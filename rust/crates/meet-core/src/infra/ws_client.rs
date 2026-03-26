use meet_type::fanout::GroupInfoSummaryData;
use proton_meet_macro::async_trait;
use std::sync::{Arc, Mutex as StdMutex};
use tokio::sync::{oneshot, Mutex};

use futures::{
    stream::{SplitSink, SplitStream},
    SinkExt, StreamExt,
};
use std::collections::{HashMap, HashSet};
use std::time::Duration;
use tokio_tungstenite_wasm::{Message as TungsteniteMessage, WebSocketStream};
use url::Url;
use uuid::Uuid;

use crate::{
    domain::user::ports::{
        ConnectionState, WebSocketClient, WebSocketDisconnectionHandler, WebSocketMessageHandler,
        WebSocketStatus,
    },
    infra::dto::websocket::{
        WebSocketTextRequest, WebSocketTextRequestCommand, WebSocketTextResponse,
        WebSocketTextResponseCommand,
    },
    utils,
};
#[cfg(not(target_family = "wasm"))]
use tokio::time::*;
#[cfg(target_family = "wasm")]
use wasmtimer::tokio::*;

#[cfg(not(target_family = "wasm"))]
use std::time::Instant;
#[cfg(target_family = "wasm")]
use wasmtimer::std::Instant;

const MAX_RETRY_COUNT: u32 = 5;
const RETRY_DELAY_SECONDS: u64 = 1;
const DEFAULT_PING_INTERVAL_SECONDS: u64 = 5;
const DEFAULT_MAX_PING_FAILURES: u32 = 2;
const DEFAULT_PONG_TIMEOUT_SECONDS: u64 = 3;

// Heartbeat message types
const HEARTBEAT_PING: u8 = 0x01;
const HEARTBEAT_PONG: u8 = 0x02;
const HEARTBEAT_MSG_SIZE: usize = 25; // 1 byte type + 16 bytes UUID + 8 bytes timestamp

#[cfg(target_family = "wasm")]
fn set_cookie_js(cookie_string: &str) -> bool {
    use wasm_bindgen::JsCast;

    let Some(window) = web_sys::window() else {
        return false;
    };
    let Some(document) = window.document() else {
        return false;
    };
    let Ok(html_document) = document.dyn_into::<web_sys::HtmlDocument>() else {
        return false;
    };

    html_document.set_cookie(cookie_string).is_ok()
}

#[cfg(target_family = "wasm")]
fn set_ws_auth_cookie(url: &Url, base64_sd_kbt: &str) -> Result<(), anyhow::Error> {
    let mut cookie = format!("meet-token={base64_sd_kbt}");

    // Restrict this cookie to the websocket endpoint path.
    let path = url.path();
    if path.is_empty() {
        cookie.push_str("; Path=/");
    } else {
        cookie.push_str(&format!("; Path={path}"));
    }

    if let Some(domain) = url.host_str() {
        cookie.push_str(&format!("; Domain={domain}"));
    }

    if url.scheme() == "wss" {
        cookie.push_str("; Secure");
    }

    cookie.push_str("; SameSite=Strict");

    if !set_cookie_js(&cookie) {
        return Err(anyhow::anyhow!(
            "Failed to set websocket auth cookie meet-token"
        ));
    }

    Ok(())
}

#[cfg(target_family = "wasm")]
fn clear_ws_auth_cookie(url: &Url) -> Result<(), anyhow::Error> {
    let mut cookie = "meet-token=".to_string();

    let path = url.path();
    if path.is_empty() {
        cookie.push_str("; Path=/");
    } else {
        cookie.push_str(&format!("; Path={path}"));
    }

    if let Some(domain) = url.host_str() {
        cookie.push_str(&format!("; Domain={domain}"));
    }

    if url.scheme() == "wss" {
        cookie.push_str("; Secure");
    }

    cookie.push_str("; SameSite=Strict");
    cookie.push_str("; Expires=Thu, 01 Jan 1970 00:00:00 GMT");

    if !set_cookie_js(&cookie) {
        return Err(anyhow::anyhow!(
            "Failed to clear websocket auth cookie meet-token"
        ));
    }

    Ok(())
}

/// Serialize a heartbeat message to binary format
fn serialize_heartbeat(msg_type: u8, id: Uuid, timestamp: u64) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(HEARTBEAT_MSG_SIZE);
    bytes.push(msg_type);
    bytes.extend_from_slice(id.as_bytes());
    bytes.extend_from_slice(&timestamp.to_le_bytes());
    bytes
}

/// Deserialize a heartbeat message from binary format
fn deserialize_heartbeat(data: &[u8]) -> Option<(u8, Uuid, u64)> {
    if data.len() != HEARTBEAT_MSG_SIZE {
        return None;
    }

    let msg_type = data[0];
    let uuid_bytes: [u8; 16] = data[1..17].try_into().ok()?;
    let id = Uuid::from_bytes(uuid_bytes);
    let timestamp_bytes: [u8; 8] = data[17..25].try_into().ok()?;
    let timestamp = u64::from_le_bytes(timestamp_bytes);

    Some((msg_type, id, timestamp))
}

/// Check if a message is a heartbeat message
fn is_heartbeat_message(data: &[u8]) -> bool {
    data.len() == HEARTBEAT_MSG_SIZE && (data[0] == HEARTBEAT_PING || data[0] == HEARTBEAT_PONG)
}

