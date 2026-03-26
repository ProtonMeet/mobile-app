use meet_type::fanout::GroupInfoSummaryData;
use proton_meet_macro::async_trait_with_mock;
use std::time::Duration;

use crate::domain::user::ports::{WebSocketDisconnectionHandler, WebSocketMessageHandler};
use crate::infra::dto::websocket::{WebSocketTextRequestCommand, WebSocketTextResponseCommand};
use crate::infra::ws_client::WebSocketMessage;
use std::sync::Arc;

#[derive(Debug, Clone, PartialEq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
}

#[derive(Debug)]
pub struct WebSocketStatus {
    pub connection_state: ConnectionState,
    pub retry_count: u32,
    pub intentional_disconnection: bool,
    pub has_reconnected: bool,
    pub last_rtt_ms: Option<u32>,
    pub last_ping_timestamp: Option<u64>,
    pub last_pong_timestamp: Option<u64>,
}

#[cfg(not(target_family = "wasm"))]
pub type ArcWebSocketClient = Arc<dyn WebSocketClient + Send + Sync>;
#[cfg(target_family = "wasm")]
pub type ArcWebSocketClient = Arc<dyn WebSocketClient>;

#[async_trait_with_mock]
pub trait WebSocketClient {
    async fn connect(&self, base64_sd_kbt: &str) -> Result<(), anyhow::Error>;
    async fn reconnect(self) -> Result<(), anyhow::Error>;
    async fn disconnect(&self, intentional: Option<bool>) -> Result<(), anyhow::Error>;
    async fn send_message(&self, message: WebSocketMessage) -> Result<(), anyhow::Error>;
    async fn send_text_request_and_wait(
        &self,
        command: WebSocketTextRequestCommand,
        timeout_duration: Duration,
    ) -> Result<WebSocketTextResponseCommand, anyhow::Error>;
    fn start_listening_task(&self) -> Result<(), anyhow::Error>;
    async fn get_connection_state(&self) -> ConnectionState;
    async fn get_last_rtt_ms(&self) -> Option<u32>;
    async fn get_has_reconnected(&self) -> bool;
    /// Manually trigger a reconnection (e.g., when network connectivity changes)
    async fn trigger_reconnect(&self) -> Result<(), anyhow::Error>;

    /// callbacks
    async fn set_message_handler(&self, callback: Arc<WebSocketMessageHandler>);
    async fn set_disconnection_handler(&self, callback: Arc<WebSocketDisconnectionHandler>);

    /// Configuration methods (optional - implementations can provide no-op if not supported)
    async fn set_ping_interval_seconds(&self, _seconds: Option<u64>) {}
    async fn set_max_ping_failures(&self, _failures: Option<u32>) {}
    async fn set_pong_timeout_seconds(&self, _seconds: Option<u64>) {}

    async fn get_group_info_summary(&self) -> Result<GroupInfoSummaryData, anyhow::Error>;
}
