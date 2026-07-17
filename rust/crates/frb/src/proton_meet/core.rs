pub use proton_meet_core::infra::dto::proton_user::UserData;
use proton_meet_core::{
    domain::user::models::{MeetParticipant, MeetingType},
    errors::login::LoginError,
    muon::{Auth, Tokens},
    ProtonUser,
};
use proton_meet_crypto::MeetCrypto;
use std::sync::Arc;
use std::sync::OnceLock;
use tokio::runtime::{Handle, Runtime};
use tokio::sync::broadcast;

use crate::proton_meet::models::chat_event::FrbChatComposeResult;
use crate::{
    errors::BridgeError,
    frb_generated::StreamSink,
    proton_meet::models::{
        app_event::AppEvent,
        connection_state::ConnectionState,
        event::FrbGetEventsResponse,
        join_request::{FrbSubmitJoinRequestResponse, JoinRequestChange},
        join_type::JoinType,
        meet_info::FrbMeetInfo,
        meeting_info::FrbMeetingInfo,
        mls_sync_state::MlsSyncState,
        participant_track_settings::FrbParticipantTrackSettings,
        proton_user_session::ProtonUserSession,
        rejoin_reason::RejoinReason,
        schedule_meeting::ScheduleMeetingRequest,
        upcoming_meeting::FrbUpcomingMeeting,
    },
};

use super::meet_auth_store::ProtonMeetAuthStore;
use super::storage::user_key_provider::FrbUserKeyProvider;
use super::user_config::UserConfig;
use flutter_rust_bridge::{frb, DartFnFuture};
use proton_meet_app::user_config::user_config::{ConfigStorage, VideoMaxBitrate, VideoResolution};
use proton_meet_calendar::{IcsEvent, RecurrenceRule};
use proton_meet_chat::legacy_wire::MeetChatMessage;
use proton_meet_chat::{ChatComposeRequest, MessageId, ReplyTarget};
pub use proton_meet_core::errors::core::MeetCoreError;
use proton_meet_core::{
    app::App,
    app_state::UserState,
    domain::user::models::{
        access_token::AccessToken,
        meet_link::{parse_meeting_link, MeetLink},
        meeting_link_name::MeetingLinkName,
        meeting_password::MeetingPassword,
        UnleashResponse,
    },
};
use tokio::sync::Mutex;

pub use proton_meet_core::app::DecryptedMessageInfo;

pub type MlsGroupUpdateCallback = dyn Fn(String) -> DartFnFuture<()> + Send + Sync;

pub type LiveKitAdminChangeCallback = dyn Fn(String, String, u32) -> DartFnFuture<()> + Send + Sync;

pub type MlsSyncStateUpdateCallback =
    dyn Fn(MlsSyncState, Option<RejoinReason>) -> DartFnFuture<()> + Send + Sync;
pub type JoinDecisionCallback = dyn Fn(String, bool) -> DartFnFuture<()> + Send + Sync;
pub type JoinRequestCallback =
    dyn Fn(JoinRequestChange, String, String, u64) -> DartFnFuture<()> + Send + Sync;

lazy_static::lazy_static! {
    static ref MEET_MLS_GROUP_UPDATE_DART_CALLBACK: Arc<Mutex<Option<Arc<MlsGroupUpdateCallback>>>> =
        Arc::new(Mutex::new(None));
    static ref MEET_LIVEKIT_ADMIN_CHANGE_DART_CALLBACK: Arc<Mutex<Option<Arc<LiveKitAdminChangeCallback>>>> =
        Arc::new(Mutex::new(None));
    static ref MEET_MLS_SYNC_STATE_UPDATE_DART_CALLBACK: Arc<Mutex<Option<Arc<MlsSyncStateUpdateCallback>>>> =
        Arc::new(Mutex::new(None));
    static ref MEET_JOIN_DECISION_DART_CALLBACK: Arc<Mutex<Option<Arc<JoinDecisionCallback>>>> =
        Arc::new(Mutex::new(None));
    static ref MEET_JOIN_REQUEST_DART_CALLBACK: Arc<Mutex<Option<Arc<JoinRequestCallback>>>> =
        Arc::new(Mutex::new(None));
}

// Dedicated runtime for app core operations to offload main thread
// This runtime runs on background threads, preventing blocking of the Dart main thread
static APP_CORE_RUNTIME: OnceLock<Option<Handle>> = OnceLock::new();

fn get_app_core_runtime_handle() -> Option<Handle> {
    APP_CORE_RUNTIME
        .get_or_init(|| {
            // Try to create a dedicated runtime on background threads to offload main thread
            // Using Handle::try_current() would use the main thread's runtime, which defeats
            // the purpose of offloading work. We need a separate runtime on background threads.
            if let Ok(runtime) = Runtime::new() {
                let handle = runtime.handle().clone();

                // Spawn the runtime on a background thread to keep it alive
                // This ensures all work runs on background threads, not the main thread
                if std::thread::Builder::new()
                    .name("app-core-runtime".to_string())
                    .spawn(move || {
                        runtime.block_on(async {
                            // Keep runtime alive indefinitely
                            std::future::pending::<()>().await;
                        });
                    })
                    .is_ok()
                {
                    return Some(handle);
                }
            }

            // If we can't create a dedicated runtime, return None
            // We'll use tokio::spawn directly in functions instead
            None
        })
        .clone()
}

#[frb(opaque)]
pub struct AppCore {
    pub(crate) inner: Arc<App>,
    pub(crate) auth_store: Arc<ProtonMeetAuthStore>,
    user_config: UserConfig,
    //  event bus
    event_tx: broadcast::Sender<AppEvent>,
    // Optional dedicated runtime handle for offloading heavy operations from main thread
    // If None, we'll use tokio::spawn directly (which still spawns tasks, just on current runtime)
    runtime_handle: Option<Handle>,
}

