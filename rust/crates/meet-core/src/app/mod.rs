use crate::app_state::{AppState, UserState};
use crate::domain::mls::ports::KeyPackagePort;
use crate::domain::room::{RoomService, WaitingRoomService};
use crate::domain::user::models::{
    participant_track_settings::ParticipantTrackSettings, user_settings::UserSettings,
    UnleashResponse,
};
use crate::domain::user::ports::crypto_client::CryptoClient;
use crate::domain::user::ports::meeting_api::MeetingApi;
use crate::domain::user::ports::{
    ArcWebSocketClient, EventApi, HttpClient, MlsApi, UnleashApi, UserService, WebSocketClient,
};
use crate::errors::core::MeetCoreError;
use crate::infra::muon::is_prod_environment;
#[cfg(not(target_arch = "wasm32"))]
use crate::infra::muon::AuthStore;
use crate::infra::{
    crypto_client::MeetCryptoClient,
    http_client::{ApiConfig, ProtonHttpClient},
    ports::user_key_provider::UserKeyProvider,
    storage::persister::Persister,
    ws_client::WsClient,
};
use crate::service::mls_service::MlsService;
use crate::service::service::Service;
use proton_meet_mls::{MlsClientConfig, MlsStore};
use std::{collections::HashMap, future::Future, sync::Arc};
use tokio::sync::RwLock;
use tracing::error;

#[cfg(target_family = "wasm")]
use {wasm_bindgen::prelude::wasm_bindgen, wasm_bindgen::JsValue};

mod agent;
mod auth;
mod chat;
#[cfg(not(target_arch = "wasm32"))]
mod event;
mod join;
mod meetings;
mod metrics;
mod prejoin;
mod server_time;
mod user_state;
mod waiting_room;
mod websocket;

#[cfg(all(test, not(target_family = "wasm")))]
mod test_support;

#[cfg(all(test, not(target_family = "wasm")))]
mod auth_test;
#[cfg(all(test, not(target_family = "wasm")))]
mod chat_test;
#[cfg(all(test, not(target_family = "wasm")))]
mod event_test;
#[cfg(all(test, not(target_family = "wasm")))]
mod join_test;
#[cfg(all(test, not(target_family = "wasm")))]
mod meetings_test;
#[cfg(all(test, not(target_family = "wasm")))]
mod metrics_test;
#[cfg(all(test, not(target_family = "wasm")))]
mod mod_test;
#[cfg(all(test, not(target_family = "wasm")))]
mod user_state_test;
#[cfg(all(test, not(target_family = "wasm")))]
mod websocket_test;

#[cfg(target_family = "wasm")]
mod wasm;
#[cfg(all(test, target_family = "wasm"))]
mod wasm_test;

#[cfg(target_family = "wasm")]
pub use wasm::{
    ConnectionStateInfo, GroupDisplayCode, GroupKeyInfo, GroupKeyUpdateReasonInfo,
    JoinRequestChangeInfo, JoinTypeInfo, MeetingInfo, MeetingInfoWithPassword, MlsSyncStateInfo,
    ParticipantTrackSettingsInfo, RejoinReasonInfo, SubmitJoinRequestResponseInfo,
    UserSettingsInfo,
};

#[cfg(all(target_family = "wasm", test))]
pub use wasm::disconnection_handler;

#[derive(Clone)]
#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct TestFunctions {}

#[cfg(target_family = "wasm")]
#[wasm_bindgen]
impl TestFunctions {
    #[wasm_bindgen(constructor)]
    pub async fn new_test() -> Result<Self, JsValue> {
        Ok(Self {})
    }

    #[wasm_bindgen(js_name = testWasmNewFn)]
    pub async fn test_wasm(&self) -> crate::errors::core::Result<()> {
        Err(crate::errors::core::MeetCoreError::InvalidUrl {
            url: "test".to_string(),
        })
    }
}

#[derive(Clone, Debug)]
#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct DecryptedMessageInfo {
    pub message: String,
    pub sender_participant_id: String,
}

