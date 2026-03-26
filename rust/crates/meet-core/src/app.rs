use crate::app_state::{AppState, UserState, UserStateInfo};
use crate::domain::room::RoomService;
use crate::domain::user::models::meet_link_info::{MeetInfo, MeetParticipant};
use crate::domain::user::models::meeting::{
    Meeting, MeetingType, UpcomingMeeting, UpdateMeetingScheduleParams,
};
use crate::domain::user::models::participant_track_settings::ParticipantTrackSettings;
use crate::domain::user::models::user_settings::UserSettings;
use crate::domain::user::models::UnleashResponse;
use crate::domain::user::models::UserId;
use crate::domain::user::ports::meeting_api::MeetingApi;
use crate::domain::user::ports::{
    ArcWebSocketClient, ConnectionState, HttpClient, UnleashApi, UserService, WebSocketClient,
};
use crate::errors::core::MeetCoreError;
use crate::infra::auth_store::AuthStore;
use crate::infra::crypto_client::MeetCryptoClient;
use crate::infra::dto::proton_user::UserData;
use crate::infra::dto::realtime::{
    ConnectionLostMetric, DesignatedCommitterMetric, ErrorCodeMetric, JoinType, RejoinReason,
    ServiceMetricsRequest, UserEpochHealthMetric, UserJoinTimeMetric, UserRejoinMetric,
    UserRetryCountMetric,
};
use crate::infra::http_client::{ApiConfig, ProtonHttpClient};
use crate::infra::ports::user_key_provider::UserKeyProvider;
use crate::infra::storage::persister::Persister;
use crate::infra::ws_client::WsClient;
use crate::service::service::Service;
use crate::utils::{instant, try_join};
use chrono::{DateTime, Utc};
use mls_rs_codec::MlsEncode;
use mls_trait::MlsClientConfig;
use mls_types::MlsMessage;
use muon::client::Auth;
use muon::env::EnvId;
use muon::store::Store;
use proton_meet_common::models::ProtonUser;
use proton_meet_common::models::ProtonUserKey;
use proton_meet_mls::MlsStore;
use std::collections::HashMap;
use std::future::Future;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::RwLock;
#[cfg(not(target_family = "wasm"))]
use tokio::time::sleep;
use tracing::{debug, error, info, warn};
#[cfg(target_family = "wasm")]
use wasmtimer::tokio::sleep;

#[cfg(target_family = "wasm")]
use {wasm_bindgen::prelude::wasm_bindgen, wasm_bindgen::JsValue};

// Threshold for switching from ExternalCommit to ExternalProposal join type in the app, based on the room participants count
const JOIN_TYPE_SWITCH_THRESHOLD: u32 = 20;

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

#[derive(Clone)]
#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct App {
    state: Arc<RwLock<AppState>>,
    ws_client: ArcWebSocketClient,
    http_client: ProtonHttpClient,
    user_key_provider: Arc<dyn UserKeyProvider>,

    /// services
    pub(crate) user_service: Arc<RwLock<Service>>,
    pub(crate) room_service: Arc<RoomService>,
}

impl App {
    /// Extracts user authentication information from the active user state.
    /// This includes the active user key, user ID, mailbox password, and primary address.
    ///
    /// # Returns
    /// * `Ok(UserAuthInfo)` - User authentication information
    /// * `Err(MeetCoreError)` - Error if no active user, no user keys, or no primary address
    async fn get_user_state_info(&self) -> Result<UserStateInfo, MeetCoreError> {
        let app_state = self.state.read().await;
        let user_state = app_state
            .active_user
            .as_ref()
            .ok_or(MeetCoreError::NoActiveUser)?;
        let active_user_key = user_state
            .user_keys
            .first()
            .ok_or(MeetCoreError::NoUserKeys)?
            .clone();
        let user_id = user_state.user_data.id.clone();
        let primary_address = user_state
            .user_addresses
            .first()
            .ok_or(MeetCoreError::NoPrimaryAddress)?
            .clone();

        Ok(UserStateInfo {
            active_user_key,
            user_id,
            primary_address,
        })
    }
}

impl App {
    #[allow(clippy::too_many_arguments)]
    pub async fn new(
        env: String,
        app_version: String,
        user_agent: String,
        db_path: String,
        auth_store: Box<dyn Store>,
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
        let http_client = ProtonHttpClient::new(config, auth_store, http_host)?;
        let persister = Persister::new(db_path).await?;
        let ws_client = Arc::new(WsClient::new_with_prod_tls_pinning(ws_host, is_prod_env));
        let mls_store = Arc::new(RwLock::new(MlsStore {
            clients: HashMap::new(),
            group_map: HashMap::new(),
            config: MlsClientConfig::default(),
        }));
        let crypto_client = MeetCryptoClient::new();

        let user_service = Arc::new(RwLock::new(Service::new(
            Arc::new(http_client.clone()),
            Arc::new(http_client.clone()),
            Arc::new(persister),
            ws_client.clone(),
            mls_store.clone(),
        )));

        let room_service = Arc::new(RoomService::new(
            Arc::new(http_client.clone()),
            Arc::new(http_client.clone()),
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
                join_type: None,
                app_version: Some(app_version_clone),
                user_agent: Some(user_agent_clone),
                use_psk: true,
            })),
            ws_client,
            http_client,
            user_key_provider,