impl AppCore {
    /// Helper to spawn a future on background runtime or using tokio::spawn
    /// This unifies the spawning logic so we don't need if/else checks everywhere
    fn spawn_on_background<F, T>(&self, future: F) -> tokio::task::JoinHandle<T>
    where
        F: std::future::Future<Output = T> + Send + 'static,
        T: Send + 'static,
    {
        if let Some(handle) = &self.runtime_handle {
            handle.spawn(future)
        } else {
            tokio::spawn(future)
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn new(
        env: String,
        app_version: String,
        user_agent: String,
        db_path: String,
        auth_store: &ProtonMeetAuthStore,
        ws_host: String,
        http_host: String,
        user_state: Option<UserState>,
        user_key_provider: &FrbUserKeyProvider,
    ) -> Result<Self, BridgeError> {
        let app = App::new(
            env,
            app_version,
            user_agent,
            db_path,
            auth_store.inner.clone(),
            ws_host,
            http_host,
            user_state,
            Arc::new(user_key_provider.inner.clone()),
        )
        .await?;
        let user_config = UserConfig::load();
        let (event_tx, _rx) = broadcast::channel::<AppEvent>(256);

        // Get handle to dedicated background runtime for spawning heavy operations
        // This ensures app core work runs on background threads, offloading main thread
        // If None, we'll use tokio::spawn directly in functions
        let runtime_handle = get_app_core_runtime_handle();

        Ok(Self {
            inner: Arc::new(app),
            auth_store: Arc::new(auth_store.clone()),
            user_config,
            event_tx,
            runtime_handle,
        })
    }

    pub async fn update_auth(
        &mut self,
        user_id: String,
        uid: String,
        access: String,
        refresh: String,
        scopes: Vec<String>,
    ) -> Result<(), BridgeError> {
        let auth = Auth::internal(user_id, uid, Tokens::access(access, refresh, scopes));
        let mut store = self.auth_store.inner.clone();
        store.set_session_auth(auth);
        self.auth_store = Arc::new(ProtonMeetAuthStore {
            inner: store.clone(),
        });
        self.inner.sync_auth_store(store).await?;
        Ok(())
    }

    /// Rebuild the muon session from the current auth store (e.g. after `ProtonMeetAuthStore::set_auth`).
    pub async fn sync_auth_store(&self) -> Result<(), BridgeError> {
        self.inner
            .sync_auth_store(self.auth_store.inner.clone())
            .await?;
        Ok(())
    }

    pub async fn fetch_toggles(&self) -> Result<UnleashResponse, BridgeError> {
        let response = self.inner.fetch_toggles().await?;
        Ok(response)
    }

    /// Lightweight server reachability check (e.g. when logged out). Surfaces API errors such as force upgrade.
    pub async fn ping(&self) -> Result<u64, BridgeError> {
        let rtt_ms = self.inner.ping().await?;
        Ok(rtt_ms)
    }

    // 🔌 Flutter subscribes by giving us a StreamSink; we push events into it.
    // This returns immediately and we keep pushing on a background task.
    #[frb(sync)]
    pub fn subscribe_events(&self, sink: StreamSink<AppEvent>) -> Result<(), BridgeError> {
        let mut rx = self.event_tx.subscribe();
        tokio::spawn(async move {
            while let Ok(ev) = rx.recv().await {
                // ignore send failures (listener disposed)
                let _ = sink.add(ev.into());
            }
        });
        Ok(())
    }

    // fn emit(&self, ev: AppEvent) {
    //     let _ = self.event_tx.send(ev);
    // }

    /// Helper function to compute mailbox password from user data and password
    #[frb(ignore)]
    async fn compute_mailbox_password(
        user_data: &UserData,
        password: &str,
    ) -> Result<String, BridgeError> {
        let user_key = user_data
            .user
            .keys
            .as_ref()
            .and_then(|keys| keys.first())
            .ok_or(LoginError::NoUserKeys)?;

        let key_id = user_key.id.clone();
        let encoded_salt = user_data
            .key_salts
            .iter()
            .find(|key_salt| key_salt.id == key_id)
            .ok_or(LoginError::NoKeySalt)?
            .key_salt
            .as_ref()
            .ok_or(LoginError::NoKeySalt)?;

        MeetCrypto::compute_key_password(password, encoded_salt)
            .await
            .map_err(|e| BridgeError::from(LoginError::SrpHashError(e)))
    }

    pub async fn login(
        &self,
        username: String,
        password: String,
    ) -> Result<ProtonUserSession, BridgeError> {
        let user_data = self.inner.login(username, password.clone()).await?;

        // Compute mailbox password
        let mailbox_password = Self::compute_mailbox_password(&user_data, &password).await?;

        // Get auth information from auth store
        let auth = self.auth_store.get_auth().await;
        ProtonUserSession::from_user_data_and_auth(Box::new(user_data), auth, mailbox_password)
    }

    pub async fn login_with_two_factor(
        &self,
        password: String,
        two_factor_code: String,
    ) -> Result<ProtonUserSession, BridgeError> {
        let user_data = self.inner.login_with_two_factor(two_factor_code).await?;

        // Compute mailbox password
        let mailbox_password = Self::compute_mailbox_password(&user_data, &password).await?;

        // Get auth information from auth store
        let auth = self.auth_store.get_auth().await;
        ProtonUserSession::from_user_data_and_auth(Box::new(user_data), auth, mailbox_password)
    }

    pub async fn get_user(&self, user_id: String) -> Result<ProtonUser, BridgeError> {
        let user = self.inner.get_user(user_id).await?;
        Ok(user)
    }

    pub async fn get_proton_telemetry_enabled(&self) -> Result<bool, BridgeError> {
        self.inner
            .get_proton_telemetry_enabled()
            .await
            .map_err(Into::into)
    }

    pub async fn fetch_user_state(
        &self,
        user_id: String,
        force_remote: bool,
    ) -> Result<UserState, BridgeError> {
        let user = self.inner.fetch_user_state(user_id, force_remote).await?;
        Ok(user)
    }

    pub async fn refresh_user_state_from_api(
        &self,
        user_id: String,
    ) -> Result<UserState, BridgeError> {
        let user = self.inner.refresh_user_state_from_api(user_id).await?;
        Ok(user)
    }

    pub async fn logout(&self, user_id: String) -> Result<(), BridgeError> {
        self.inner.logout(user_id).await?;
        Ok(())
    }

    pub fn get_user_config(&self) -> UserConfig {
        self.user_config.clone()
    }

    pub async fn get_participants(
        &self,
        meet_link_name: String,
    ) -> Result<Vec<MeetParticipant>, BridgeError> {
        let participants = self.inner.get_participants(meet_link_name).await?;
        Ok(participants)
    }

    pub async fn get_participants_count(&self, meet_link_name: String) -> Result<u32, BridgeError> {
        let count = self.inner.get_participants_count(meet_link_name).await?;
        Ok(count)
    }

    pub async fn lock_meeting(&self, meet_link_name: String) -> Result<(), BridgeError> {
        self.inner.lock_meeting(meet_link_name).await?;
        Ok(())
    }

    pub async fn unlock_meeting(&self, meet_link_name: String) -> Result<(), BridgeError> {
        self.inner.unlock_meeting(meet_link_name).await?;
        Ok(())
    }

    pub fn get_join_type(
        &self,
        is_new_join_type: bool,
        enable_join_type_switch: bool,
        current_participant_count: u32,
    ) -> JoinType {
        self.inner.get_join_type(
            is_new_join_type,
            enable_join_type_switch,
            current_participant_count,
        )
    }

    pub fn update_display_name(mut self, display_name: String) {
        self.user_config = self.user_config.update_display_name(display_name);
        self.user_config.save();
    }
    pub fn update_show_self_tile(&mut self, show_self_tile: bool) {
        self.user_config = self.user_config.update_show_self_tile(show_self_tile);
        self.user_config.save();
    }

    pub fn update_dark_mode(&mut self, dark_mode: bool) {
        self.user_config = self.user_config.update_dark_mode(dark_mode);
        self.user_config.save();
    }

    pub fn update_camera_resolution(&mut self, camera_resolution: VideoResolution) {
        self.user_config = self.user_config.update_camera_resolution(camera_resolution);
        self.user_config.save();
    }

    pub fn update_camera_max_bitrate(&mut self, camera_max_bitrate: VideoMaxBitrate) {
        self.user_config = self
            .user_config
            .update_camera_max_bitrate(camera_max_bitrate);
        self.user_config.save();
    }

    pub fn update_screensharing_resolution(&mut self, screensharing_resolution: VideoResolution) {
        self.user_config = self
            .user_config
            .update_screensharing_resolution(screensharing_resolution);
        self.user_config.save();
    }

    pub fn update_screensharing_max_bitrate(&mut self, screensharing_max_bitrate: VideoMaxBitrate) {
        self.user_config = self
            .user_config
            .update_screensharing_max_bitrate(screensharing_max_bitrate);
        self.user_config.save();
    }

    pub async fn set_livekit_active_uuids(&mut self, active_uuids: Vec<String>) {
        let _ = self.inner.set_livekit_active_uuids(active_uuids).await;
    }

    /// SRP-authenticate a meeting link and return decrypted metadata (name, limits).
    /// Caches the auth result for reuse when [`Self::join_meeting`] is called with
    /// `reuse_prejoin_auth: true`.
    pub async fn authenticate_meeting_link(
        &self,
        meet_link_name: String,
        meet_link_password: String,
        display_name: String,
    ) -> Result<FrbMeetInfo, BridgeError> {
        let inner_clone = self.inner.clone();
        let meet_info = self
            .spawn_on_background(async move {
                inner_clone
                    .authenticate_meeting_link(meet_link_name, meet_link_password, display_name)
                    .await
            })
            .await??;
        Ok(meet_info.into())
    }

    pub async fn clear_prejoin_srp_auth(&self) -> Result<(), BridgeError> {
        self.inner.clear_prejoin_srp_auth().await;
        Ok(())
    }

    /// Prepare MLS session from cached pre-join auth for waiting-room group-info polling.
    pub async fn prepare_mls_session_for_waiting_room(
        &self,
        meet_link_name: String,
        meet_link_password: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .prepare_mls_session_for_waiting_room(meet_link_name, meet_link_password)
            .await?;
        Ok(())
    }

    /// Whether MLS group info exists on the server (host has started the meeting).
    pub async fn has_mls_group_info(&self) -> Result<bool, BridgeError> {
        Ok(self.inner.has_mls_group_info().await?)
    }

    /// Submits an encrypted MLS join request to meet-server for waiting-room admission.
    ///
    /// Requires an active MLS session (see [`Self::prepare_mls_session_for_waiting_room`]).
    /// After a successful response, call [`Self::wait_for_waiting_room_welcome`] to wait for host admit.
    pub async fn create_join_request(
        &self,
        meet_link_name: String,
        meeting_session_key: String,
    ) -> Result<FrbSubmitJoinRequestResponse, BridgeError> {
        let response = self
            .inner
            .create_join_request(meet_link_name, meeting_session_key.into())
            .await?;
        Ok(response.into())
    }

    /// Waits up to 5 minutes for the host to admit via Welcome, then joins the MLS group.
    pub async fn wait_for_waiting_room_welcome(
        &self,
        meet_link_name: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .wait_for_waiting_room_welcome(meet_link_name)
            .await?;
        Ok(())
    }

    pub async fn get_meeting_display_name_session_key(&self) -> Result<String, BridgeError> {
        Ok(self.inner.get_meeting_display_name_session_key().await?)
    }

    pub async fn connect_websocket_for_waiting_room(&self) -> Result<(), BridgeError> {
        self.inner.connect_websocket_for_waiting_room().await?;
        Ok(())
    }

    pub async fn clear_waiting_room_join_request(&self) -> Result<(), BridgeError> {
        self.inner.clear_waiting_room_join_request().await;
        Ok(())
    }

    /// Cancels the guest's outstanding waiting-room join request (DELETE when submitted),
    /// resets local MLS guest admission state, and disconnects the MLS websocket.
    pub async fn cancel_waiting_room_join_request(
        &self,
        meet_link_name: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .cancel_waiting_room_join_request(meet_link_name)
            .await?;
        Ok(())
    }

    pub async fn set_join_decision_callback(
        &self,
        callback: impl Fn(String, bool) -> DartFnFuture<()> + Send + Sync + 'static,
    ) -> Result<(), BridgeError> {
        let callback_guard = {
            let mut guard = MEET_JOIN_DECISION_DART_CALLBACK.lock().await;
            *guard = Some(Arc::new(callback));
            MEET_JOIN_DECISION_DART_CALLBACK.clone()
        };

        self.inner
            .set_join_decision_handler(move |request_id, admitted| {
                let callback_lock = callback_guard.clone();
                Box::pin(async move {
                    let callback = {
                        let guard = callback_lock.lock().await;
                        guard.as_ref().cloned()
                    };
                    if let Some(callback) = callback {
                        flutter_rust_bridge::spawn(async move {
                            let _ = callback(request_id, admitted).await;
                        });
                    }
                })
            })
            .await;
        Ok(())
    }

    pub async fn clear_join_decision_callback(&self) -> Result<(), BridgeError> {
        let mut guard = MEET_JOIN_DECISION_DART_CALLBACK.lock().await;
        *guard = None;
        Ok(())
    }

    /// Registers a Dart callback fired when a waiting-room join request is added or removed.
    /// Args: `(change, request_id, participant_uid, expires_at)`.
    /// For removals, `expires_at` is 0. `request_id` is set when known (host reject);
    /// WS fanout may omit it — the UI ignores removals without `request_id`.
    pub async fn set_join_request_callback(
        &self,
        callback: impl Fn(JoinRequestChange, String, String, u64) -> DartFnFuture<()>
            + Send
            + Sync
            + 'static,
    ) -> Result<(), BridgeError> {
        let callback_guard = {
            let mut guard = MEET_JOIN_REQUEST_DART_CALLBACK.lock().await;
            *guard = Some(Arc::new(callback));
            MEET_JOIN_REQUEST_DART_CALLBACK.clone()
        };

        self.inner
            .set_join_request_handler(move |change, request_id, participant_uid, expires_at| {
                let callback_lock = callback_guard.clone();
                Box::pin(async move {
                    if let Some(callback) = callback_lock.lock().await.as_ref().cloned() {
                        flutter_rust_bridge::spawn(async move {
                            let _ = callback(change, request_id, participant_uid, expires_at).await;
                        });
                    }
                })
            })
            .await;
        Ok(())
    }

    pub async fn clear_join_request_callback(&self) -> Result<(), BridgeError> {
        {
            let mut guard = MEET_JOIN_REQUEST_DART_CALLBACK.lock().await;
            *guard = None;
        }
        self.inner.clear_join_request_handler().await;
        Ok(())
    }

    /// Rejects a waiting-room join request (host only).
    pub async fn reject_waiting_room_join_request(
        &self,
        meet_link_name: String,
        request_id: String,
        participant_uid: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .reject_waiting_room_join_request(meet_link_name, request_id, participant_uid)
            .await?;
        Ok(())
    }

    /// Admits a single waiting-room join request (host only).
    pub async fn admit_waiting_room_join_request(
        &self,
        meet_link_name: String,
        request_id: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .admit_waiting_room_join_request(meet_link_name, request_id)
            .await?;
        Ok(())
    }

    /// Admits all pending waiting-room join requests (host only).
    pub async fn admit_all_waiting_room_join_requests(
        &self,
        meet_link_name: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .admit_all_waiting_room_join_requests(meet_link_name, None)
            .await?;
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn join_meeting(
        &mut self,
        meet_link_name: String,
        meet_link_password: String,
        display_name: String,
        session_id: Option<String>,
        is_meet_new_join_type: bool,
        is_meet_switch_join_type: bool,
        is_meet_new_switch_join_type: bool,
        reuse_token: bool,
        reuse_prejoin_auth: bool,
        is_waiting_room: bool,
    ) -> Result<FrbMeetInfo, BridgeError> {
        if reuse_token {
            return self
                .join_meeting_reuse_token(
                    meet_link_name,
                    meet_link_password,
                    session_id,
                    is_meet_new_join_type,
                    is_meet_switch_join_type,
                )
                .await;
        }

        let mut meet_info = if reuse_prejoin_auth {
            if let Some(cached) = self
                .inner
                .try_take_prejoin_srp_auth(&meet_link_name, &display_name)
                .await
            {
                tracing::info!(
                    "join_meeting: reusing pre-join SRP auth for {}",
                    meet_link_name
                );
                cached
            } else {
                self.spawn_authenticate_meeting_link(
                    meet_link_name.clone(),
                    meet_link_password.clone(),
                    display_name.clone(),
                )
                .await?
            }
        } else {
            self.spawn_authenticate_meeting_link(
                meet_link_name.clone(),
                meet_link_password.clone(),
                display_name.clone(),
            )
            .await?
        };

        if is_meet_new_switch_join_type {
            self.inner
                .join_meeting(
                    AccessToken::from(meet_info.access_token.clone()),
                    MeetingLinkName::from(meet_link_name.clone()),
                    MeetingPassword::from(meet_link_password.clone()),
                    session_id,
                    is_meet_new_join_type,
                    is_waiting_room,
                )
                .await?;
            tracing::info!("Successfully joined meeting with GroupInfo-based join switching");
            return Ok(meet_info.into());
        }

        let participant_count = self
            .inner
            .get_participants_count(meet_link_name.clone())
            .await?;
        meet_info.participants_count = participant_count;

        let join_type = self.inner.get_join_type(
            is_meet_new_join_type,
            is_meet_switch_join_type,
            participant_count,
        );

        let with_proposal = join_type == JoinType::ExternalProposal;
        tracing::info!(
            "join_meeting: with_proposal={}, participant_count={}, join_type={:?}",
            with_proposal,
            participant_count,
            join_type
        );

        let mut is_fallback = false;
        if with_proposal {
            match self
                .inner
                .join_meeting_with_access_token_with_proposal(
                    meet_info.access_token.clone(),
                    meet_link_name.clone(),
                    meet_link_password.clone(),
                    session_id.clone(),
                )
                .await
            {
                Ok(_) => {
                    tracing::info!("Successfully joined meeting with proposal");
                    return Ok(meet_info.into());
                }
                Err(e) => {
                    tracing::warn!(
                        "Failed to join meeting with proposal: {:?}, falling back to commit method",
                        e
                    );
                    is_fallback = true;
                }
            }
        }

        self.inner
            .join_meeting_with_access_token(
                meet_info.access_token.clone(),
                meet_link_name.clone(),
                meet_link_password.clone(),
                session_id,
            )
            .await?;
        tracing::info!(
            "Successfully joined meeting with commit (is_fallback={})",
            is_fallback
        );

        Ok(meet_info.into())
    }

    async fn spawn_authenticate_meeting_link(
        &self,
        meet_link_name: String,
        meet_link_password: String,
        display_name: String,
    ) -> Result<proton_meet_core::domain::user::models::meet_link_info::MeetInfo, BridgeError> {
        let inner_clone = self.inner.clone();
        Ok(self
            .spawn_on_background(async move {
                inner_clone
                    .authenticate_meeting_link(meet_link_name, meet_link_password, display_name)
                    .await
            })
            .await??)
    }

    #[allow(clippy::too_many_arguments)]
    async fn join_meeting_reuse_token(
        &mut self,
        meet_link_name: String,
        meet_link_password: String,
        session_id: Option<String>,
        is_meet_new_join_type: bool,
        is_meet_switch_join_type: bool,
    ) -> Result<FrbMeetInfo, BridgeError> {
        let participant_count = self
            .inner
            .get_participants_count(meet_link_name.clone())
            .await?;

        let join_type = self.inner.get_join_type(
            is_meet_new_join_type,
            is_meet_switch_join_type,
            participant_count,
        );

        let with_proposal = join_type == JoinType::ExternalProposal;
        tracing::info!(
            "join_meeting (reuse_token): with_proposal={}, participant_count={}, join_type={:?}",
            with_proposal,
            participant_count,
            join_type
        );

        let access_token = self.inner.get_active_livekit_access_token().await?;
        let websocket_url = self.inner.get_active_livekit_websocket_url().await?;
        if self.inner.is_mls_group_joined().await {
            tracing::info!("join_meeting (reuse_token): MLS already joined, skipping MLS join");
            let meeting_info: FrbMeetingInfo =
                self.inner.get_meeting_info(&meet_link_name).await?.into();
            return Ok(FrbMeetInfo {
                meet_name: meeting_info.meeting_name,
                meet_link_name,
                access_token,
                websocket_url,
                participants_count: participant_count,
                is_locked: meeting_info.locked != 0,
                has_waiting_room: meeting_info.waiting_room == 1,
                max_duration: meeting_info.max_duration,
                max_participants: meeting_info.max_participants,
                expiration_time: meeting_info.expiration_time,
            });
        }

        let mut is_fallback = false;
        if with_proposal {
            match self
                .inner
                .join_meeting_with_access_token_with_proposal(
                    access_token.clone(),
                    meet_link_name.clone(),
                    meet_link_password.clone(),
                    session_id.clone(),
                )
                .await
            {
                Ok(_) => {
                    tracing::info!("Successfully joined meeting with proposal (reuse_token)");
                    let meeting_info: FrbMeetingInfo =
                        self.inner.get_meeting_info(&meet_link_name).await?.into();
                    return Ok(FrbMeetInfo {
                        meet_name: meeting_info.meeting_name,
                        meet_link_name,
                        access_token,
                        websocket_url,
                        participants_count: participant_count,
                        is_locked: meeting_info.locked != 0,
                        has_waiting_room: meeting_info.waiting_room == 1,
                        max_duration: meeting_info.max_duration,
                        max_participants: meeting_info.max_participants,
                        expiration_time: meeting_info.expiration_time,
                    });
                }
                Err(e) => {
                    tracing::warn!(
                        "Failed to join meeting with proposal (reuse_token): {:?}, falling back to commit method",
                        e
                    );
                    is_fallback = true;
                }
            }
        }
        self.inner.disconnect_wss_intentional().await?;

        self.inner
            .join_meeting_with_access_token(
                access_token.clone(),
                meet_link_name.clone(),
                meet_link_password.clone(),
                session_id,
            )
            .await?;
        tracing::info!(
            "Successfully joined meeting with commit (reuse_token, is_fallback={})",
            is_fallback
        );

        let meeting_info: FrbMeetingInfo =
            self.inner.get_meeting_info(&meet_link_name).await?.into();
        Ok(FrbMeetInfo {
            meet_name: meeting_info.meeting_name,
            meet_link_name,
            access_token,
            websocket_url,
            participants_count: participant_count,
            is_locked: meeting_info.locked != 0,
            has_waiting_room: meeting_info.waiting_room == 1,
            max_duration: meeting_info.max_duration,
            max_participants: meeting_info.max_participants,
            expiration_time: meeting_info.expiration_time,
        })
    }

    pub async fn join_meeting_with_access_token(
        &self,
        access_token: String,
        meet_link_name: String,
        meeting_password: String,
        session_id: Option<String>,
    ) -> Result<(), BridgeError> {
        self.inner
            .join_meeting_with_access_token(
                access_token,
                meet_link_name,
                meeting_password,
                session_id,
            )
            .await?;
        Ok(())
    }

    pub async fn join_meeting_with_access_token_with_proposal(
        &self,
        access_token: String,
        meet_link_name: String,
        meeting_password: String,
        session_id: Option<String>,
    ) -> Result<(), BridgeError> {
        self.inner
            .join_meeting_with_access_token_with_proposal(
                access_token,
                meet_link_name,
                meeting_password,
                session_id,
            )
            .await?;
        Ok(())
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
        waiting_room: bool,
    ) -> Result<FrbUpcomingMeeting, BridgeError> {
        let meeting = self
            .inner
            .create_meeting(
                meeting_name,
                has_session,
                meeting_type,
                custom_password,
                start_time,
                end_time,
                time_zone,
                r_rule,
                waiting_room,
            )
            .await?;
        Ok(meeting.into())
    }

    pub async fn edit_meeting_name(
        &self,
        meeting_id: String,
        new_meeting_name: String,
        meeting_password: String,
    ) -> Result<FrbUpcomingMeeting, BridgeError> {
        let meeting = self
            .inner
            .edit_meeting_name(meeting_id, new_meeting_name, meeting_password)
            .await?;
        Ok(meeting.into())
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
    ) -> Result<FrbUpcomingMeeting, BridgeError> {
        let meeting = self
            .inner
            .update_meeting_schedule(
                meeting_id,
                meeting_name,
                meeting_password,
                start_time,
                end_time,
                time_zone,
                r_rule,
            )
            .await?;
        Ok(meeting.into())
    }

    pub async fn get_upcoming_meetings(&self) -> Result<Vec<FrbUpcomingMeeting>, BridgeError> {
        // Spawn heavy meeting list fetch on background runtime to offload main thread
        // This involves HTTP requests that can block
        let meetings = {
            let inner_clone = self.inner.clone();
            self.spawn_on_background(async move { inner_clone.get_upcoming_meetings().await })
                .await??
        };

        Ok(meetings
            .into_iter()
            .map(|m| m.into())
            .collect::<Vec<FrbUpcomingMeeting>>())
    }

    pub async fn create_personal_meeting(
        &self,
        meeting_name: String,
        custom_password: Option<String>,
        is_rotate: bool,
        waiting_room: bool,
    ) -> Result<FrbUpcomingMeeting, BridgeError> {
        let meeting = self
            .inner
            .create_personal_meeting(meeting_name, custom_password, is_rotate, waiting_room)
            .await?;
        Ok(meeting.into())
    }

    pub async fn leave_room(&self) -> Result<(), BridgeError> {
        self.inner.leave_meeting().await?;
        Ok(())
    }

    pub async fn end_meeting(&self) -> Result<(), BridgeError> {
        self.inner.end_meeting().await?;
        Ok(())
    }

    pub async fn send_meeting_feedback(
        &self,
        meeting_link_name: String,
        score: u8,
        feedback_parts: Vec<String>,
    ) -> Result<(), BridgeError> {
        self.inner
            .send_meeting_feedback(&meeting_link_name, score, feedback_parts)
            .await?;
        Ok(())
    }

    pub async fn get_meeting_info(
        &self,
        meeting_link_name: String,
    ) -> Result<FrbMeetingInfo, BridgeError> {
        let meeting_info = self.inner.get_meeting_info(&meeting_link_name).await?;
        Ok(meeting_info.into())
    }

    pub async fn delete_meeting(&self, meeting_name: String) -> Result<(), BridgeError> {
        self.inner.delete_meeting(meeting_name).await?;
        Ok(())
    }

    /// Get the latest event ID from the server
    pub async fn get_latest_event_id(&self) -> Result<String, BridgeError> {
        let event_id = self.inner.get_latest_event_id().await?;
        Ok(event_id)
    }

    /// Get events starting from a given event ID
    /// Returns GetEventsResponse containing meeting events, flags, and new event ID
    pub async fn get_events(&self, event_id: String) -> Result<FrbGetEventsResponse, BridgeError> {
        let response = self.inner.get_events(event_id).await?;
        Ok(response.into())
    }
    pub async fn get_core_events(
        &self,
        event_id: String,
    ) -> Result<FrbGetEventsResponse, BridgeError> {
        let response = self.inner.get_core_events(event_id).await?;
        Ok(response.into())
    }

    pub async fn update_livekit_access_token(
        &self,
        access_token: String,
    ) -> Result<(), BridgeError> {
        self.inner.update_livekit_access_token(access_token).await?;
        Ok(())
    }

    pub async fn update_livekit_access_token_and_websocket_url(
        &self,
        access_token: String,
        websocket_url: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .update_livekit_access_token_and_websocket_url(access_token, websocket_url)
            .await?;
        Ok(())
    }

    pub async fn update_participant_track_settings(
        &self,
        participant_uuid: String,
        audio: Option<u8>,
        video: Option<u8>,
    ) -> Result<FrbParticipantTrackSettings, MeetCoreError> {
        let participant_track_settings = self
            .inner
            .update_participant_track_settings(participant_uuid, audio, video)
            .await?;
        Ok(participant_track_settings.into())
    }

    pub async fn update_waiting_room_setting(
        &self,
        meet_link_name: String,
        enable: bool,
    ) -> Result<(), BridgeError> {
        self.inner
            .update_waiting_room_setting(meet_link_name, enable, None)
            .await?;
        Ok(())
    }

    pub async fn remove_participant(&self, participant_uuid: String) -> Result<(), BridgeError> {
        self.inner.remove_participant(participant_uuid).await?;
        Ok(())
    }

    pub async fn get_group_key(&self) -> Result<(String, u64), BridgeError> {
        // Spawn heavy group key fetch on background runtime to offload main thread
        // This involves HTTP requests and MLS operations that can block
        let (group_key, epoch) = {
            let inner_clone = self.inner.clone();
            self.spawn_on_background(async move { inner_clone.get_group_key().await })
                .await??
        };

        Ok((group_key, epoch))
    }

    pub async fn get_group_len(&self) -> Result<u32, BridgeError> {
        let len = {
            let inner_clone = self.inner.clone();
            self.spawn_on_background(async move { inner_clone.get_group_len().await })
                .await??
        };

        Ok(len)
    }

    pub async fn get_group_display_code(&self) -> Result<String, BridgeError> {
        let group_display_code = self.inner.get_group_display_code().await?;
        Ok(group_display_code)
    }

    pub async fn get_ws_state(&self) -> Result<ConnectionState, BridgeError> {
        let ws_state = self.inner.get_ws_state().await?;
        Ok(ws_state)
    }

    pub async fn is_websocket_has_reconnected(&self) -> Result<bool, BridgeError> {
        let has_reconnected = self.inner.is_websocket_has_reconnected().await?;
        Ok(has_reconnected)
    }

    /// Set WebSocket ping interval in seconds (None to use default)
    pub async fn set_websocket_ping_interval(
        &self,
        seconds: Option<u64>,
    ) -> Result<(), BridgeError> {
        self.inner.set_websocket_ping_interval(seconds).await?;
        Ok(())
    }

    /// Set WebSocket max ping failures (None to use default)
    /// This is particularly useful for Safari when it goes to background, allowing more tolerance
    pub async fn set_websocket_max_ping_failures(
        &self,
        failures: Option<u32>,
    ) -> Result<(), BridgeError> {
        self.inner.set_websocket_max_ping_failures(failures).await?;
        Ok(())
    }

    /// Set WebSocket pong timeout in seconds (None to use default)
    pub async fn set_websocket_pong_timeout(
        &self,
        seconds: Option<u64>,
    ) -> Result<(), BridgeError> {
        self.inner.set_websocket_pong_timeout(seconds).await?;
        Ok(())
    }

    pub async fn is_mls_up_to_date(&self) -> Result<bool, BridgeError> {
        let is_up_to_date = self.inner.is_mls_up_to_date().await?;
        Ok(is_up_to_date)
    }

    pub async fn set_mls_group_update_callback(
        &self,
        callback: impl Fn(String) -> DartFnFuture<()> + Send + Sync + 'static,
    ) -> Result<(), BridgeError> {
        let mut guard = MEET_MLS_GROUP_UPDATE_DART_CALLBACK.lock().await;
        *guard = Some(Arc::new(callback));
        let callback_guard = MEET_MLS_GROUP_UPDATE_DART_CALLBACK.clone();

        let event_tx = self.event_tx.clone(); // <-- owned, 'static (Arc<...>)
        self.inner
            .set_mls_group_update_handler(move |room_id, _reason| {
                // let app_arc = app_arc.clone();
                // let self_weak = self_weak.clone();
                let event_tx = event_tx.clone(); // <-- owned, 'static (Arc<...>)
                tracing::info!("set_mls_group_update_callback group update callback");
                let callback_lock = callback_guard.clone();
                Box::pin(async move {
                    // Emit via sender (no &self needed)
                    let _ = event_tx.send(AppEvent::MlsGroupUpdated {
                        room_id: room_id.clone(),
                        key: "group_key".to_string(),
                        epoch: 0,
                    });

                    if let Some(callback) = callback_lock.lock().await.as_ref().cloned() {
                        flutter_rust_bridge::spawn(async move {
                            let _ = callback(room_id).await;
                        });
                    }
                })
            })
            .await;
        Ok(())
    }

    pub async fn clear_mls_group_update_callback(&self) -> Result<(), BridgeError> {
        let mut guard = MEET_MLS_GROUP_UPDATE_DART_CALLBACK.lock().await;
        *guard = None;
        Ok(())
    }

    pub async fn set_mls_sync_state_update_callback(
        &self,
        callback: impl Fn(MlsSyncState, Option<RejoinReason>) -> DartFnFuture<()>
            + Send
            + Sync
            + 'static,
    ) -> Result<(), BridgeError> {
        let mut guard = MEET_MLS_SYNC_STATE_UPDATE_DART_CALLBACK.lock().await;
        *guard = Some(Arc::new(callback));
        let callback_guard = MEET_MLS_SYNC_STATE_UPDATE_DART_CALLBACK.clone();

        let event_tx = self.event_tx.clone();
        self.inner
            .set_mls_sync_state_update_handler(move |state, reason| {
                let event_tx = event_tx.clone();
                tracing::info!("set_mls_sync_state_update_callback sync state update callback");
                let callback_lock = callback_guard.clone();
                Box::pin(async move {
                    // Emit via sender (no &self needed)
                    let _ = event_tx.send(AppEvent::MlsSyncStateChanged {
                        state: state.clone(),
                        reason,
                    });

                    if let Some(callback) = callback_lock.lock().await.as_ref().cloned() {
                        flutter_rust_bridge::spawn(async move {
                            let _ = callback(state, reason).await;
                        });
                    }
                })
            })
            .await;
        Ok(())
    }

    pub async fn clear_mls_sync_state_update_callback(&self) -> Result<(), BridgeError> {
        let mut guard = MEET_MLS_SYNC_STATE_UPDATE_DART_CALLBACK.lock().await;
        *guard = None;
        Ok(())
    }

    pub async fn set_livekit_admin_change_callback(
        &self,
        callback: impl Fn(String, String, u32) -> DartFnFuture<()> + Send + Sync + 'static,
    ) -> Result<(), BridgeError> {
        let mut guard = MEET_LIVEKIT_ADMIN_CHANGE_DART_CALLBACK.lock().await;
        *guard = Some(Arc::new(callback));
        let callback_guard = MEET_LIVEKIT_ADMIN_CHANGE_DART_CALLBACK.clone();
        self.inner
            .set_livekit_admin_change_handler(move |room_id, participant_uid, participant_type| {
                tracing::info!("set_livekit_admin_change_callback admin change callback");
                let callback_lock = callback_guard.clone();
                Box::pin(async move {
                    if let Some(callback) = callback_lock.lock().await.as_ref().cloned() {
                        flutter_rust_bridge::spawn(async move {
                            let _ = callback(room_id, participant_uid, participant_type).await;
                        });
                    }
                })
            })
            .await;
        Ok(())
    }

    pub async fn clear_livekit_admin_change_callback(&self) -> Result<(), BridgeError> {
        let mut guard = MEET_LIVEKIT_ADMIN_CHANGE_DART_CALLBACK.lock().await;
        *guard = None;
        Ok(())
    }

    pub async fn parse_meeting_link(link: String) -> Result<Option<MeetLink>, BridgeError> {
        Ok(parse_meeting_link(link).await?)
    }

    pub async fn encrypt_message(&self, message: String) -> Result<Vec<u8>, BridgeError> {
        Ok(self.inner.encrypt_message(&message).await?)
    }

    pub async fn decrypt_message(&self, data: Vec<u8>) -> Result<(String, String), BridgeError> {
        let result = self.inner.decrypt_message(data).await?;
        Ok((result.message, result.sender_participant_id))
    }

    pub async fn parse_chat_message(
        &self,
        chat_message: String,
    ) -> Result<MeetChatMessage, BridgeError> {
        let message = MeetChatMessage::from_json(&chat_message)?;
        let (decrypted_message, _) = self
            .decrypt_message(message.message.as_bytes().to_vec())
            .await?;
        Ok(MeetChatMessage {
            id: message.id,
            timestamp: message.timestamp,
            identity: message.identity,
            name: message.name,
            seen: message.seen,
            message: decrypted_message.clone(),
        })
    }

    /// Compose a MimiV1 chat message (root message or thread reply).
    ///
    /// `reply_to_id` is the id of the message being replied to (usually the
    /// thread root); `reply_topic_id` is the thread root id. Both must be hex
    /// message ids. Returns the encrypted `payload` to publish plus a
    /// `local_echo` for optimistic UI.
    pub async fn compose_chat_message(
        &self,
        text: String,
        reply_to_id: Option<String>,
        reply_topic_id: Option<String>,
    ) -> Result<FrbChatComposeResult, BridgeError> {
        let reply_to = match reply_to_id {
            None => None,
            Some(id) => Some(ReplyTarget {
                message_id: MessageId::from_hex(&id).map_err(MeetCoreError::from)?,
                topic_id: reply_topic_id
                    .map(|t| MessageId::from_hex(&t).map_err(MeetCoreError::from))
                    .transpose()?,
            }),
        };
        Ok(self
            .inner
            .compose_chat(ChatComposeRequest::Message { text, reply_to })
            .await?
            .into())
    }

    /// Compose a MimiV1 emoji reaction on `target_id` (a message id).
    pub async fn compose_chat_reaction(
        &self,
        target_id: String,
        emoji: String,
    ) -> Result<FrbChatComposeResult, BridgeError> {
        let target = MessageId::from_hex(&target_id).map_err(MeetCoreError::from)?;
        Ok(self
            .inner
            .compose_chat(ChatComposeRequest::React { target, emoji })
            .await?
            .into())
    }

    /// Compose a MimiV1 unreact event removing a previous reaction.
    ///
    /// `replaces_id` is the id of the original reaction event to withdraw.
    pub async fn compose_chat_unreact(
        &self,
        target_id: String,
        replaces_id: String,
    ) -> Result<FrbChatComposeResult, BridgeError> {
        let target = MessageId::from_hex(&target_id).map_err(MeetCoreError::from)?;
        let replaces = MessageId::from_hex(&replaces_id).map_err(MeetCoreError::from)?;
        Ok(self
            .inner
            .compose_chat(ChatComposeRequest::Unreact { target, replaces })
            .await?
            .into())
    }

    /// Decode an incoming chat data-channel payload into a structured event.
    pub async fn decode_chat(
        &self,
        data: Vec<u8>,
    ) -> Result<crate::proton_meet::models::chat_event::FrbChatIncomingEvent, BridgeError> {
        Ok(self.inner.decode_chat(data).await?.into())
    }

    /// Manually trigger WebSocket reconnection.
    /// Call this when network connectivity changes (e.g., WiFi → cellular, airplane mode off).
    pub async fn trigger_websocket_reconnect(&self) -> Result<(), BridgeError> {
        self.inner.trigger_websocket_reconnect().await?;
        Ok(())
    }

    /// Fork selector for creating child sessions (e.g., for account deletion)
    /// Returns a selector string that can be used to create a fork session
    /// Client must be authenticated first
    pub async fn fork_selector(&self, client_child: String) -> Result<String, BridgeError> {
        let selector = self
            .inner
            .fork_selector(&client_child)
            .await
            .map_err(|e| BridgeError::Fork(e.to_string()))?;
        Ok(selector)
    }

    // pub async fn serialize_chat_message(
    //     &self,
    //     message: MeetChatMessage,
    // ) -> Result<String, BridgeError> {
    //     let message = message.to_json().await?;
    //     Ok(message)
    // }

    /// Log metrics when room join is successful, this method must be called right after the room is showing to user on client side
    pub async fn log_joined_room(
        &self,
        is_vp9_decode_supported: Option<bool>,
        is_vp9_encode_supported: Option<bool>,
    ) -> Result<(), BridgeError> {
        self.inner
            .log_joined_room(is_vp9_decode_supported, is_vp9_encode_supported)
            .await?;
        Ok(())
    }

    /// Log metrics when room join fails, this method must be called right after the room join fails on client side
    pub async fn log_joined_room_failed(
        &self,
        error_code: Option<String>,
    ) -> Result<(), BridgeError> {
        self.inner.log_joined_room_failed(error_code).await?;
        Ok(())
    }

    /// Log metrics when connection is lost
    pub async fn log_connection_lost(&self) -> Result<(), BridgeError> {
        self.inner.log_connection_lost().await?;
        Ok(())
    }

    /// Log metrics when connection is lost
    pub async fn log_user_epoch_health(
        &self,
        current_epoch: u32,
        epoch_display_code: String,
    ) -> Result<(), BridgeError> {
        self.inner
            .log_user_epoch_health(current_epoch, epoch_display_code)
            .await?;
        Ok(())
    }

    /// Log user rejoin metrics, parameters will be passed from client side
    pub async fn log_user_rejoin(
        &self,
        rejoin_time_ms: u64,
        incremental_count: u32,
        reason: RejoinReason,
        success: bool,
    ) -> Result<(), BridgeError> {
        self.inner
            .log_user_rejoin(rejoin_time_ms, incremental_count, reason, success)
            .await?;
        Ok(())
    }

    pub async fn log_start_to_join_room(&self) -> Result<(), BridgeError> {
        self.inner.log_start_to_join_room().await?;
        Ok(())
    }

    pub async fn try_log_designated_committer(&self, epoch: u32) -> Result<(), BridgeError> {
        self.inner.try_log_designated_committer(epoch).await?;
        Ok(())
    }

    pub async fn export_schedule_meeting_to_ics(
        &self,
        meeting: ScheduleMeetingRequest,
    ) -> Result<String, BridgeError> {
        let start = chrono::DateTime::<chrono::Utc>::from_timestamp(meeting.start_timestamp, 0)
            .ok_or_else(|| BridgeError::ParseError("Invalid start timestamp".to_string()))?;
        let mut end = chrono::DateTime::<chrono::Utc>::from_timestamp(meeting.end_timestamp, 0)
            .ok_or_else(|| BridgeError::ParseError("Invalid end timestamp".to_string()))?;
        if end <= start {
            let duration_minutes = meeting.duration_minutes.max(1);
            end = start + chrono::Duration::minutes(duration_minutes);
        }
        let recurrence = meeting.recurrence.map(|frequency| RecurrenceRule {
            frequency,
            interval: 1,
            count: None,
            until: None,
        });
        let uid = format!(
            "proton-meet-{}-{}",
            meeting.start_timestamp, meeting.end_timestamp
        );
        let event = IcsEvent {
            summary: meeting.title,
            description: meeting.description,
            start,
            end,
            location: meeting.location,
            recurrence,
            uid,
            time_zone: meeting.time_zone,
            duration_minutes: Some(meeting.duration_minutes),
        };
        let ics = event.to_ics();
        Ok(ics)
    }
}