#[derive(Clone)]
#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct App {
    state: Arc<RwLock<AppState>>,
    ws_client: ArcWebSocketClient,
    http_api: Arc<dyn HttpClient>,
    mls_api: Arc<dyn MlsApi>,
    proton_http: Option<Arc<ProtonHttpClient>>,
    unleash_api: Arc<dyn UnleashApi>,
    meeting_api: Arc<dyn MeetingApi>,
    event_api: Arc<dyn EventApi>,
    user_key_provider: Arc<dyn UserKeyProvider>,

    /// services
    pub(crate) user_service: Arc<RwLock<Service>>,
    pub(crate) room_service: Arc<RoomService>,
    pub(crate) waiting_room_service: Arc<WaitingRoomService>,
}

impl App {
    #[cfg(not(target_family = "wasm"))]
    #[allow(clippy::too_many_arguments)]
    pub async fn new(
        env: String,
        app_version: String,
        user_agent: String,
        db_path: String,
        auth_store: AuthStore,
        http_host: String,
        ws_host: String,
        user_state: Option<UserState>,
        user_key_provider: Arc<dyn UserKeyProvider>,
    ) -> Result<Self, MeetCoreError> {
        let app_version_clone = app_version.clone();
        let user_agent_clone = user_agent.clone();
        let is_prod_env = is_prod_environment(&env);
        let config = ApiConfig {
            spec: (app_version, user_agent),
            auth: None,
            url_prefix: None,
            env: Some(env),
            proxy: None,
        };
        let http_client = Arc::new(ProtonHttpClient::new(config, auth_store, http_host).await?);
        Self::from_http_client(
            http_client,
            db_path,
            ws_host,
            is_prod_env,
            user_state,
            user_key_provider,
            app_version_clone,
            user_agent_clone,
        )
        .await
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn http_client(&self) -> ProtonHttpClient {
        self.proton_http
            .as_ref()
            .expect("proton HTTP client is only available on production App instances")
            .as_ref()
            .clone()
    }

    /// Rebuild the muon client so its in-memory auth matches `auth_store`.
    #[cfg(not(target_family = "wasm"))]
    pub async fn sync_auth_store(&self, auth_store: AuthStore) -> Result<(), MeetCoreError> {
        self.http_client()
            .sync_auth_store(auth_store)
            .await
            .map_err(MeetCoreError::from)
    }

    #[cfg(target_family = "wasm")]
    pub async fn from_config(
        config: ApiConfig,
        db_path: String,
        http_host: String,
        ws_host: String,
        user_key_provider: Arc<dyn UserKeyProvider>,
    ) -> Result<Self, MeetCoreError> {
        Self::init_logging();

        let env: String = config.env.clone().unwrap_or("atlas".to_string());
        let is_prod_env = is_prod_environment(&env);
        let app_version = config.spec.0.clone();
        let user_agent = config.spec.1.clone();

        let http_client = Arc::new(ProtonHttpClient::new(config, http_host).await?);

        Self::from_http_client(
            http_client,
            db_path,
            ws_host,
            is_prod_env,
            None,
            user_key_provider,
            app_version,
            user_agent,
        )
        .await
    }

    #[allow(clippy::too_many_arguments)]
    async fn from_http_client(
        http_client: Arc<ProtonHttpClient>,
        db_path: String,
        ws_host: String,
        is_prod_env: bool,
        user_state: Option<UserState>,
        user_key_provider: Arc<dyn UserKeyProvider>,
        app_version: String,
        user_agent: String,
    ) -> Result<Self, MeetCoreError> {
        let persister = Persister::new(db_path).await?;

        let ws_client = Arc::new(WsClient::new_with_prod_tls_pinning(ws_host, is_prod_env));
        let mls_store = Arc::new(RwLock::new(MlsStore {
            clients: HashMap::new(),
            group_map: HashMap::new(),
            config: MlsClientConfig::default(),
        }));
        let crypto_client = Arc::new(MeetCryptoClient::new()) as Arc<dyn CryptoClient>;
        let mls_service: Arc<dyn KeyPackagePort> = Arc::new(MlsService::new(
            mls_store.clone(),
            http_client.server_time_tracker(),
        ));

        let user_service = Arc::new(RwLock::new(Service::new(
            http_client.clone(),
            http_client.clone(),
            http_client.clone(),
            http_client.clone(),
            Arc::new(persister),
            ws_client.clone(),
            mls_store.clone(),
            http_client.server_time_tracker(),
        )));

        let room_service = Arc::new(RoomService::new(
            http_client.clone(),
            http_client.clone(),
            crypto_client.clone(),
        ));
        let waiting_room_service = Arc::new(WaitingRoomService::new(crypto_client, mls_service));

        let user_service_clone = user_service.clone();
        ws_client
            .set_message_handler(Arc::new(move |message| {
                let user_service = user_service_clone.clone();
                Box::pin(async move {
                    match user_service
                        .read()
                        .await
                        .handle_websocket_message(message)
                        .await
                    {
                        Ok(_) => (),
                        Err(e) => {
                            error!("Error handling message: {:?}", e);
                        }
                    }
                })
            }))
            .await;

        Ok(Self {
            user_service,
            room_service,
            waiting_room_service,

            state: Arc::new(RwLock::new(AppState {
                active_user: user_state,
                mls_store,
                active_livekit_access_token: None,
                active_livekit_websocket_url: None,
                meeting_display_name_session_key: None,
                active_user_info: None,
                join_start_time: None,
                join_mls_time: None,
                total_join_start_time: None,
                join_type: None,
                prejoin_srp_auth: None,
                pending_waiting_room_join_request_id: None,
                used_waiting_room_for_join: None,
                app_version: Some(app_version),
                user_agent: Some(user_agent),
            })),
            ws_client,
            http_api: http_client.clone(),
            mls_api: http_client.clone(),
            proton_http: Some(http_client.clone()),
            unleash_api: http_client.clone(),
            meeting_api: http_client.clone(),
            event_api: http_client,
            user_key_provider,
        })
    }

    pub async fn fetch_toggles(&self) -> Result<UnleashResponse, MeetCoreError> {
        let response = self
            .unleash_api
            .fetch_toggles()
            .await
            .map_err(MeetCoreError::from)?;
        Ok(response)
    }

    /// Ping the server and return RTT in milliseconds
    pub async fn ping(&self) -> Result<u64, MeetCoreError> {
        self.http_api.ping().await.map_err(MeetCoreError::from)
    }

    pub async fn set_livekit_active_uuids(
        &self,
        livekit_active_uuid_list: Vec<String>,
    ) -> Result<(), MeetCoreError> {
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);

        let meeting_id = self
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;
        self.user_service
            .read()
            .await
            .set_livekit_active_uuids(&meeting_id, livekit_active_uuid_list)
            .await?;

        Ok(())
    }