/// Pending ping tracking
struct PendingPing {
    sent_at: Instant,
    timestamp: u64, // The actual timestamp sent in the message
}

/// A wrapper around WebSocket messages
#[derive(Debug, Clone)]
pub enum WebSocketMessage {
    Text(String),
    Binary(Vec<u8>),
    Close(Option<String>),
}

impl From<TungsteniteMessage> for WebSocketMessage {
    fn from(msg: TungsteniteMessage) -> Self {
        match msg {
            TungsteniteMessage::Text(text) => WebSocketMessage::Text(text.to_string()),
            TungsteniteMessage::Binary(data) => WebSocketMessage::Binary(data.to_vec()),
            TungsteniteMessage::Close(close_frame) => {
                WebSocketMessage::Close(close_frame.map(|c| c.reason.to_string()))
            }
        }
    }
}

impl From<WebSocketMessage> for TungsteniteMessage {
    fn from(msg: WebSocketMessage) -> Self {
        match msg {
            WebSocketMessage::Text(text) => TungsteniteMessage::Text(text.into()),
            WebSocketMessage::Binary(data) => TungsteniteMessage::Binary(data.into()),
            WebSocketMessage::Close(_) => TungsteniteMessage::Close(None),
        }
    }
}

// #[cfg(not(target_family = "wasm"))]
// type MessageHandler = Box<
//     dyn FnMut(WebSocketMessage) -> Box<dyn Future<Output = ()> + Unpin + Send> + Send + 'static,
// >;

// #[cfg(target_family = "wasm")]
// type MessageHandler =
//     Box<dyn FnMut(WebSocketMessage) -> Box<dyn Future<Output = ()> + Unpin> + 'static>;

// // Disconnection callback types
// #[cfg(target_family = "wasm")]
// type DisconnectionHandler = Box<dyn FnMut(bool) + 'static>;

// #[cfg(not(target_family = "wasm"))]
// type DisconnectionHandler = Box<dyn FnMut(bool) + Send + 'static>;

#[derive(Clone)]
pub struct WsClient {
    ws_sender: Arc<Mutex<Option<SplitSink<WebSocketStream, TungsteniteMessage>>>>,
    ws_receiver: Arc<Mutex<Option<SplitStream<WebSocketStream>>>>,
    token: Arc<Mutex<Option<String>>>,
    connection_state: Arc<Mutex<WebSocketStatus>>,
    host: String,
    message_handler: Arc<Mutex<Option<Arc<WebSocketMessageHandler>>>>,
    disconnection_callback: Arc<Mutex<Option<Arc<WebSocketDisconnectionHandler>>>>,
    pending_pings: Arc<Mutex<HashMap<Uuid, PendingPing>>>,
    pending_text_requests:
        Arc<Mutex<HashMap<String, oneshot::Sender<WebSocketTextResponseCommand>>>>,
    timed_out_text_requests: Arc<Mutex<HashSet<String>>>,
    ping_interval_seconds: Arc<Mutex<Option<u64>>>,
    max_ping_failures: Arc<Mutex<Option<u32>>>,
    pong_timeout_seconds: Arc<Mutex<Option<u64>>>,
    listener_generation: Arc<StdMutex<u64>>,
    enable_prod_tls_pinning: bool,
}

impl WsClient {
    pub fn new(host: String) -> Self {
        Self::new_with_prod_tls_pinning(host, true)
    }

    pub fn new_with_prod_tls_pinning(host: String, enable_prod_tls_pinning: bool) -> Self {
        Self {
            ws_sender: Arc::new(Mutex::new(None)),
            ws_receiver: Arc::new(Mutex::new(None)),
            token: Arc::new(Mutex::new(None)),
            connection_state: Arc::new(Mutex::new(WebSocketStatus {
                connection_state: ConnectionState::Disconnected,
                retry_count: 0,
                intentional_disconnection: false,
                has_reconnected: false, // set false by default
                last_rtt_ms: None,
                last_ping_timestamp: None,
                last_pong_timestamp: None,
            })),
            host,
            message_handler: Arc::new(Mutex::new(None)),
            disconnection_callback: Arc::new(Mutex::new(None)),
            pending_pings: Arc::new(Mutex::new(HashMap::new())),
            pending_text_requests: Arc::new(Mutex::new(HashMap::new())),
            timed_out_text_requests: Arc::new(Mutex::new(HashSet::new())),
            ping_interval_seconds: Arc::new(Mutex::new(None)),
            max_ping_failures: Arc::new(Mutex::new(None)),
            pong_timeout_seconds: Arc::new(Mutex::new(None)),
            listener_generation: Arc::new(StdMutex::new(0)),
            enable_prod_tls_pinning,
        }
    }

    /// Get ping interval in seconds, using configured value or default
    async fn get_ping_interval_seconds(&self) -> u64 {
        let guard = self.ping_interval_seconds.lock().await;
        guard.unwrap_or(DEFAULT_PING_INTERVAL_SECONDS)
    }

    /// Get max ping failures, using configured value or default
    async fn get_max_ping_failures(&self) -> u32 {
        let guard = self.max_ping_failures.lock().await;
        guard.unwrap_or(DEFAULT_MAX_PING_FAILURES)
    }

