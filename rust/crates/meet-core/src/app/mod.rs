use crate::app_state::{AppState, UserState};
use crate::domain::room::RoomService;
use crate::domain::user::models::{
    participant_track_settings::ParticipantTrackSettings, user_settings::UserSettings,
    UnleashResponse,
};
use crate::domain::user::ports::meeting_api::MeetingApi;
use crate::domain::user::ports::{
    ArcWebSocketClient, EventApi, HttpClient, UnleashApi, UserService, WebSocketClient,
};
use crate::errors::core::MeetCoreError;
use crate::infra::{
    auth_store::{AuthStore, MUON_DEFAULT_SESSION_KEY},
    crypto_client::MeetCryptoClient,
    http_client::{ApiConfig, ProtonHttpClient},
    ports::user_key_provider::UserKeyProvider,
    storage::persister::Persister,
    ws_client::WsClient,
};
use crate::service::service::Service;
use mls_trait::MlsClientConfig;
use muon::{client::Auth, env::EnvId, store::Store};
use proton_meet_mls::MlsStore;
use std::{collections::HashMap, future::Future, sync::Arc};
use tokio::sync::RwLock;
use tracing::error;

#[cfg(target_family = "wasm")]
use {wasm_bindgen::prelude::wasm_bindgen, wasm_bindgen::JsValue};

mod auth;
mod chat;
mod event;
mod join;
mod meetings;
mod metrics;
mod user_state;
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
    ConnectionStateInfo, GroupDisplayCode, GroupKeyInfo, GroupKeyUpdateReasonInfo, JoinTypeInfo,
    MeetingInfo, MeetingInfoWithPassword, MlsSyncStateInfo, ParticipantTrackSettingsInfo,
    RejoinReasonInfo, UserSettingsInfo,
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
    proton_http: Option<Arc<ProtonHttpClient>>,
    unleash_api: Arc<dyn UnleashApi>,
    meeting_api: Arc<dyn MeetingApi>,
    event_api: Arc<dyn EventApi>,
    user_key_provider: Arc<dyn UserKeyProvider>,

    /// services
    pub(crate) user_service: Arc<RwLock<Service>>,
    pub(crate) room_service: Arc<RoomService>,
}