    pub async fn is_mls_up_to_date(&self) -> Result<bool, MeetCoreError> {
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        let meeting_id = self
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;
        // first check
        let is_up_to_date = self
            .user_service
            .read()
            .await
            .is_mls_up_to_date(&user_id, meeting_id.as_str(), false)
            .await?;
        // trigger websocket reconnection if not up to date,
        if !is_up_to_date {
            self.trigger_websocket_reconnect().await?;
        } else {
            // already up to date, return true earlier
            return Ok(true);
        }
        // recheck
        let is_up_to_date = self
            .user_service
            .read()
            .await
            .is_mls_up_to_date(&user_id, meeting_id.as_str(), true)
            .await?;
        Ok(is_up_to_date)
    }

    pub async fn update_participant_track_settings(
        &self,
        participant_uuid: String,
        audio: Option<u8>,
        video: Option<u8>,
    ) -> Result<ParticipantTrackSettings, MeetCoreError> {
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        let livekit_access_token = app_state
            .active_livekit_access_token
            .as_ref()
            .ok_or(MeetCoreError::LivekitAccessTokenNotFound)?;
        let meeting_id = self
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;
        let participant_track_settings = self
            .room_service
            .update_participant_track_settings(
                meeting_id.as_str(),
                livekit_access_token,
                &participant_uuid,
                audio,
                video,
            )
            .await?;
        Ok(participant_track_settings)
    }

    pub async fn get_user_settings(&self) -> Result<UserSettings, MeetCoreError> {
        let user_settings = self.user_service.read().await.get_user_settings().await?;
        Ok(user_settings)
    }

    pub async fn update_user_settings_waiting_room(
        &self,
        enable: bool,
    ) -> Result<UserSettings, MeetCoreError> {
        let user_settings = self
            .user_service
            .read()
            .await
            .update_user_settings_waiting_room(enable)
            .await?;
        Ok(user_settings)
    }