    /// Get pong timeout in seconds, using configured value or default
    async fn get_pong_timeout_seconds(&self) -> u64 {
        let guard = self.pong_timeout_seconds.lock().await;
        guard.unwrap_or(DEFAULT_PONG_TIMEOUT_SECONDS)
    }

    /// Set ping interval in seconds (None to use default)
    pub async fn set_ping_interval_seconds(&self, seconds: Option<u64>) {
        let mut guard = self.ping_interval_seconds.lock().await;
        *guard = seconds;
    }

    /// Set max ping failures (None to use default)
    pub async fn set_max_ping_failures(&self, failures: Option<u32>) {
        let mut guard = self.max_ping_failures.lock().await;
        *guard = failures;
    }

    /// Set pong timeout in seconds (None to use default)
    pub async fn set_pong_timeout_seconds(&self, seconds: Option<u64>) {
        let mut guard = self.pong_timeout_seconds.lock().await;
        *guard = seconds;
    }

    /// Helper function to build a WebSocket URL from host and a path
    fn build_ws_url(&self, path: &str) -> Result<Url, anyhow::Error> {
        let mut base = self.host.trim_end_matches('/').to_string();

        // Add back trailing slash if the base has a path component
        // This ensures URL::join doesn't replace the last segment
        if base.contains('/') && !base.ends_with('/') {
            base.push('/');
        }

        let base_url = if base.starts_with("wss://") {
            base
        } else {
            format!("wss://{base}")
        };
        let url = Url::parse(&base_url)?.join(path)?;
        Ok(url)
    }

    /// Get current intentional disconnection status
    async fn get_intentional_disconnection(&self) -> bool {
        self.connection_state.lock().await.intentional_disconnection
    }

    async fn register_pending_text_request(
        &self,
        request_id: &str,
    ) -> Result<oneshot::Receiver<WebSocketTextResponseCommand>, anyhow::Error> {
        let (tx, rx) = oneshot::channel::<WebSocketTextResponseCommand>();
        {
            let mut timed_out = self.timed_out_text_requests.lock().await;
            timed_out.remove(request_id);
        }
        let mut pending = self.pending_text_requests.lock().await;
        if pending.contains_key(request_id) {
            return Err(anyhow::anyhow!(
                "duplicate websocket request_id in flight: {request_id}"
            ));
        }
        pending.insert(request_id.to_string(), tx);
        Ok(rx)
    }

    async fn clear_pending_text_request(&self, request_id: &str) {
        let mut pending = self.pending_text_requests.lock().await;
        pending.remove(request_id);
    }

    async fn mark_text_request_timed_out(&self, request_id: &str) {
        const MAX_TIMED_OUT_REQUEST_IDS: usize = 1024;
        let mut timed_out = self.timed_out_text_requests.lock().await;
        if timed_out.len() >= MAX_TIMED_OUT_REQUEST_IDS {
            if let Some(oldest_seen) = timed_out.iter().next().cloned() {
                timed_out.remove(&oldest_seen);
            }
        }
        timed_out.insert(request_id.to_string());
    }

    fn create_text_request(
        &self,
        command: WebSocketTextRequestCommand,
    ) -> (String, WebSocketTextRequest) {
        let request_id = Uuid::new_v4().to_string();
        let request = WebSocketTextRequest {
            request_id: Some(request_id.clone()),
            command,
        };
        (request_id, request)
    }

    async fn wait_for_text_response(
        &self,
        request_id: &str,
        receiver: oneshot::Receiver<WebSocketTextResponseCommand>,
        timeout_duration: Duration,
    ) -> Result<WebSocketTextResponseCommand, anyhow::Error> {
        match timeout(timeout_duration, receiver).await {
            Ok(Ok(response)) => Ok(response),
            Ok(Err(_)) => {
                self.clear_pending_text_request(request_id).await;
                // Requester has gone away before response arrived; treat future response as stale.
                self.mark_text_request_timed_out(request_id).await;
                Err(anyhow::anyhow!(
                    "response channel closed for request_id={request_id}"
                ))
            }
            Err(_) => {
                self.clear_pending_text_request(request_id).await;
                self.mark_text_request_timed_out(request_id).await;
                Err(anyhow::anyhow!(
                    "timed out waiting websocket response for request_id={request_id}"
                ))
            }
        }
    }

    async fn try_resolve_text_response(&self, text: &str) -> bool {
        match serde_json::from_str::<WebSocketTextResponse>(text) {
            Ok(response) => {
                if let Some(request_id) = response.request_id {
                    let was_timed_out = {
                        let mut timed_out = self.timed_out_text_requests.lock().await;
                        timed_out.remove(&request_id)
                    };
                    if was_timed_out {
                        tracing::warn!(
                            "Discarding late websocket response for timed-out request_id={}",
                            request_id
                        );
                        return true;
                    }

                    let sender = {
                        let mut pending = self.pending_text_requests.lock().await;
                        pending.remove(&request_id)
                    };
                    if let Some(sender) = sender {
                        if sender.send(response.command).is_err() {
                            tracing::warn!(
                                "Dropped websocket response because requester is gone: request_id={}",
                                request_id
                            );
                        }
                        return true;
                    }
                }
            }
            Err(_) => {}
        }
        false
    }
}