impl App {
    #[allow(clippy::too_many_arguments)]
    pub async fn new(
        env: String,
        app_version: String,
        user_agent: String,
        db_path: String,
        auth_store: Box<dyn Store<()>>,
        http_host: String,
        ws_host: String,
        user_state: Option<UserState>,
        user_key_provider: Arc<dyn UserKeyProvider>,
    ) -> Result<Self, MeetCoreError> {
        #[cfg(target_family = "wasm")]
        Self::init_logging();

        let app_version_clone = app_version.clone();
        let user_agent_clone = user_agent.clone();
        let is_prod_env = matches!(env.parse::<EnvId>(), Ok(EnvId::Prod));
        let config = ApiConfig {
            spec: (app_version, user_agent),
            auth: None,
            url_prefix: None,
            env: Some(env),
            store: None,
            // proxy: Some(ProxyConfig {
            //     host: "192.168.1.140".into(),
            //     port: 9090,
            // }),
            proxy: None,
        };
        let http_client = Arc::new(ProtonHttpClient::new(config, auth_store, http_host).await?);
        let persister = Persister::new(db_path).await?;
        let ws_client = Arc::new(WsClient::new_with_prod_tls_pinning(ws_host, is_prod_env));
        let mls_store = Arc::new(RwLock::new(MlsStore {
            clients: HashMap::new(),
            group_map: HashMap::new(),
            config: MlsClientConfig::default(),
        }));
        let crypto_client = MeetCryptoClient::new();

        let user_service = Arc::new(RwLock::new(Service::new(
            http_client.clone(),
            http_client.clone(),
            Arc::new(persister),
            ws_client.clone(),
            mls_store.clone(),
        )));

        let room_service = Arc::new(RoomService::new(
            http_client.clone(),
            http_client.clone(),
            Arc::new(crypto_client),
        ));

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
                app_version: Some(app_version_clone),
                user_agent: Some(user_agent_clone),
            })),
            ws_client,
            http_api: http_client.clone(),
            proton_http: Some(http_client.clone()),
            unleash_api: http_client.clone(),
            meeting_api: http_client.clone(),
            event_api: http_client,
            user_key_provider,

            room_service,
            user_service,
        })
    }

    pub fn http_client(&self) -> ProtonHttpClient {
        self.proton_http
            .as_ref()
            .expect("proton HTTP client is only available on production App instances")
            .as_ref()
            .clone()
    }

    pub async fn from_config(
        config: ApiConfig,
        db_path: String,
        http_host: String,
        ws_host: String,
        user_key_provider: Arc<dyn UserKeyProvider>,
    ) -> Result<Self, MeetCoreError> {
        #[cfg(target_family = "wasm")]
        Self::init_logging();

        let env: String = config.env.clone().unwrap_or("atlas".to_string());
        let is_prod_env = matches!(env.parse::<EnvId>(), Ok(EnvId::Prod));
        let app_version = config.spec.0.clone();
        let user_agent = config.spec.1.clone();
        let auth = config.auth.clone().unwrap_or(Auth::None);
        let original_auth = auth.clone();
        let mut auth_store = if config.proxy.is_none() {
            Box::new(AuthStore::from_env_str(
                env.clone(),
                Arc::new(tokio::sync::Mutex::new(auth)),
            ))
        } else {
            Box::new(AuthStore::from_custom_env_str(
                env.clone(),
                Arc::new(tokio::sync::Mutex::new(auth)),
            ))
        };

        let _initialized_auth = auth_store
            .get_auth(&MUON_DEFAULT_SESSION_KEY)
            .await
            .map_err(|e| MeetCoreError::AuthStoreError {
                message: e.to_string(),
            })?;
        // Auth session details must not be logged (contains tokens).
        // need to set the auth again or the auth_store will be empty
        // todo: check and report to muon team if this is a bug
        if matches!(original_auth, Auth::None) {
            auth_store
                .remove_auth(&MUON_DEFAULT_SESSION_KEY)
                .await
                .map_err(|e| MeetCoreError::AuthStoreError {
                    message: e.to_string(),
                })?;
        } else {
            auth_store
                .set_auth(&MUON_DEFAULT_SESSION_KEY, original_auth)
                .await
                .map_err(|e| MeetCoreError::AuthStoreError {
                    message: e.to_string(),
                })?;
        }

        let http_client = Arc::new(ProtonHttpClient::new(config, auth_store, http_host).await?);
        let persister = Persister::new(db_path).await?;

        let ws_client = Arc::new(WsClient::new_with_prod_tls_pinning(ws_host, is_prod_env));
        let mls_store = Arc::new(RwLock::new(MlsStore {
            clients: HashMap::new(),
            group_map: HashMap::new(),
            config: MlsClientConfig::default(),
        }));
        let crypto_client = MeetCryptoClient::new();

        let user_service = Arc::new(RwLock::new(Service::new(
            http_client.clone(),
            http_client.clone(),
            Arc::new(persister),
            ws_client.clone(),
            mls_store.clone(),
        )));

        let room_service = Arc::new(RoomService::new(
            http_client.clone(),
            http_client.clone(),
            Arc::new(crypto_client),
        ));

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

            state: Arc::new(RwLock::new(AppState {
                active_user: None,
                mls_store,
                active_livekit_access_token: None,
                active_livekit_websocket_url: None,
                meeting_display_name_session_key: None,
                active_user_info: None,
                join_start_time: None,
                join_mls_time: None,
                total_join_start_time: None,
                join_type: None,
                app_version: Some(app_version),
                user_agent: Some(user_agent),
            })),
            ws_client,
            http_api: http_client.clone(),
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
}

// #[cfg(all(test, not(target_family = "wasm")))]
impl App {
    pub(crate) fn from_test_parts(
        state: Arc<RwLock<AppState>>,
        ws_client: ArcWebSocketClient,
        http_client: Arc<dyn HttpClient>,
        unleash_api: Arc<dyn UnleashApi>,
        meeting_api: Arc<dyn MeetingApi>,
        event_api: Arc<dyn EventApi>,
        user_key_provider: Arc<dyn UserKeyProvider>,
        user_service: Arc<RwLock<Service>>,
        room_service: Arc<RoomService>,
    ) -> Self {
        Self {
            state,
            ws_client,
            http_api: http_client,
            proton_http: None,
            unleash_api,
            meeting_api,
            event_api,
            user_key_provider,
            user_service,
            room_service,
        }
    }
}