    pub async fn remove_participant(
        &self,
        participant_uuid_to_remove: String,
    ) -> Result<(), MeetCoreError> {
        let app_state = self.state.read().await;
        let livekit_access_token = app_state
            .active_livekit_access_token
            .as_ref()
            .ok_or(MeetCoreError::LivekitAccessTokenNotFound)?;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        let meeting_id = self
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;
        self.room_service
            .remove_participant(
                meeting_id.as_str(),
                livekit_access_token,
                &participant_uuid_to_remove,
            )
            .await?;
        self.kick_participant(participant_uuid_to_remove).await?;
        Ok(())
    }

    pub async fn get_group_key(&self) -> Result<(String, u64), MeetCoreError> {
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        let meeting_id = self
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;

        self.user_service
            .read()
            .await
            .get_group_key(meeting_id.as_str())
            .await
            .map_err(MeetCoreError::from)
    }

    pub async fn get_group_len(&self) -> Result<u32, MeetCoreError> {
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        let meeting_id = self
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;

        self.user_service
            .read()
            .await
            .get_group_len(meeting_id.as_str())
            .await
            .map_err(MeetCoreError::from)
    }

    pub async fn get_group_display_code(&self) -> Result<String, MeetCoreError> {
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        let meeting_id = self
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;

        let group_display_code = self
            .user_service
            .read()
            .await
            .get_group_display_code(meeting_id.as_str())
            .await?;
        Ok(group_display_code)
    }

    pub async fn encrypt_message(&self, message: &str) -> Result<Vec<u8>, MeetCoreError> {
        crate::chat::legacy::encrypt_legacy(self, message).await
    }

    pub async fn decrypt_message(
        &self,
        data: Vec<u8>,
    ) -> Result<DecryptedMessageInfo, MeetCoreError> {
        crate::chat::legacy::decrypt_legacy(self, data).await
    }

    pub async fn set_mls_group_update_handler<F, Fut>(&self, callback: F)
    where
        F: Fn(String, crate::service::service::GroupKeyUpdateReason) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        self.user_service
            .write()
            .await
            .set_mls_group_update_handler(callback);
    }

    pub async fn set_mls_sync_state_update_handler<F, Fut>(&self, callback: F)
    where
        F: Fn(
                crate::service::service_state::MlsSyncState,
                Option<crate::infra::dto::realtime::RejoinReason>,
            ) -> Fut
            + Send
            + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        self.user_service
            .write()
            .await
            .set_mls_sync_state_update_handler(callback);
    }

    pub async fn set_livekit_admin_change_handler<F, Fut>(&self, callback: F)
    where
        F: Fn(String, String, u32) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        self.user_service
            .write()
            .await
            .set_livekit_admin_change_handler(callback);
    }

    pub async fn set_agent_pending_handler<F, Fut>(&self, callback: F)
    where
        F: Fn(String) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        self.user_service
            .write()
            .await
            .set_agent_pending_handler(callback);
    }

    pub async fn set_agent_left_handler<F, Fut>(&self, callback: F)
    where
        F: Fn(String) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        self.user_service
            .write()
            .await
            .set_agent_left_handler(callback);
    }
}

#[cfg(all(test, not(target_family = "wasm")))]
impl App {
    pub(crate) fn from_test_parts(
        state: Arc<RwLock<AppState>>,
        ws_client: ArcWebSocketClient,
        http_client: Arc<dyn HttpClient>,
        mls_api: Arc<dyn MlsApi>,
        unleash_api: Arc<dyn UnleashApi>,
        meeting_api: Arc<dyn MeetingApi>,
        event_api: Arc<dyn EventApi>,
        user_key_provider: Arc<dyn UserKeyProvider>,
        user_service: Arc<RwLock<Service>>,
        room_service: Arc<RoomService>,
        waiting_room_service: Arc<WaitingRoomService>,
    ) -> Self {
        Self {
            state,
            ws_client,
            http_api: http_client,
            mls_api,
            proton_http: None,
            unleash_api,
            meeting_api,
            event_api,
            user_key_provider,
            user_service,
            room_service,
            waiting_room_service,
        }
    }
}