#[async_trait]
impl WebSocketClient for WsClient {
    async fn connect(&self, base64_sd_kbt: &str) -> Result<(), anyhow::Error> {
        #[cfg(target_family = "wasm")]
        {
            let url = self.build_ws_url("v1/ws")?;
            set_ws_auth_cookie(&url, base64_sd_kbt)?;
            let connect_result = tokio_tungstenite_wasm::connect(url.as_str()).await;
            let _ = clear_ws_auth_cookie(&url);
            let ws_stream = connect_result?;

            let (write, read) = ws_stream.split();
            *self.ws_sender.lock().await = Some(write.into());
            *self.ws_receiver.lock().await = Some(read.into());
        }

        #[cfg(all(not(target_family = "wasm"), target_os = "ios"))]
        {
            use crate::infra::tls_pinning::build_prod_tls_config;
            use rustls::ClientConfig;
            use rustls_platform_verifier::ConfigVerifierExt;
            use std::sync::Arc;
            use tokio_tungstenite_wasm::Connector;
            let tls_config: Arc<ClientConfig> = if self.enable_prod_tls_pinning {
                Arc::new(build_prod_tls_config()?)
            } else {
                Arc::new(ClientConfig::with_platform_verifier()?)
            };
            // Tell tokio-tungstenite to use our rustls config
            let connector = Connector::Rustls(tls_config);

            let url = self.build_ws_url("v1/ws")?;
            let ws_stream = tokio_tungstenite_wasm::connect_with_tls_auth(
                url.as_str(),
                base64_sd_kbt,
                Some(connector),
            )
            .await?;
            let (write, read) = ws_stream.split();
            *self.ws_sender.lock().await = Some(write);
            *self.ws_receiver.lock().await = Some(read);
        }

        #[cfg(all(not(target_family = "wasm"), not(target_os = "ios")))]
        {
            use crate::infra::tls_pinning::build_prod_tls_config;
            use rustls::ClientConfig;
            use std::sync::Arc;
            use tokio_tungstenite_wasm::Connector;

            let url = self.build_ws_url("v1/ws")?;
            let ws_stream = if self.enable_prod_tls_pinning {
                let tls_config: Arc<ClientConfig> = Arc::new(build_prod_tls_config()?);
                let connector = Connector::Rustls(tls_config);
                tokio_tungstenite_wasm::connect_with_tls_auth(
                    url.as_str(),
                    base64_sd_kbt,
                    Some(connector),
                )
                .await?
            } else {
                tokio_tungstenite_wasm::connect_with_auth(url.as_str(), base64_sd_kbt).await?
            };
            let (write, read) = ws_stream.split();
            *self.ws_sender.lock().await = Some(write);
            *self.ws_receiver.lock().await = Some(read);
        }

        *self.token.lock().await = Some(base64_sd_kbt.to_string());

        let mut state = self.connection_state.lock().await;
        *state = WebSocketStatus {
            connection_state: ConnectionState::Connected,
            retry_count: 0,
            intentional_disconnection: false,
            has_reconnected: state.has_reconnected,
            last_rtt_ms: state.last_rtt_ms,
            last_ping_timestamp: state.last_ping_timestamp,
            last_pong_timestamp: state.last_pong_timestamp,
        };

        Ok(())
    }

    async fn reconnect(self) -> Result<(), anyhow::Error> {
        let mut state = self.connection_state.lock().await;
        *state = WebSocketStatus {
            connection_state: ConnectionState::Reconnecting,
            retry_count: 1,
            intentional_disconnection: false,
            has_reconnected: true, // since we are reconnecting, we need to set has_reconnected to true
            last_rtt_ms: state.last_rtt_ms,
            last_ping_timestamp: state.last_ping_timestamp,
            last_pong_timestamp: state.last_pong_timestamp,
        };
        let mut retry_count = state.retry_count;
        drop(state);

        loop {
            if retry_count > MAX_RETRY_COUNT {
                tracing::error!("WebSocket max retry count reached, disconnecting...");
                self.disconnect(None).await?;
                return Ok(());
            }

            tracing::info!(
                "Reconnecting WebSocket, retry count: ({}/{})",
                retry_count,
                MAX_RETRY_COUNT
            );

            tracing::info!("Reconnecting WebSocket, try to get token for reconnect");

            let token = {
                let token_guard = self.token.lock().await;
                let token_value = token_guard.clone();
                drop(token_guard);
                token_value
            };

            let token = token.ok_or_else(|| {
                tracing::error!("No token found during WebSocket reconnection. Token state: None");
                anyhow::anyhow!("No token found")
            })?;

            let connect_result = self.connect(&token).await;
            if connect_result.is_err() {
                sleep(std::time::Duration::from_secs(RETRY_DELAY_SECONDS)).await;
                retry_count += 1;
                tracing::warn!(
                    "Failed to reconnect WebSocket, retry count: {}/{}",
                    retry_count,
                    MAX_RETRY_COUNT
                );
                continue;
            }

            // if connect is successful, need to start listening task again and break the loop
            let _ = self.start_listening_task();
            #[cfg(debug_assertions)]
            tracing::info!("WebSocket reconnected");
            break;
        }

        Ok(())
    }