            room_service,
            user_service,
        })
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
                env,
                Arc::new(tokio::sync::Mutex::new(auth)),
            ))
        } else {
            Box::new(AuthStore::from_custom_env_str(
                env,
                Arc::new(tokio::sync::Mutex::new(auth)),
            ))
        };

        let initialized_auth = auth_store.get_auth().await;
        #[cfg(debug_assertions)]
        debug!("initialized_auth: {:?}", initialized_auth);
        // need to set the auth again or the auth_store will be empty
        // todo: check and report to muon team if this is a bug
        let fixed_auth = auth_store.set_auth(original_auth).await.map_err(|e| {
            MeetCoreError::AuthStoreError {
                message: e.to_string(),
            }
        })?;
        #[cfg(debug_assertions)]
        debug!("fixed_auth: {:?}", fixed_auth);

        let http_client = ProtonHttpClient::new(config, auth_store, http_host)?;
        let persister = Persister::new(db_path).await?;

        let ws_client = Arc::new(WsClient::new_with_prod_tls_pinning(ws_host, is_prod_env));
        let mls_store = Arc::new(RwLock::new(MlsStore {
            clients: HashMap::new(),
            group_map: HashMap::new(),
            config: MlsClientConfig::default(),
        }));
        let crypto_client = MeetCryptoClient::new();

        let user_service = Arc::new(RwLock::new(Service::new(
            Arc::new(http_client.clone()),
            Arc::new(http_client.clone()),
            Arc::new(persister),
            ws_client.clone(),
            mls_store.clone(),
        )));

        let room_service = Arc::new(RoomService::new(
            Arc::new(http_client.clone()),
            Arc::new(http_client.clone()),
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
                join_type: None,
                app_version: Some(app_version),
                user_agent: Some(user_agent),
                use_psk: true,
            })),
            ws_client,
            http_client,
            user_key_provider,
        })
    }

    pub async fn fetch_toggles(&self) -> Result<UnleashResponse, MeetCoreError> {
        let unleash_api = self.http_client.clone();
        let response = unleash_api
            .fetch_toggles()
            .await
            .map_err(MeetCoreError::from)?;
        Ok(response)
    }

    /// Get the latest event ID from the server
    pub async fn get_latest_event_id(&self) -> Result<String, MeetCoreError> {
        use crate::domain::user::ports::event_api::EventApi;
        let event_id = self.http_client.get_latest_event_id().await.map_err(|e| {
            MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            }
        })?;
        Ok(event_id)
    }

    /// Get events starting from a given event ID
    /// Returns GetEventsResponse containing meeting event items, flags, and new event ID
    pub async fn get_events(
        &self,
        event_id: String,
    ) -> Result<crate::infra::dto::event::GetEventsResponse, MeetCoreError> {
        use crate::domain::user::ports::event_api::EventApi;
        let response = self
            .http_client
            .get_events(&event_id)
            .await
            .map_err(MeetCoreError::from)?;

        Ok(response)
    }

    /// Ping the server and return RTT in milliseconds
    pub async fn ping(&self) -> Result<u64, MeetCoreError> {
        self.http_client.ping().await.map_err(MeetCoreError::from)
    }

    /// Fork selector for creating child sessions (e.g., for account deletion)
    /// Returns a selector string that can be used to create a fork session
    /// Client must be authenticated first
    pub async fn fork_selector(&self, client_child: &str) -> Result<String, MeetCoreError> {
        let session = self.http_client.get_session();
        match session
            .fork(client_child)
            .payload(b"proton meet fork")
            .send()
            .await
        {
            muon::client::flow::ForkFlowResult::Success(_client, selector) => Ok(selector),
            other => {
                error!("Fork session failed: {:?}", other);
                Err(MeetCoreError::HttpClientError {
                    status: 0,
                    message: format!("Fork session failed: {other:?}"),
                    details: Some(format!("{other:?}")),
                })
            }
        }
    }

    pub async fn fetch_user_state(&self, user_id: String) -> Result<UserState, MeetCoreError> {
        let user = self
            .user_service
            .read()
            .await
            .get_user(&UserId::new(user_id.clone()))
            .await?;

        let user_keys = self
            .user_service
            .read()
            .await
            .get_user_keys(&UserId::new(user_id.clone()))
            .await?;

        let user_addresses = self.user_service.read().await.get_user_addresses().await?;

        let user_state = UserState {
            user_data: user.clone(),
            user_keys,
            user_addresses,
        };

        self.state.write().await.active_user = Some(user_state.clone());
        Ok(user_state)
    }

    pub async fn login(
        &self,
        username: String,
        password: String,
    ) -> Result<UserData, MeetCoreError> {
        use zeroize::Zeroizing;
        let password = Zeroizing::new(password);
        let (login_response, user, user_keys, user_addresses) = self
            .user_service
            .read()
            .await
            .login(&username, password.as_str())
            .await?;
        self.state.write().await.active_user = Some(UserState {
            user_data: user.clone(),
            user_keys,
            user_addresses,
        });
        Ok(login_response)
    }

    pub async fn get_ws_state(&self) -> Result<ConnectionState, MeetCoreError> {
        let ws_state = self.ws_client.get_connection_state().await;
        Ok(ws_state)
    }

    /// Set WebSocket ping interval in seconds (None to use default)
    pub async fn set_websocket_ping_interval(
        &self,
        seconds: Option<u64>,
    ) -> Result<(), MeetCoreError> {
        self.ws_client.set_ping_interval_seconds(seconds).await;
        Ok(())
    }

    /// Set WebSocket max ping failures (None to use default)
    pub async fn set_websocket_max_ping_failures(
        &self,
        failures: Option<u32>,
    ) -> Result<(), MeetCoreError> {
        self.ws_client.set_max_ping_failures(failures).await;
        Ok(())
    }

    /// Set WebSocket pong timeout in seconds (None to use default)
    pub async fn set_websocket_pong_timeout(
        &self,
        seconds: Option<u64>,
    ) -> Result<(), MeetCoreError> {
        self.ws_client.set_pong_timeout_seconds(seconds).await;
        Ok(())
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
            .write()
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

    pub async fn is_websocket_has_reconnected(&self) -> Result<bool, MeetCoreError> {
        let has_reconnected = self
            .user_service
            .read()
            .await
            .is_websocket_has_reconnected()
            .await;
        Ok(has_reconnected)
    }

    pub async fn get_user_state(&self) -> Result<UserState, MeetCoreError> {
        let app_state = self.state.read().await;
        let user_state = app_state
            .active_user
            .as_ref()
            .ok_or(MeetCoreError::NoActiveUser)?;
        Ok(user_state.clone())
    }

    pub async fn logout(&self, user_id: String) -> Result<(), MeetCoreError> {
        self.user_service
            .write()
            .await
            .logout(&UserId::new(user_id))
            .await?;
        let mut state = self.state.write().await;
        state.active_user = None;
        state.meeting_display_name_session_key = None;
        Ok(())
    }

    pub async fn leave_meeting(&self) -> Result<(), MeetCoreError> {
        // Step 1: clone necessary data first
        let (participant_id, meeting_id) = {
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
            (user_id, meeting_id)
        };
        // Step 2: Leave room
        self.user_service
            .read()
            .await
            .leave_room(&participant_id, &meeting_id)
            .await?;
        // Step 3: Disconnect from WebSocket
        self.disconnect_from_ws().await?;

        // Step 4: Modify state (no overlapping locks)
        {
            let mut state = self.state.write().await;
            state.meeting_display_name_session_key = None;
            let mut store = state.mls_store.write().await;
            store.clients.remove(&participant_id.to_string());
        }

        Ok(())
    }

    pub async fn end_meeting(&self) -> Result<(), MeetCoreError> {
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
        let livekit_access_token = app_state
            .active_livekit_access_token
            .as_ref()
            .ok_or(MeetCoreError::LivekitAccessTokenNotFound)?;
        self.room_service
            .end_meeting(&meeting_id, livekit_access_token)
            .await?;

        self.disconnect_from_ws().await?;

        Ok(())
    }

    pub async fn delete_meeting(&self, meeting_name: String) -> Result<(), MeetCoreError> {
        self.http_client.delete_meeting(&meeting_name).await?;
        Ok(())
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

    pub async fn get_active_meetings(&self) -> Result<Vec<Meeting>, MeetCoreError> {
        let active_meetings = self.room_service.get_active_meetings().await?;
        Ok(active_meetings)
    }

    pub async fn get_meeting_info(
        &self,
        meeting_link_name: &str,
    ) -> Result<crate::domain::user::models::MeetingInfo, MeetCoreError> {
        let meeting_info = self
            .room_service
            .get_meeting_info(meeting_link_name)
            .await?;
        Ok(meeting_info)
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
        let encrypted_message = self
            .user_service
            .read()
            .await
            .encrypt_application_message(meeting_id.as_str(), message)
            .await?;
        Ok(encrypted_message.mls_encode_to_vec()?)
    }

    pub async fn decrypt_message(
        &self,
        data: Vec<u8>,
    ) -> Result<DecryptedMessageInfo, MeetCoreError> {
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
        let mls_message = MlsMessage::from_bytes(&data)?;
        let (decrypted_message, sender_id) = self
            .user_service
            .read()
            .await
            .decrypt_application_message(meeting_id.as_str(), mls_message)
            .await?;
        Ok(DecryptedMessageInfo {
            message: decrypted_message,
            sender_participant_id: sender_id.to_string(),
        })
    }

    pub async fn set_mls_group_update_handler<F, Fut>(&self, callback: F)
    where
        F: Fn(String) -> Fut + Send + 'static,
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

    #[tracing::instrument(err, skip_all)]
    pub async fn login_with_two_factor(
        &self,
        two_factor_code: String,
    ) -> Result<UserData, MeetCoreError> {
        let user_data = self
            .user_service
            .read()
            .await
            .login_with_two_factor(&two_factor_code)
            .await?;
        Ok(user_data)
    }

    #[tracing::instrument(err, skip_all)]
    pub async fn get_user(&self, user_id: String) -> Result<ProtonUser, anyhow::Error> {
        let user_data = self
            .user_service
            .read()
            .await
            .get_user(&UserId::new(user_id))
            .await?;
        Ok(user_data)
    }

    pub async fn join_meeting_with_access_token(
        &self,
        access_token: String,
        meet_link_name: String,
        meeting_password: String,
        use_psk: bool,
        session_id: Option<String>,
    ) -> Result<(), MeetCoreError> {
        // Record join start time
        {
            let mut state = self.state.write().await;
            state.join_start_time = Some(crate::utils::instant::now());
            state.join_mls_time = None;
            state.use_psk = use_psk;
        }

        let mls_start = instant::now();
        let user_info = self
            .user_service
            .read()
            .await
            .create_mls_client(
                &access_token,
                &meet_link_name,
                &meeting_password,
                use_psk,
                session_id.as_deref(),
            )
            .await?;
        debug!(
            "join_meeting_with_access_token step=create_mls_client ms={} user={:?} device_id={}",
            mls_start.elapsed().as_millis(),
            &user_info.user_identifier,
            &user_info.device_id,
        );
        debug!(
            "MLS client created for user: {:?}, device_id: {}",
            &user_info.user_identifier, &user_info.device_id,
        );

        let state_start = instant::now();
        {
            let mut state = self.state.write().await;
            state.active_user_info = Some(user_info.clone());
            state.active_livekit_access_token = Some(access_token.clone());
            debug!("Active user info: {:?}", state.active_user_info);
        }
        debug!(
            "join_meeting_with_access_token step=store_state ms={}",
            state_start.elapsed().as_millis()
        );

        let join_and_connect_start = instant::now();

        let connect_ws_fut = self.connect_to_ws();
        let join_room_fut = self.join_room();

        let result = try_join(connect_ws_fut, join_room_fut).await;

        if let Err(e) = result {
            error!(
                "Error connecting to WebSocket or joining room: {:?}, ms={}",
                &e,
                join_and_connect_start.elapsed().as_millis()
            );

            self.user_service.read().await.reset_service_state().await;
            if let Err(disconnect_err) = self.disconnect_from_ws().await {
                warn!("Failed to disconnect from websocket: {:?}", disconnect_err);
            }
            return Err(e);
        }

        info!(
            "Connected to WebSocket and joined room ms={}",
            join_and_connect_start.elapsed().as_millis()
        );
        Ok(())
    }

    pub async fn join_meeting_with_access_token_with_proposal(
        &self,
        access_token: String,
        meet_link_name: String,
        meeting_password: String,
        use_psk: bool,
        session_id: Option<String>,
    ) -> Result<(), MeetCoreError> {
        // Record join start time
        {
            let mut state = self.state.write().await;
            state.join_start_time = Some(crate::utils::instant::now());
            state.join_mls_time = None;
            state.use_psk = use_psk;
        }

        let user_info = self
            .user_service
            .read()
            .await
            .create_mls_client(
                &access_token,
                &meet_link_name,
                &meeting_password,
                use_psk,
                session_id.as_deref(),
            )
            .await?;
        debug!(
            "MLS client created for user: {:?}, device_id: {}",
            &user_info.user_identifier, &user_info.device_id,
        );

        {
            let mut state = self.state.write().await;
            state.active_user_info = Some(user_info.clone());
            state.active_livekit_access_token = Some(access_token.clone());
            debug!("Active user info: {:?}", state.active_user_info);
        } // lock released here

        let join_and_connect_start = instant::now();
        let connect_ws_fut = self.connect_to_ws();
        let join_room_fut = self.join_room_with_proposal();
        let result = try_join(connect_ws_fut, join_room_fut).await;

        if let Err(e) = result {
            error!(
                "Error connecting to WebSocket or joining room with proposal: {:?}, ms={}",
                &e,
                join_and_connect_start.elapsed().as_millis()
            );
            self.user_service.read().await.reset_service_state().await;
            if let Err(disconnect_err) = self.disconnect_from_ws().await {
                warn!("Failed to disconnect from websocket: {:?}", disconnect_err);
            }
            return Err(e);
        }

        info!(
            "Joined room with proposal ms={}",
            join_and_connect_start.elapsed().as_millis()
        );

        // Check if user is host and update role if needed
        let user_id = user_info.user_id();
        if let Ok(meeting_id) = self
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await
        {
            if let Err(e) = self
                .user_service
                .read()
                .await
                .check_and_update_host_role(&meeting_id)
                .await
            {
                warn!(
                    "Failed to check and update host role after proposal join: {:?}",
                    e
                );
                // Don't fail the join if role update fails
            }
        }

        Ok(())
    }

    pub async fn update_livekit_access_token(
        &self,
        access_token: String,
    ) -> Result<(), MeetCoreError> {
        self.state.write().await.active_livekit_access_token = Some(access_token);
        debug!("Updated livekit access token");
        Ok(())
    }

    pub async fn update_livekit_access_token_and_websocket_url(
        &self,
        access_token: String,
        websocket_url: String,
    ) -> Result<(), MeetCoreError> {
        self.state.write().await.active_livekit_access_token = Some(access_token);
        self.state.write().await.active_livekit_websocket_url = Some(websocket_url);
        debug!("Updated livekit access token and websocket url");
        Ok(())
    }
    pub async fn get_active_livekit_access_token(&self) -> Result<String, MeetCoreError> {
        self.state
            .read()
            .await
            .active_livekit_access_token
            .clone()
            .ok_or(MeetCoreError::LivekitAccessTokenNotFound)
    }

    pub async fn get_active_livekit_websocket_url(&self) -> Result<String, MeetCoreError> {
        self.state
            .read()
            .await
            .active_livekit_websocket_url
            .clone()
            .ok_or(MeetCoreError::InternalError {
                message: "Livekit websocket url not found".to_string(),
                details: None,
            })
    }

    #[tracing::instrument(err, skip_all)]
    pub async fn authenticate_meeting_link(
        &self,
        meet_link_name: String,
        meet_link_password: String,
        display_name: String,
    ) -> Result<MeetInfo, MeetCoreError> {
        let (meet_info, session_key) = self
            .room_service
            .join_meeting(&meet_link_name, &meet_link_password, &display_name)
            .await?;

        {
            let mut state = self.state.write().await;
            state.meeting_display_name_session_key = session_key;
        }

        Ok(meet_info)
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn create_meeting(
        &self,
        meeting_name: String,
        has_session: bool,
        meeting_type: MeetingType,
        custom_password: Option<String>,
        start_time: Option<i64>,
        end_time: Option<i64>,
        time_zone: Option<String>,
        r_rule: Option<String>,
    ) -> Result<UpcomingMeeting, MeetCoreError> {
        let start_time = start_time.and_then(Self::to_utc_datetime);
        let end_time = end_time.and_then(Self::to_utc_datetime);
        let meeting = if has_session {
            debug!("create_meeting with session");
            let auth_info = self.get_user_state_info().await?;

            let mailbox_password = self
                .user_key_provider
                .get_user_key_passphrase(auth_info.user_id)
                .await
                .map_err(|e| MeetCoreError::StorageError {
                    message: format!("Failed to get mailbox password: {e}"),
                    details: None,
                })?;
            self.room_service
                .create_meeting(
                    &meeting_name,
                    custom_password,
                    Some(&auth_info.primary_address.id),
                    Some(&auth_info.active_user_key.private_key),
                    Some(&mailbox_password),
                    meeting_type,
                    false,
                    start_time,
                    end_time,
                    time_zone,
                    r_rule,
                )
                .await
                .map_err(MeetCoreError::from)?
        } else {
            debug!("create_meeting without session");
            self.room_service
                .create_meeting(
                    &meeting_name,
                    custom_password,
                    None,
                    None,
                    None,
                    MeetingType::Instant,
                    false,
                    None,
                    None,
                    None,
                    None,
                )
                .await
                .map_err(MeetCoreError::from)?
        };
        Ok(meeting)
    }

    fn to_utc_datetime(timestamp: i64) -> Option<DateTime<Utc>> {
        // Accept both seconds and milliseconds since epoch.
        if timestamp.abs() >= 1_000_000_000_000 {
            let secs = timestamp.div_euclid(1000);
            let millis = timestamp.rem_euclid(1000) as u32;
            DateTime::<Utc>::from_timestamp(secs, millis * 1_000_000)
        } else {
            DateTime::<Utc>::from_timestamp(timestamp, 0)
        }
    }

    pub async fn edit_meeting_name(
        &self,
        meeting_id: String,
        new_meeting_name: String,
        meeting_password: String,
    ) -> Result<UpcomingMeeting, MeetCoreError> {
        // check if the user is authenticated
        let _ = self.get_user_state_info().await?;
        let updated_meeting = self
            .room_service
            .edit_meeting_name(&meeting_id, &new_meeting_name, &meeting_password)
            .await?;
        Ok(updated_meeting)
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn update_meeting_schedule(
        &self,
        meeting_id: String,
        meeting_name: String,
        meeting_password: String,
        start_time: Option<i64>,
        end_time: Option<i64>,
        time_zone: Option<String>,
        r_rule: Option<String>,
    ) -> Result<UpcomingMeeting, MeetCoreError> {
        // check if the user is authenticated
        let _ = self.get_user_state_info().await?;
        let start_time = start_time
            .and_then(Self::to_utc_datetime)
            .map(|dt| dt.to_rfc3339());
        let end_time = end_time
            .and_then(Self::to_utc_datetime)
            .map(|dt| dt.to_rfc3339());
        let params = UpdateMeetingScheduleParams {
            start_time,
            end_time,
            r_rule,
            time_zone,
        };
        let updated_meeting = self
            .room_service
            .update_meeting_schedule(&meeting_id, &meeting_name, &meeting_password, params)
            .await?;
        Ok(updated_meeting)
    }

    pub async fn get_upcoming_meetings(&self) -> Result<Vec<UpcomingMeeting>, MeetCoreError> {
        let app_state = self.state.read().await;
        let user_state = app_state
            .active_user
            .as_ref()
            .ok_or(MeetCoreError::NoActiveUser)?;
        let user_private_keys = user_state.user_keys.clone();
        let user_id = user_state.user_data.id.clone();
        let mailbox_password = self
            .user_key_provider
            .get_user_key_passphrase(user_id)
            .await
            .map_err(|e| MeetCoreError::StorageError {
                message: format!("Failed to get mailbox password: {e}"),
                details: None,
            })?;
        let all_address_keys: Vec<ProtonUserKey> = user_state
            .user_addresses
            .iter()
            .flat_map(|address| address.keys.clone())
            .collect();

        let upcoming_meetings = self
            .room_service
            .get_upcoming_meetings(&user_private_keys, &all_address_keys, &mailbox_password)
            .await?;
        Ok(upcoming_meetings)
    }

    pub async fn create_personal_meeting(
        &self,
        meeting_name: String,
        custom_password: Option<String>,
        is_rotate: bool,
    ) -> Result<UpcomingMeeting, MeetCoreError> {
        let auth_info = self.get_user_state_info().await?;

        let mailbox_password = self
            .user_key_provider
            .get_user_key_passphrase(auth_info.user_id)
            .await
            .map_err(|e| MeetCoreError::StorageError {
                message: format!("Failed to get mailbox password: {e}"),
                details: None,
            })?;

        let meeting = self
            .room_service
            .create_meeting(
                &meeting_name,
                custom_password,
                Some(&auth_info.primary_address.id),
                Some(&auth_info.active_user_key.private_key),
                Some(&mailbox_password),
                MeetingType::Personal,
                is_rotate,
                None,
                None,
                None,
                None,
            )
            .await?;

        Ok(meeting)
    }

    async fn connect_to_ws(&self) -> Result<(), MeetCoreError> {
        let total_start = instant::now();
        let app_state = self.state.read().await;

        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?
            .clone();
        let user_id = user_info.user_id();
        let sd_start = instant::now();
        let sd_kbt = self.user_service.read().await.get_sd_kbt(&user_id).await?;
        debug!(
            "connect_to_ws step=get_sd_kbt ms={}",
            sd_start.elapsed().as_millis()
        );

        // need to clone the client to avoid borrow checker error
        let client = self.ws_client.clone();

        // Retry mechanism: retry up to 3 times on HTTP/WebSocket errors
        const MAX_RETRIES: u32 = 3;
        const RETRY_DELAY_MS: u64 = 200;
        let mut last_error = None;

        for attempt in 1..=MAX_RETRIES {
            let attempt_start = instant::now();
            match client.connect(&sd_kbt).await {
                Ok(_) => {
                    if attempt > 1 {
                        warn!(
                            "WebSocket connection succeeded on attempt {} ms={}",
                            attempt,
                            attempt_start.elapsed().as_millis()
                        );
                    } else {
                        debug!(
                            "WebSocket connection succeeded on attempt {} ms={}",
                            attempt,
                            attempt_start.elapsed().as_millis()
                        );
                    }
                    let _ = client.start_listening_task();
                    debug!(
                        "connect_to_ws step=done total_ms={}",
                        total_start.elapsed().as_millis()
                    );
                    return Ok(());
                }
                Err(e) => {
                    let error_msg = e.to_string();
                    last_error = Some(e);

                    if attempt < MAX_RETRIES {
                        warn!(
                            "WebSocket connection failed on attempt {}/{}: {}. attempt_ms={} Retrying...",
                            attempt,
                            MAX_RETRIES,
                            error_msg,
                            attempt_start.elapsed().as_millis()
                        );
                        // Wait 1 second before retrying
                        sleep(Duration::from_millis(RETRY_DELAY_MS)).await;
                    } else {
                        error!(
                            "WebSocket connection failed after {} attempts: {} total_ms={}",
                            MAX_RETRIES,
                            error_msg,
                            total_start.elapsed().as_millis()
                        );
                    }
                }
            }
        }

        // Convert anyhow::Error to MeetCoreError
        // This should never be None since we only reach here if all retries failed
        match last_error {
            Some(error) => Err(MeetCoreError::WebSocketError {
                message: error.to_string(),
            }),
            None => Err(MeetCoreError::WebSocketError {
                message: "WebSocket connection failed: unknown error".to_string(),
            }),
        }
    }

    async fn disconnect_from_ws(&self) -> Result<(), MeetCoreError> {
        Ok(self.ws_client.disconnect(Some(true)).await?)
    }

    /// Manually trigger WebSocket reconnection, typically called when network connectivity changes.
    /// This is useful for mobile apps to proactively reconnect when switching networks.
    pub async fn trigger_websocket_reconnect(&self) -> Result<(), MeetCoreError> {
        self.ws_client
            .trigger_reconnect()
            .await
            .map_err(|e| MeetCoreError::WebSocketError {
                message: e.to_string(),
            })
    }

    pub async fn get_participants(
        &self,
        meet_link_name: String,
    ) -> Result<Vec<MeetParticipant>, MeetCoreError> {
        let session_key = self
            .state
            .read()
            .await
            .meeting_display_name_session_key
            .clone();
        let participants = self.room_service.get_participants(&meet_link_name).await?;
        let participants = self
            .room_service
            .decrypt_participant_display_names(participants, session_key.as_deref())
            .await;
        Ok(participants)
    }

    pub async fn get_participants_count(
        &self,
        meet_link_name: String,
    ) -> Result<u32, MeetCoreError> {
        let count = self
            .room_service
            .get_participants_count(&meet_link_name)
            .await?;
        Ok(count)
    }

    pub async fn lock_meeting(&self, meet_link_name: String) -> Result<(), MeetCoreError> {
        self.room_service.lock_meeting(&meet_link_name).await?;
        Ok(())
    }

    pub async fn unlock_meeting(&self, meet_link_name: String) -> Result<(), MeetCoreError> {
        self.room_service.unlock_meeting(&meet_link_name).await?;
        Ok(())
    }

    pub fn get_join_type(
        &self,
        is_new_join_type: bool,
        enable_join_type_switch: bool,
        current_participant_count: u32,
    ) -> JoinType {
        debug!("get_join_type(), is_new_join_type={}, enable_join_type_switch={}, current_participant_count={}, threshold={}", 
            is_new_join_type, enable_join_type_switch, current_participant_count, JOIN_TYPE_SWITCH_THRESHOLD);
        if is_new_join_type && enable_join_type_switch {
            if current_participant_count >= JOIN_TYPE_SWITCH_THRESHOLD {
                debug!("get_join_type() switching to ExternalProposal for large meeting room");
                JoinType::ExternalProposal
            } else {
                debug!("get_join_type() staying on ExternalCommit for small meeting room");
                JoinType::ExternalCommit
            }
        } else if is_new_join_type {
            debug!("get_join_type() switching to ExternalProposal");
            JoinType::ExternalProposal
        } else {
            debug!("get_join_type() staying on ExternalCommit");
            JoinType::ExternalCommit
        }
    }

    async fn join_room(&self) -> Result<(), MeetCoreError> {
        let total_start = instant::now();
        let (user_token_info, use_psk) = {
            let app_state = self.state.read().await;
            (
                app_state
                    .active_user_info
                    .as_ref()
                    .ok_or(MeetCoreError::ParticipantNotFound)?
                    .clone(),
                app_state.use_psk,
            )
        };
        let user_id = user_token_info.user_id();
        let meeting_start = instant::now();
        let meeting_id = self
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;
        debug!(
            "join_room step=get_meeting_id ms={}",
            meeting_start.elapsed().as_millis()
        );

        let join_call_start = instant::now();
        self.user_service
            .read()
            .await
            .join_room(&user_token_info, &meeting_id, use_psk)
            .await?;

        {
            let mut app_state = self.state.write().await;
            app_state.join_mls_time = Some(crate::utils::instant::now());
            app_state.join_type = Some(JoinType::ExternalCommit);
        }
        debug!(
            "join_room step=join_room_call ms={} total_ms={}",
            join_call_start.elapsed().as_millis(),
            total_start.elapsed().as_millis()
        );
        Ok(())
    }

    async fn join_room_with_proposal(&self) -> Result<(), MeetCoreError> {
        let total_start = instant::now();
        let user_info = {
            let app_state = self.state.read().await;
            app_state
                .active_user_info
                .as_ref()
                .ok_or(MeetCoreError::ParticipantNotFound)?
                .clone()
        };
        let user_id = user_info.user_id();
        let meeting_start = instant::now();
        let meeting_id = self
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;
        debug!(
            "join_room_with_proposal step=get_meeting_id ms={}",
            meeting_start.elapsed().as_millis()
        );

        let join_call_start = instant::now();
        self.user_service
            .read()
            .await
            .join_room_with_proposal(&user_id, &meeting_id)
            .await?;

        {
            let mut app_state = self.state.write().await;
            app_state.join_mls_time = Some(crate::utils::instant::now());
            app_state.join_type = Some(JoinType::ExternalProposal);
        }
        debug!(
            "join_room_with_proposal step=join_room_call ms={} total_ms={}",
            join_call_start.elapsed().as_millis(),
            total_start.elapsed().as_millis()
        );
        Ok(())
    }

    /// Log metrics when room join is successful, this method must be called right after the room is showing to user on client side
    pub async fn log_joined_room(
        &self,
        is_vp9_decode_supported: Option<bool>,
        is_vp9_encode_supported: Option<bool>,
    ) -> Result<(), MeetCoreError> {
        let state = self.state.read().await;
        let join_start_time =
            state
                .join_start_time
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "join_start_time not set".to_string(),
                    details: None,
                })?;

        let join_mls_time_ms = state
            .join_mls_time
            .map(|mls_time| {
                // Calculate duration between join_start_time and mls_time
                // Since we can't directly subtract two Instants, we calculate:
                // (current_time - join_start_time) - (current_time - mls_time) = mls_time - join_start_time
                let total_elapsed = join_start_time.elapsed();
                let mls_elapsed = mls_time.elapsed();
                if total_elapsed >= mls_elapsed {
                    (total_elapsed - mls_elapsed).as_millis() as u64
                } else {
                    0
                }
            })
            .unwrap_or(0);

        let join_type = state.join_type;

        drop(state);

        let join_room_time_ms = join_start_time.elapsed().as_millis() as u64;

        // Get MLS retry count from Service
        let mls_retry_count = self.user_service.read().await.get_mls_retry_count().await;

        // Get user_id and room_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);

        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;

        // Get app_version and user_agent from state
        let (app_version, user_agent) = {
            let app_state = self.state.read().await;
            let app_version = app_state
                .app_version
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "app_version not set".to_string(),
                    details: None,
                })?
                .clone();
            let user_agent = app_state
                .user_agent
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "user_agent not set".to_string(),
                    details: None,
                })?
                .clone();
            (app_version, user_agent)
        };

        // Build metrics request
        let metrics_request = ServiceMetricsRequest {
            user_join_time: Some(UserJoinTimeMetric {
                room_join_time_ms: join_room_time_ms,
                mls_join_time_ms: join_mls_time_ms,
                join_type,
                is_vp9_decode_supported,
                is_vp9_encode_supported,
            }),
            user_retry_count: Some(UserRetryCountMetric {
                retry_count: mls_retry_count,
            }),
            error_code: None,
            connection_lost: None,
            user_epoch_health: None,
            designated_committer: None,
            user_rejoin: None,
        };

        // Send metrics
        self.http_client
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }

    /// Log metrics when room join fails, this method must be called right after the room join fails on client side
    pub async fn log_joined_room_failed(
        &self,
        error_code: Option<String>,
    ) -> Result<(), MeetCoreError> {
        let state = self.state.read().await;
        let join_start_time =
            state
                .join_start_time
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "join_start_time not set".to_string(),
                    details: None,
                })?;

        let join_room_time_ms = join_start_time.elapsed().as_millis() as u64;

        drop(state);

        // Get MLS retry count from Service
        let mls_retry_count = self.user_service.read().await.get_mls_retry_count().await;

        // Get user_id and room_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);
        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;

        // Get app_version and user_agent from state
        let (app_version, user_agent) = {
            let app_state = self.state.read().await;
            let app_version = app_state
                .app_version
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "app_version not set".to_string(),
                    details: None,
                })?
                .clone();
            let user_agent = app_state
                .user_agent
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "user_agent not set".to_string(),
                    details: None,
                })?
                .clone();
            (app_version, user_agent)
        };

        // Build metrics request with error
        let metrics_request = ServiceMetricsRequest {
            user_join_time: Some(UserJoinTimeMetric {
                room_join_time_ms: join_room_time_ms,
                mls_join_time_ms: join_room_time_ms,
                join_type: None,
                is_vp9_decode_supported: None,
                is_vp9_encode_supported: None,
            }),
            user_retry_count: Some(UserRetryCountMetric {
                retry_count: mls_retry_count,
            }),
            error_code: error_code.map(|code| ErrorCodeMetric {
                error_code: code,
                error_message: None,
            }),
            connection_lost: None,
            user_epoch_health: None,
            designated_committer: None,
            user_rejoin: None,
        };

        // Send metrics
        self.http_client
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }

    pub async fn log_connection_lost(&self) -> Result<(), MeetCoreError> {
        // Get user_id and room_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);
        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;

        // Get metrics from ServiceState (recorded by is_mls_up_to_date)
        let mls_sync_metrics = self
            .user_service
            .read()
            .await
            .get_mls_sync_metrics()
            .await
            .ok_or_else(|| MeetCoreError::InternalError {
                message: "MLS sync metrics not available".to_string(),
                details: None,
            })?;

        // Get RTT via ping
        let rtt = self.ping().await.unwrap_or(0) as u32;

        // Get app_version and user_agent from state
        let (app_version, user_agent) = {
            let app_state = self.state.read().await;
            let app_version = app_state
                .app_version
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "app_version not set".to_string(),
                    details: None,
                })?
                .clone();
            let user_agent = app_state
                .user_agent
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "user_agent not set".to_string(),
                    details: None,
                })?
                .clone();
            (app_version, user_agent)
        };

        let metrics_request = ServiceMetricsRequest {
            user_join_time: None,
            user_retry_count: None,
            error_code: None,
            connection_lost: Some(ConnectionLostMetric {
                local_epoch: mls_sync_metrics.local_epoch,
                server_epoch: mls_sync_metrics.server_epoch,
                is_user_device_in_group_info: mls_sync_metrics.is_user_device_in_group_info,
                is_websocket_disconnected: mls_sync_metrics.is_websocket_disconnected,
                has_websocket_reconnected: mls_sync_metrics.has_websocket_reconnected,
                rtt,
                is_get_group_info_success: mls_sync_metrics.is_get_group_info_success,
                connection_lost_type: mls_sync_metrics.connection_lost_type,
            }),
            user_epoch_health: None,
            designated_committer: None,
            user_rejoin: None,
        };
        self.http_client
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }

    /// Log user epoch health metrics, the current_epoch and epoch_display_code will be passed from client side
    pub async fn log_user_epoch_health(
        &self,
        current_epoch: u32,
        epoch_display_code: String,
    ) -> Result<(), MeetCoreError> {
        // Get user_id and meeting_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);

        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;
        // Get RTT via ping
        let rtt = self.ping().await.unwrap_or(0) as u32;

        // websocket_rtt is not available, set to None
        let websocket_rtt = self.ws_client.get_last_rtt_ms().await;

        // Get app_version and user_agent from state
        let (app_version, user_agent) = {
            let app_state = self.state.read().await;
            let app_version = app_state
                .app_version
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "app_version not set".to_string(),
                    details: None,
                })?
                .clone();
            let user_agent = app_state
                .user_agent
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "user_agent not set".to_string(),
                    details: None,
                })?
                .clone();
            (app_version, user_agent)
        };

        // Build metrics request
        let metrics_request = ServiceMetricsRequest {
            user_join_time: None,
            user_retry_count: None,
            error_code: None,
            connection_lost: None,
            user_epoch_health: Some(UserEpochHealthMetric {
                local_epoch: current_epoch,
                epoch_authenticator: Some(epoch_display_code),
                rtt,
                websocket_rtt,
            }),
            designated_committer: None,
            user_rejoin: None,
        };

        // Send metrics
        self.http_client
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }

    /// Try to log designated committer metrics, if this client is not the committer for this epoch, do nothing
    pub async fn try_log_designated_committer(&self, epoch: u32) -> Result<(), MeetCoreError> {
        // Get user_id and meeting_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);

        let mls_designated_committer_metrics = self
            .user_service
            .read()
            .await
            .get_mls_designated_committer_metrics_at_epoch(epoch)
            .await;

        let Some(designated_committer_metrics) = mls_designated_committer_metrics else {
            return Ok(());
        };

        if !designated_committer_metrics.is_committer {
            return Ok(());
        }

        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;

        // Get app_version and user_agent from state
        let (app_version, user_agent) = {
            let app_state = self.state.read().await;
            let app_version = app_state
                .app_version
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "app_version not set".to_string(),
                    details: None,
                })?
                .clone();
            let user_agent = app_state
                .user_agent
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "user_agent not set".to_string(),
                    details: None,
                })?
                .clone();
            (app_version, user_agent)
        };

        // Build metrics request
        let metrics_request = ServiceMetricsRequest {
            user_join_time: None,
            user_retry_count: None,
            error_code: None,
            connection_lost: None,
            user_epoch_health: None,
            designated_committer: Some(DesignatedCommitterMetric {
                epoch,
                designated_committer_rank: designated_committer_metrics.rank,
                new_member_count: designated_committer_metrics.new_member_count,
                removed_member_count: designated_committer_metrics.removed_member_count,
            }),
            user_rejoin: None,
        };

        // Send metrics
        self.http_client
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }

    /// Log user rejoin metrics, parameters will be passed from client side
    pub async fn log_user_rejoin(
        &self,
        rejoin_time_ms: u64,
        incremental_count: u32,
        reason: RejoinReason,
        success: bool,
    ) -> Result<(), MeetCoreError> {
        // Get user_id and meeting_id
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        drop(app_state);

        // Get base64_sd_kbt for authorization
        let base64_sd_kbt = self
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: format!("Failed to get sd_kbt: {e}"),
                details: None,
            })?;

        // Get app_version and user_agent from state
        let (app_version, user_agent) = {
            let app_state = self.state.read().await;
            let app_version = app_state
                .app_version
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "app_version not set".to_string(),
                    details: None,
                })?
                .clone();
            let user_agent = app_state
                .user_agent
                .as_ref()
                .ok_or_else(|| MeetCoreError::InternalError {
                    message: "user_agent not set".to_string(),
                    details: None,
                })?
                .clone();
            (app_version, user_agent)
        };

        // Build metrics request
        let metrics_request = ServiceMetricsRequest {
            user_join_time: None,
            user_retry_count: None,
            error_code: None,
            connection_lost: None,
            user_epoch_health: None,
            designated_committer: None,
            user_rejoin: Some(UserRejoinMetric {
                rejoin_time_ms,
                incremental_count,
                reason,
                success,
            }),
        };

        // Send metrics
        self.http_client
            .send_metrics(&base64_sd_kbt, &app_version, &user_agent, &metrics_request)
            .await
            .map_err(|e| MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            })?;

        Ok(())
    }

    pub async fn kick_participant(&self, participant_id: String) -> Result<(), MeetCoreError> {
        let user_token_info = {
            let app_state = self.state.read().await;
            app_state
                .active_user_info
                .as_ref()
                .ok_or(MeetCoreError::ParticipantNotFound)?
                .clone()
        };
        let user_id = user_token_info.user_id();
        let meeting_id = self
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;

        self.user_service
            .read()
            .await
            .kick_participant(&participant_id, &meeting_id)
            .await?;

        Ok(())
    }
}