    async fn disconnect(&self, intentional: Option<bool>) -> Result<(), anyhow::Error> {
        // Reset connection state
        let mut state = self.connection_state.lock().await;
        *state = WebSocketStatus {
            connection_state: ConnectionState::Disconnected,
            retry_count: 0,
            intentional_disconnection: intentional.unwrap_or(false),
            has_reconnected: state.has_reconnected,
            last_rtt_ms: state.last_rtt_ms,
            last_ping_timestamp: state.last_ping_timestamp,
            last_pong_timestamp: state.last_pong_timestamp,
        };
        drop(state);

        let mut sender_guard = self.ws_sender.lock().await;
        if let Some(sender) = sender_guard.as_mut() {
            if let Err(err) = sender.close().await {
                tracing::warn!(
                    "Failed to close sender when disconnecting websocket: {:?}",
                    err
                );
            }
        }
        *sender_guard = None;
        *self.ws_receiver.lock().await = None;
        self.pending_text_requests.lock().await.clear();
        self.timed_out_text_requests.lock().await.clear();

        // Only clear token on intentional disconnect; preserve for reconnection
        if intentional == Some(true) {
            tracing::info!("Disconnecting WebSocket intentionally (explicitly set to true)");
            *self.token.lock().await = None;
        }

        // Call disconnection callback if set
        // Extract callback outside the lock to prevent deadlock if callback tries to access ws_client
        let callback_opt = {
            let mut callback_guard = self.disconnection_callback.lock().await;
            callback_guard.take() // Take ownership to call outside the lock
        };
        // callback_guard now contains None

        if let Some(callback) = callback_opt {
            callback(intentional.unwrap_or(true)); // Call outside lock to prevent deadlock
        } else {
            tracing::info!("No disconnection callback set");
        }
        #[cfg(debug_assertions)]
        tracing::info!("Disconnected from WebSocket");
        Ok(())
    }

    async fn send_message(&self, message: WebSocketMessage) -> Result<(), anyhow::Error> {
        // Check connection state before attempting to send
        let connection_state = {
            let state = self.connection_state.lock().await;
            state.connection_state.clone()
        };

        if connection_state != ConnectionState::Connected {
            tracing::warn!(
                "Cannot send message, connection state is {:?}",
                connection_state
            );
            return Err(anyhow::anyhow!(
                "WebSocket not connected (state: {connection_state:?}), cannot send message"
            ));
        }

        let mut sender_guard = self.ws_sender.lock().await;
        if let Some(sender) = sender_guard.as_mut() {
            #[cfg(not(target_family = "wasm"))]
            {
                // Add timeout to prevent indefinite blocking if connection is closed
                match timeout(Duration::from_secs(5), sender.send(message.into())).await {
                    Ok(Ok(_)) => {
                        tracing::debug!(" Message sent successfully");
                        Ok(())
                    }
                    Ok(Err(e)) => Err(anyhow::anyhow!("Failed to send WebSocket message: {e}")),
                    Err(_) => {
                        tracing::error!("Send message timed out after 5 seconds");
                        Err(anyhow::anyhow!("WebSocket send timed out"))
                    }
                }
            }
            #[cfg(target_family = "wasm")]
            {
                // For wasm, sender.send should fail quickly if closed
                match sender.send(message.into()).await {
                    Ok(_) => {
                        tracing::debug!("Message sent successfully");
                        Ok(())
                    }
                    Err(e) => {
                        tracing::error!("Failed to send message: {:?}", e);
                        Err(anyhow::anyhow!("Failed to send WebSocket message: {}", e))
                    }
                }
            }
        } else {
            tracing::warn!("WebSocket sender not initialized");
            Err(anyhow::anyhow!("WebSocket sender not initialized"))
        }
    }

    async fn send_text_request_and_wait(
        &self,
        command: WebSocketTextRequestCommand,
        timeout_duration: Duration,
    ) -> Result<WebSocketTextResponseCommand, anyhow::Error> {
        let (request_id, request) = self.create_text_request(command);
        let receiver = self.register_pending_text_request(&request_id).await?;
        let payload = serde_json::to_string(&request)?;

        if let Err(error) = self.send_message(WebSocketMessage::Text(payload)).await {
            self.clear_pending_text_request(&request_id).await;
            return Err(error);
        }

        self.wait_for_text_response(&request_id, receiver, timeout_duration)
            .await
    }

    fn start_listening_task(&self) -> Result<(), anyhow::Error> {
        let listener_generation = {
            let mut generation = self
                .listener_generation
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            *generation = generation.wrapping_add(1);
            *generation
        };
        let receiver_arc = self.ws_receiver.clone();
        let handler_arc = self.message_handler.clone();
        let connection_state_arc = self.connection_state.clone();
        let sender_arc = self.ws_sender.clone();
        let pending_pings_arc = self.pending_pings.clone();
        let ping_interval_arc = self.ping_interval_seconds.clone();
        let max_ping_failures_arc = self.max_ping_failures.clone();
        let pong_timeout_arc = self.pong_timeout_seconds.clone();
        let listener_generation_arc = self.listener_generation.clone();
        let self_clone = self.clone();

        #[cfg(debug_assertions)]
        tracing::info!("Starting listening task");

        utils::spawn_detached(async move {
            // Extract receiver immediately
            let mut receiver = match receiver_arc.lock().await.take() {
                Some(r) => r,
                None => {
                    tracing::error!("No receiver available");
                    return;
                }
            };

            // Get initial ping interval
            let ping_interval_secs = {
                let guard = ping_interval_arc.lock().await;
                guard.unwrap_or(DEFAULT_PING_INTERVAL_SECONDS)
            };
            let mut ping_interval = interval(std::time::Duration::from_secs(ping_interval_secs));
            ping_interval.tick().await; // Skip first immediate tick
            let mut ping_failed_count = 0u32;

            loop {
                let is_stale_listener = {
                    let generation = listener_generation_arc
                        .lock()
                        .unwrap_or_else(|poisoned| poisoned.into_inner());
                    *generation != listener_generation
                };
                if is_stale_listener {
                    tracing::info!(
                        "Listener task generation {} is stale, exiting",
                        listener_generation
                    );
                    break;
                }

                // Get current max ping failures (may have changed)
                let max_ping_failures = {
                    let guard = max_ping_failures_arc.lock().await;
                    guard.unwrap_or(DEFAULT_MAX_PING_FAILURES)
                };

                // Single state check per iteration
                let is_disconnected = {
                    let state = connection_state_arc.lock().await;
                    state.connection_state == ConnectionState::Disconnected
                };

                if is_disconnected || ping_failed_count >= max_ping_failures {
                    tracing::info!(
                        "Breaking loop: disconnected={} ping_failures={}",
                        is_disconnected,
                        ping_failed_count
                    );
                    break;
                }

                // Get current pong timeout (may have changed)
                let pong_timeout_secs = {
                    let guard = pong_timeout_arc.lock().await;
                    guard.unwrap_or(DEFAULT_PONG_TIMEOUT_SECONDS)
                };

                // Check for stale pings (no pong received within timeout)
                {
                    let mut pending = pending_pings_arc.lock().await;
                    let now = Instant::now();
                    let stale_count = pending
                        .iter()
                        .filter(|(_, ping)| {
                            now.duration_since(ping.sent_at).as_secs() > pong_timeout_secs
                        })
                        .count();

                    if stale_count > 0 {
                        ping_failed_count += stale_count as u32;
                        pending.retain(|_, ping| {
                            now.duration_since(ping.sent_at).as_secs() <= pong_timeout_secs
                        });
                        tracing::warn!(
                            "Found {} stale pings without pongs (total failures: {}/{})",
                            stale_count,
                            ping_failed_count,
                            max_ping_failures
                        );
                    }
                }

                match utils::select(receiver.next(), ping_interval.tick()).await {
                    // Message received
                    utils::SelectResult::First(msg_result) => {
                        match msg_result {
                            Some(Ok(msg)) => {
                                // Check if this is a heartbeat pong
                                if let TungsteniteMessage::Binary(ref data) = msg {
                                    if is_heartbeat_message(data) {
                                        if let Some((msg_type, id, pong_timestamp)) =
                                            deserialize_heartbeat(data)
                                        {
                                            if msg_type == HEARTBEAT_PONG {
                                                // Handle pong
                                                let mut pending = pending_pings_arc.lock().await;
                                                if let Some(pending_ping) = pending.remove(&id) {
                                                    // Calculate RTT using timestamps
                                                    let now_timestamp =
                                                        crate::utils::time::unix_timestamp_ms();
                                                    let rtt_ms = now_timestamp
                                                        .saturating_sub(pending_ping.timestamp);
                                                    ping_failed_count = 0; // Reset on successful pong
                                                    tracing::debug!(
                                                        "Pong received for ping {}, RTT: {}ms, timestamp match: {}",
                                                        id,
                                                        rtt_ms,
                                                        pending_ping.timestamp == pong_timestamp
                                                    );
                                                    {
                                                        let mut state =
                                                            connection_state_arc.lock().await;
                                                        state.last_rtt_ms = Some(rtt_ms as u32);
                                                        state.last_ping_timestamp =
                                                            Some(pending_ping.timestamp);
                                                        state.last_pong_timestamp =
                                                            Some(pong_timestamp);
                                                    }
                                                } else {
                                                    tracing::warn!(
                                                        "Received pong for unknown ping ID: {}",
                                                        id
                                                    );
                                                }
                                                continue; // Don't pass to application handler
                                            }
                                        }
                                    }
                                }

                                if let TungsteniteMessage::Text(ref text) = msg {
                                    if self_clone.try_resolve_text_response(text.as_ref()).await {
                                        continue;
                                    }
                                }

                                let wrapped_msg = WebSocketMessage::from(msg);
                                #[cfg(debug_assertions)]
                                tracing::info!("Received websocket message");

                                // Clone handler Arc outside lock
                                if let Some(handler) = handler_arc.lock().await.clone() {
                                    handler(wrapped_msg).await;
                                    tracing::info!("Message handler called");
                                } else {
                                    tracing::error!("No message handler set");
                                }
                            }
                            Some(Err(e)) => {
                                tracing::error!("WebSocket error: {}", e);
                                break;
                            }
                            None => {
                                tracing::info!("Receiver stream ended");
                                break;
                            }
                        }
                    }

                    // Ping interval tick
                    utils::SelectResult::Second(_) => {
                        let timestamp = crate::utils::time::unix_timestamp_ms();
                        let ping_id = Uuid::new_v4();

                        let ping_bytes = serialize_heartbeat(HEARTBEAT_PING, ping_id, timestamp);

                        let ping_result = async {
                            let mut sender_guard = sender_arc.lock().await;
                            match sender_guard.as_mut() {
                                Some(sender) => {
                                    #[cfg(not(target_family = "wasm"))]
                                    {
                                        timeout(
                                            Duration::from_secs(5),
                                            sender.send(TungsteniteMessage::Binary(
                                                ping_bytes.into(),
                                            )),
                                        )
                                        .await
                                        .map_err(|_| anyhow::anyhow!("Ping timeout"))?
                                        .map_err(|e| anyhow::anyhow!("Ping send error: {e:?}"))
                                    }
                                    #[cfg(target_family = "wasm")]
                                    {
                                        sender
                                            .send(TungsteniteMessage::Binary(ping_bytes.into()))
                                            .await
                                            .map_err(|e| anyhow::anyhow!("Ping send error: {}", e))
                                    }
                                }
                                None => Err(anyhow::anyhow!("Sender not available")),
                            }
                        }
                        .await;

                        match ping_result {
                            Ok(_) => {
                                // Store pending ping with the same timestamp that was sent
                                let mut pending = pending_pings_arc.lock().await;
                                pending.insert(
                                    ping_id,
                                    PendingPing {
                                        sent_at: Instant::now(),
                                        timestamp,
                                    },
                                );
                                tracing::debug!(
                                    "Ping sent successfully: {} at {}",
                                    ping_id,
                                    timestamp
                                );
                            }
                            Err(e) => {
                                ping_failed_count += 1;
                                // Get current max ping failures (may have changed)
                                let max_ping_failures = {
                                    let guard = max_ping_failures_arc.lock().await;
                                    guard.unwrap_or(DEFAULT_MAX_PING_FAILURES)
                                };
                                tracing::warn!(
                                    "Ping failed ({}/{}): {:?}",
                                    ping_failed_count,
                                    max_ping_failures,
                                    e
                                );

                                if ping_failed_count >= max_ping_failures {
                                    tracing::error!(
                                        "Max ping failures reached, triggering disconnect"
                                    );
                                    let mut state = connection_state_arc.lock().await;
                                    state.connection_state = ConnectionState::Disconnected;
                                    state.intentional_disconnection = false;
                                    break;
                                }
                            }
                        }
                    }
                }
            }

            tracing::info!("Receiver loop exited");

            let is_latest_listener = {
                let generation = listener_generation_arc
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner());
                *generation == listener_generation
            };
            if !is_latest_listener {
                tracing::info!(
                    "Listener task generation {} exited stale, skipping cleanup/reconnect",
                    listener_generation
                );
                return;
            }

            // Check if reconnection is needed
            let intentional_disconnection =
                connection_state_arc.lock().await.intentional_disconnection;
            tracing::info!("Intentional disconnection: {}", intentional_disconnection);

            {
                let mut pending = pending_pings_arc.lock().await;
                pending.clear();
            }
            self_clone.pending_text_requests.lock().await.clear();
            self_clone.timed_out_text_requests.lock().await.clear();

            if !intentional_disconnection {
                tracing::info!("Reconnecting");
                let _ = self_clone.reconnect().await;
            }
        });