impl App {
    pub async fn disconnect_wss_intentional(&self) -> Result<(), anyhow::Error> {
        self.ws_client.disconnect(Some(true)).await
    }

    pub async fn disconnect_wss_unintentional(&self) -> Result<(), anyhow::Error> {
        self.ws_client.disconnect(Some(false)).await
    }
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct GroupKeyInfo {
    pub key: String,
    pub epoch: u64,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct GroupDisplayCode {
    pub full_code: String,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct ParticipantTrackSettingsInfo {
    pub audio: u8,
    pub video: u8,
}

#[derive(Clone, Debug)]
#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct DecryptedMessageInfo {
    pub message: String,
    pub sender_participant_id: String,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct UserSettingsInfo {
    pub meeting_id: String,
    pub address_id: String,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
#[derive(Clone)]
pub struct MeetingInfo {
    pub id: String,
    pub address_id: Option<String>,
    pub meeting_link_name: String,
    pub meeting_name: String,
    pub password: Option<String>,
    pub salt: String,
    pub session_key: String,
    pub srp_modulus_id: String,
    pub srp_salt: String,
    pub srp_verifier: String,
    pub r_rule: Option<String>,
    pub time_zone: Option<String>,
    pub custom_password: u8,
    pub meeting_type: u8,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct MeetingInfoWithPassword {
    pub meeting: MeetingInfo,
    pub password: String,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConnectionStateInfo {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum JoinTypeInfo {
    ExternalCommit = 0,
    ExternalProposal = 1,
}

impl From<JoinType> for JoinTypeInfo {
    fn from(join_type: JoinType) -> Self {
        match join_type {
            JoinType::ExternalCommit => JoinTypeInfo::ExternalCommit,
            JoinType::ExternalProposal => JoinTypeInfo::ExternalProposal,
        }
    }
}

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MlsSyncStateInfo {
    Success = 0,
    Checking = 1,
    Retrying = 2,
    Failed = 3,
}

#[cfg(target_family = "wasm")]
impl From<crate::service::service_state::MlsSyncState> for MlsSyncStateInfo {
    fn from(state: crate::service::service_state::MlsSyncState) -> Self {
        match state {
            crate::service::service_state::MlsSyncState::Success => MlsSyncStateInfo::Success,
            crate::service::service_state::MlsSyncState::Checking => MlsSyncStateInfo::Checking,
            crate::service::service_state::MlsSyncState::Retrying => MlsSyncStateInfo::Retrying,
            crate::service::service_state::MlsSyncState::Failed => MlsSyncStateInfo::Failed,
        }
    }
}

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RejoinReasonInfo {
    EpochMismatch = 0,
    WebsocketDisconnected = 1,
    MemberNotFoundInMLS = 2,
    FetchTimeout = 3,
    LivekitStateMismatch = 4,
    LivekitConnectionTimeout = 5,
    Other = 6,
}

#[cfg(target_family = "wasm")]
impl From<RejoinReason> for RejoinReasonInfo {
    fn from(reason: RejoinReason) -> Self {
        match reason {
            RejoinReason::EpochMismatch => RejoinReasonInfo::EpochMismatch,
            RejoinReason::WebsocketDisconnected => RejoinReasonInfo::WebsocketDisconnected,
            RejoinReason::MemberNotFoundInMLS => RejoinReasonInfo::MemberNotFoundInMLS,
            RejoinReason::FetchTimeout => RejoinReasonInfo::FetchTimeout,
            RejoinReason::LivekitStateMismatch => RejoinReasonInfo::LivekitStateMismatch,
            RejoinReason::LivekitConnectionTimeout => RejoinReasonInfo::LivekitConnectionTimeout,
            RejoinReason::Other => RejoinReasonInfo::Other,
        }
    }
}

#[cfg(target_family = "wasm")]
impl From<RejoinReasonInfo> for RejoinReason {
    fn from(reason: RejoinReasonInfo) -> Self {
        match reason {
            RejoinReasonInfo::EpochMismatch => RejoinReason::EpochMismatch,
            RejoinReasonInfo::WebsocketDisconnected => RejoinReason::WebsocketDisconnected,
            RejoinReasonInfo::MemberNotFoundInMLS => RejoinReason::MemberNotFoundInMLS,
            RejoinReasonInfo::FetchTimeout => RejoinReason::FetchTimeout,
            RejoinReasonInfo::LivekitStateMismatch => RejoinReason::LivekitStateMismatch,
            RejoinReasonInfo::LivekitConnectionTimeout => RejoinReason::LivekitConnectionTimeout,
            RejoinReasonInfo::Other => RejoinReason::Other,
        }
    }
}

#[cfg(target_family = "wasm")]
impl From<ConnectionState> for ConnectionStateInfo {
    fn from(state: ConnectionState) -> Self {
        match state {
            ConnectionState::Disconnected => ConnectionStateInfo::Disconnected,
            ConnectionState::Connecting => ConnectionStateInfo::Connecting,
            ConnectionState::Connected => ConnectionStateInfo::Connected,
            ConnectionState::Reconnecting => ConnectionStateInfo::Reconnecting,
        }
    }
}

#[cfg(target_family = "wasm")]
impl App {
    fn init_logging() {
        let _ = tracing_subscriber::fmt()
            .with_max_level(tracing::Level::DEBUG)
            .with_ansi(false)
            .with_timer(tracing_subscriber::fmt::time::ChronoLocal::new(
                "%H:%M:%S%.3f".to_string(),
            ))
            .with_writer(tracing_web::MakeWebConsoleWriter::new().with_pretty_level())
            .with_level(false) // Level is part of the "pretty level" in the console writer
            .try_init();
    }
}

#[cfg(target_family = "wasm")]
#[wasm_bindgen]
impl App {
    #[wasm_bindgen(constructor)]
    pub async fn new_wasm(
        env: String,
        app_version: String,
        user_agent: String,
        db_path: String,
        http_host: String,
        ws_host: String,
        user_id_str: String,
        uid_str: String,
    ) -> Result<Self, JsValue> {
        use crate::infra::UserKeyProviderAdapter;
        let auth = Auth::external(user_id_str, uid_str);
        let config = ApiConfig {
            spec: (app_version, user_agent),
            auth: Some(auth),
            url_prefix: None,
            env: Some(env),
            store: None,
            proxy: None,
        };
        let user_key_provider = Arc::new(UserKeyProviderAdapter::new());
        Self::from_config(config, db_path, http_host, ws_host, user_key_provider)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = joinMeetingWithAccessToken)]
    pub async fn join_meeting_with_access_token_wasm(
        &self,
        access_token: String,
        meet_link_name: String,
        meeting_password: String,
        use_psk: bool,
        session_id: Option<String>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.join_meeting_with_access_token(
            access_token,
            meet_link_name,
            meeting_password,
            use_psk,
            session_id,
        )
        .await
        .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = joinRoomWithProposal)]
    pub async fn join_meeting_with_access_token_with_proposal_wasm(
        &self,
        access_token: String,
        meet_link_name: String,
        meeting_password: String,
        use_psk: bool,
        session_id: Option<String>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.join_meeting_with_access_token_with_proposal(
            access_token,
            meet_link_name,
            meeting_password,
            use_psk,
            session_id,
        )
        .await
        .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = updateLivekitAccessToken)]
    pub async fn update_livekit_access_token_wasm(
        &self,
        access_token: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.update_livekit_access_token(access_token)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = getWsState)]
    pub async fn get_ws_state_wasm(
        &self,
    ) -> Result<ConnectionStateInfo, crate::errors::core::MeetCoreErrorEnum> {
        let ws_state = self
            .get_ws_state()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))?;
        Ok(ConnectionStateInfo::from(ws_state))
    }

    #[wasm_bindgen(js_name = setWebsocketPingInterval)]
    pub async fn set_websocket_ping_interval_wasm(
        &self,
        seconds: Option<u64>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.set_websocket_ping_interval(seconds)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = setWebsocketMaxPingFailures)]
    pub async fn set_websocket_max_ping_failures_wasm(
        &self,
        failures: Option<u32>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.set_websocket_max_ping_failures(failures)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = setWebsocketPongTimeout)]
    pub async fn set_websocket_pong_timeout_wasm(
        &self,
        seconds: Option<u64>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.set_websocket_pong_timeout(seconds)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = setLivekitActiveUuids)]
    pub async fn set_livekit_active_uuids_wasm(
        &self,
        livekit_active_uuid_list: Vec<String>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.set_livekit_active_uuids(livekit_active_uuid_list)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = isMlsUpToDate)]
    pub async fn is_mls_up_to_date_wasm(&self) -> Result<bool, JsValue> {
        let is_up_to_date = self.is_mls_up_to_date().await?;
        Ok(is_up_to_date)
    }

    #[wasm_bindgen(js_name = isWebsocketHasReconnected)]
    pub async fn is_websocket_has_reconnected_wasm(&self) -> Result<bool, JsValue> {
        let has_reconnected = self.is_websocket_has_reconnected().await?;
        Ok(has_reconnected)
    }

    #[wasm_bindgen(js_name = getGroupKey)]
    pub async fn get_group_key_wasm(
        &self,
    ) -> Result<GroupKeyInfo, crate::errors::core::MeetCoreErrorEnum> {
        let (key, epoch) = self
            .get_group_key()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))?;
        Ok(GroupKeyInfo { key, epoch })
    }

    #[wasm_bindgen(js_name = getGroupLen)]
    pub async fn get_group_len_wasm(&self) -> Result<u32, crate::errors::core::MeetCoreErrorEnum> {
        self.get_group_len()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))
    }

    #[wasm_bindgen(js_name = getGroupDisplayCode)]
    pub async fn get_group_display_code_wasm(
        &self,
    ) -> Result<GroupDisplayCode, crate::errors::core::MeetCoreErrorEnum> {
        let full_code = self.get_group_display_code().await?;
        Ok(GroupDisplayCode { full_code })
    }

    #[wasm_bindgen(js_name = leaveMeeting)]
    pub async fn leave_meeting_wasm(&self) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.leave_meeting().await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = updateParticipantTrackSettings)]
    pub async fn update_participant_track_settings_wasm(
        &self,
        participant_uuid: String,
        audio: Option<u8>,
        video: Option<u8>,
    ) -> Result<ParticipantTrackSettingsInfo, JsValue> {
        let participant_track_settings = self
            .update_participant_track_settings(participant_uuid, audio, video)
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))?;
        Ok(ParticipantTrackSettingsInfo {
            audio: participant_track_settings.audio,
            video: participant_track_settings.video,
        })
    }

    #[wasm_bindgen(js_name = getActiveMeetings)]
    pub async fn get_active_meetings_wasm(&self) -> Result<Vec<MeetingInfo>, JsValue> {
        let active_meetings = self
            .get_active_meetings()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))?;
        Ok(active_meetings
            .into_iter()
            .map(|m| MeetingInfo {
                id: m.id,
                address_id: m.address_id.clone(),
                meeting_link_name: m.meeting_link_name,
                meeting_name: m.meeting_name,
                password: m.password,
                salt: m.salt,
                session_key: m.session_key,
                srp_modulus_id: m.srp_modulus_id,
                srp_salt: m.srp_salt,
                srp_verifier: m.srp_verifier,
                r_rule: m.r_rule,
                time_zone: m.time_zone,
                custom_password: m.custom_password as u8,
                meeting_type: m.meeting_type as u8,
            })
            .collect::<Vec<_>>())
    }

    #[wasm_bindgen(js_name = getUserSettings)]
    pub async fn get_user_settings_wasm(&self) -> Result<UserSettingsInfo, JsValue> {
        let user_settings = self
            .get_user_settings()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))?;
        Ok(UserSettingsInfo {
            meeting_id: user_settings.meeting_id,
            address_id: user_settings.address_id,
        })
    }

    #[wasm_bindgen(js_name = removeParticipant)]
    pub async fn remove_participant_wasm(
        &self,
        participant_uuid: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.remove_participant(participant_uuid)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = encryptMessage)]
    pub async fn encrypt_message_wasm(
        &self,
        message: String,
    ) -> Result<Vec<u8>, crate::errors::core::MeetCoreErrorEnum> {
        self.encrypt_message(&message).await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = getJoinType)]
    pub fn get_join_type_wasm(
        &self,
        is_new_join_type: bool,
        enable_join_type_switch: bool,
        current_participant_count: u32,
    ) -> JoinTypeInfo {
        let join_type = self.get_join_type(
            is_new_join_type,
            enable_join_type_switch,
            current_participant_count,
        );
        join_type.into()
    }

    #[wasm_bindgen(js_name = endMeeting)]
    pub async fn end_meeting_wasm(&self) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.end_meeting().await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = decryptMessage)]
    pub async fn decrypt_message_wasm(
        &self,
        data: Vec<u8>,
    ) -> Result<DecryptedMessageInfo, JsValue> {
        self.decrypt_message(data).await.map_err(|e| e.into())
    }

    #[cfg(all(target_family = "wasm", not(test)))]
    #[wasm_bindgen(js_name = setMlsGroupUpdateHandler)]
    pub async fn set_mls_group_update_handler_wasm(&self) -> Result<(), JsValue> {
        self.user_service
            .write()
            .await
            .set_mls_group_update_handler(|meeting_link_name| {
                Box::pin(async move {
                    new_group_key_for(meeting_link_name.clone());
                })
            });
        Ok(())
    }

    #[cfg(all(target_family = "wasm", not(test)))]
    #[wasm_bindgen(js_name = setMlsSyncStateUpdateHandler)]
    pub async fn set_mls_sync_state_update_handler_wasm(&self) -> Result<(), JsValue> {
        self.user_service
            .write()
            .await
            .set_mls_sync_state_update_handler(|state, reason| {
                Box::pin(async move {
                    let state_info: MlsSyncStateInfo = state.into();
                    let reason_info = reason.map(|r| r.into());
                    on_mls_sync_state_changed(state_info, reason_info);
                })
            });
        Ok(())
    }

    #[cfg(all(target_family = "wasm", not(test)))]
    #[wasm_bindgen(js_name = setLiveKitAdminChangeHandler)]
    pub async fn set_livekit_admin_change_handler_wasm(&self) -> Result<(), JsValue> {
        self.user_service
            .write()
            .await
            .set_livekit_admin_change_handler(|room_id, participant_uid, participant_type| {
                Box::pin(async move {
                    on_livekit_admin_changed(
                        room_id.clone(),
                        participant_uid.clone(),
                        participant_type,
                    );
                })
            });
        Ok(())
    }

    #[wasm_bindgen(js_name = setDisconnectionHandler)]
    pub async fn set_disconnection_handler_wasm(&self) -> Result<(), JsValue> {
        self.ws_client
            .set_disconnection_handler(Arc::new(move |_| {
                wasm_bindgen_futures::spawn_local(async move {
                    disconnection_handler();
                });
            }))
            .await;
        Ok(())
    }

    #[wasm_bindgen(js_name = triggerWebSocketReconnect)]
    pub async fn trigger_websocket_reconnect_wasm(
        &self,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.trigger_websocket_reconnect()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))
    }

    #[wasm_bindgen(js_name = logJoinedRoom)]
    pub async fn log_joined_room_wasm(
        &self,
        is_vp9_decode_supported: Option<bool>,
        is_vp9_encode_supported: Option<bool>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.log_joined_room(is_vp9_decode_supported, is_vp9_encode_supported)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = logJoinedRoomFailed)]
    pub async fn log_joined_room_failed_wasm(
        &self,
        error_code: Option<String>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.log_joined_room_failed(error_code)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = logConnectionLost)]
    pub async fn log_connection_lost_wasm(
        &self,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.log_connection_lost().await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = logUserEpochHealth)]
    pub async fn log_user_epoch_health_wasm(
        &self,
        current_epoch: u32,
        epoch_display_code: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.log_user_epoch_health(current_epoch, epoch_display_code)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = logUserRejoin)]
    pub async fn log_user_rejoin_wasm(
        &self,
        rejoin_time_ms: u64,
        incremental_count: u32,
        reason: RejoinReasonInfo,
        success: bool,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        let rejoin_reason: RejoinReason = reason.into();
        self.log_user_rejoin(rejoin_time_ms, incremental_count, rejoin_reason, success)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = tryLogDesignatedCommitter)]
    pub async fn try_log_designated_committer_wasm(
        &self,
        epoch: u32,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.try_log_designated_committer(epoch)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = ping)]
    pub async fn ping_wasm(&self) -> Result<u64, crate::errors::core::MeetCoreErrorEnum> {
        self.ping().await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = testWasm)]
    pub async fn test_wasm(&self) -> crate::errors::core::Result<()> {
        Err(crate::errors::core::MeetCoreError::PasswordTooShort)
    }
}

#[cfg(all(target_family = "wasm", not(test)))]
#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = newGroupKeyEvent)]
    pub fn new_group_key_for(meeting_link_name: String);

    #[wasm_bindgen(js_namespace = livekitAdminChangeEvent)]
    pub fn on_livekit_admin_changed(
        room_id: String,
        participant_uid: String,
        participant_type: u32,
    );

    #[wasm_bindgen(js_namespace = disconnectionEvent)]
    pub fn disconnection_handler();

    #[wasm_bindgen(js_namespace = mlsSyncStateChangeEvent)]
    pub fn on_mls_sync_state_changed(state: MlsSyncStateInfo, reason: Option<RejoinReasonInfo>);
}

// Provide a stub for tests
#[cfg(all(target_family = "wasm", test))]
pub fn disconnection_handler() {
    // Stub implementation for tests
    debug!("disconnection_handler called in test");
}