        Ok(())
    }

    async fn set_message_handler(&self, callback: Arc<WebSocketMessageHandler>) {
        let mut lock = self.message_handler.lock().await;
        *lock = Some(callback);
    }
    async fn set_disconnection_handler(&self, callback: Arc<WebSocketDisconnectionHandler>) {
        #[cfg(debug_assertions)]
        tracing::info!("Setting disconnection handler");
        let mut cb = self.disconnection_callback.lock().await;
        *cb = Some(callback);
    }

    /// Get current connection state
    async fn get_connection_state(&self) -> ConnectionState {
        self.connection_state.lock().await.connection_state.clone()
    }

    /// Get if the websocket has reconnected
    async fn get_has_reconnected(&self) -> bool {
        self.connection_state.lock().await.has_reconnected
    }

    /// Manually trigger a reconnection (e.g., when network connectivity changes).
    async fn trigger_reconnect(&self) -> Result<(), anyhow::Error> {
        let current_state = self.get_connection_state().await;

        match current_state {
            ConnectionState::Reconnecting => {
                tracing::debug!("Reconnection already in progress, skipping trigger");
                return Ok(());
            }
            ConnectionState::Connected => {
                tracing::debug!("WebSocket is already connected, skipping trigger");
                return Ok(());
            }
            ConnectionState::Connecting => {
                tracing::debug!("WebSocket is connecting, skipping trigger");
                return Ok(());
            }
            ConnectionState::Disconnected => {
                if self.get_intentional_disconnection().await {
                    return Ok(());
                }
                // Check if we have a token to reconnect with
                let has_token = self.token.lock().await.is_some();
                if !has_token {
                    tracing::warn!(
                        "Cannot trigger reconnect: WebSocket is disconnected and no token available"
                    );
                    return Err(anyhow::anyhow!("No token available for reconnection"));
                }
                tracing::debug!("Triggering reconnect from disconnected state");
                return self.clone().reconnect().await;
            }
        }
    }

    async fn get_last_rtt_ms(&self) -> Option<u32> {
        self.connection_state.lock().await.last_rtt_ms
    }

    async fn set_ping_interval_seconds(&self, seconds: Option<u64>) {
        let mut guard = self.ping_interval_seconds.lock().await;
        *guard = seconds;
    }

    async fn set_max_ping_failures(&self, failures: Option<u32>) {
        let mut guard = self.max_ping_failures.lock().await;
        *guard = failures;
    }

    async fn set_pong_timeout_seconds(&self, seconds: Option<u64>) {
        let mut guard = self.pong_timeout_seconds.lock().await;
        *guard = seconds;
    }

    async fn get_group_info_summary(&self) -> Result<GroupInfoSummaryData, anyhow::Error> {
        let ping_interval_seconds = self.get_ping_interval_seconds().await;
        let response = self
            .send_text_request_and_wait(
                WebSocketTextRequestCommand::GroupInfoSummary,
                Duration::from_secs(ping_interval_seconds),
            )
            .await?;
        match response {
            WebSocketTextResponseCommand::GroupInfoSummary(response) => {
                if let Some(epoch) = response.epoch {
                    if let Some(group_id) = response.group_id {
                        Ok(GroupInfoSummaryData { epoch, group_id })
                    } else {
                        Err(anyhow::anyhow!("GroupInfoSummary is empty"))
                    }
                } else {
                    Err(anyhow::anyhow!("GroupInfoSummary is empty"))
                }
            }
            _ => Err(anyhow::anyhow!("Expected GroupInfoSummary response")),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_text_request_generates_request_id() {
        let client = WsClient::new("localhost".to_string());
        let (request_id, request) =
            client.create_text_request(WebSocketTextRequestCommand::GroupInfoSummary);

        assert!(Uuid::parse_str(&request_id).is_ok());
        assert_eq!(request.request_id, Some(request_id));
        assert!(matches!(
            request.command,
            WebSocketTextRequestCommand::GroupInfoSummary
        ));
    }

    #[cfg(not(target_family = "wasm"))]
    #[tokio::test]
    async fn try_resolve_text_response_matches_waiter() {
        let client = WsClient::new("localhost".to_string());
        let receiver = client
            .register_pending_text_request("req-1")
            .await
            .expect("register should succeed");

        let response_json = serde_json::to_string(&WebSocketTextResponse {
            request_id: Some("req-1".to_string()),
            command: WebSocketTextResponseCommand::Unknown(
                crate::infra::dto::websocket::UnknownWebSocketCommand {
                    command: "InitAck".to_string(),
                    payload: None,
                },
            ),
        })
        .expect("response should serialize");

        let resolved = client.try_resolve_text_response(&response_json).await;

        assert!(resolved);
        let response = receiver.await.expect("receiver should resolve");
        assert!(matches!(response, WebSocketTextResponseCommand::Unknown(_)));
    }

    #[cfg(not(target_family = "wasm"))]
    #[tokio::test]
    async fn try_resolve_text_response_unmatched_waiter_falls_through() {
        let client = WsClient::new("localhost".to_string());
        let resolved = client
            .try_resolve_text_response(r#"{"RequestId":"missing","Command":"GroupInfoSummary"}"#)
            .await;
        assert!(!resolved);
    }

    #[cfg(not(target_family = "wasm"))]
    #[tokio::test]
    async fn wait_for_text_response_timeout_clears_pending() {
        let client = WsClient::new("localhost".to_string());
        let receiver = client
            .register_pending_text_request("req-timeout")
            .await
            .expect("register should succeed");

        let result = client
            .wait_for_text_response(
                "req-timeout",
                receiver,
                std::time::Duration::from_millis(20),
            )
            .await;

        assert!(result.is_err());
        let pending = client.pending_text_requests.lock().await;
        assert!(!pending.contains_key("req-timeout"));
    }

    #[cfg(not(target_family = "wasm"))]
    #[tokio::test]
    async fn late_text_response_after_timeout_is_discarded() {
        let client = WsClient::new("localhost".to_string());
        let receiver = client
            .register_pending_text_request("req-late-timeout")
            .await
            .expect("register should succeed");

        let result = client
            .wait_for_text_response(
                "req-late-timeout",
                receiver,
                std::time::Duration::from_millis(20),
            )
            .await;
        assert!(result.is_err());

        let timed_out_before = client.timed_out_text_requests.lock().await;
        assert!(
            timed_out_before.contains("req-late-timeout"),
            "request should be marked timed-out before late response is handled"
        );
        drop(timed_out_before);

        let response_json = serde_json::to_string(&WebSocketTextResponse {
            request_id: Some("req-late-timeout".to_string()),
            command: WebSocketTextResponseCommand::Unknown(
                crate::infra::dto::websocket::UnknownWebSocketCommand {
                    command: "InitAck".to_string(),
                    payload: None,
                },
            ),
        })
        .expect("response should serialize");

        let resolved = client.try_resolve_text_response(&response_json).await;
        assert!(resolved, "late response should be consumed and discarded");

        let pending = client.pending_text_requests.lock().await;
        assert!(!pending.contains_key("req-late-timeout"));
        drop(pending);
        let timed_out = client.timed_out_text_requests.lock().await;
        assert!(
            !timed_out.contains("req-late-timeout"),
            "timed-out marker should be removed once late response is handled"
        );
    }

    #[test]
    fn build_ws_url_preserves_base_path() {
        let client = WsClient::new("meet.proton.me/meet/api".to_string());
        let url = client.build_ws_url("v1/ws").expect("url should build");
        assert_eq!(url.as_str(), "wss://meet.proton.me/meet/api/v1/ws");
    }
}
