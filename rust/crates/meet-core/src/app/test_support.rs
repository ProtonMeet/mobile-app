//! Shared fixtures for `app/` unit tests. Keeps mocks out of production modules.

use std::{collections::HashMap, future::ready, str::FromStr, sync::Arc};

use mls_trait::MlsClientConfig;
use muon::auth::Auth;
use proton_meet_common::models::{ProtonUser, ProtonUserKey};
use proton_meet_mls::MlsStore;
use tokio::sync::{Mutex, RwLock};

use crate::app::App;
use crate::app_state::{AppState, UserState};
use crate::domain::room::RoomService;
use crate::domain::user::models::meeting::{MeetingType, UpcomingMeeting};
use crate::domain::user::models::{meet_link_info::MeetInfo, Address, UserTokenInfo};
use crate::domain::user::ports::{
    http_client::MockHttpClient, meeting_api::MockMeetingApi, user_api::MockUserApi,
    ConnectionState, MockUserRepository, MockWebSocketClient, UserService,
};
use crate::infra::{
    crypto_client::MeetCryptoClient,
    http_client::{ApiConfig, ProtonHttpClient},
    muon::AuthStore,
    ports::user_key_provider::{MockUserKeyProvider, UserKeyProvider},
};
use crate::service::service::create_mock_http_client_for_mls;
use crate::service::service::Service;

pub fn test_user_key(id: &str, primary: u32, active: u32) -> ProtonUserKey {
    ProtonUserKey {
        id: id.to_string(),
        version: 0,
        private_key: String::new(),
        recovery_secret: None,
        recovery_secret_signature: None,
        token: None,
        fingerprint: String::new(),
        signature: None,
        primary,
        active,
    }
}

pub fn test_address(id: &str, email: &str) -> Address {
    Address {
        id: id.to_string(),
        email: email.to_string(),
        keys: vec![],
    }
}

pub fn test_user_state(user_id: &str, with_keys: bool, with_address: bool) -> UserState {
    UserState::new(
        ProtonUser {
            id: user_id.to_string(),
            name: "Test User".to_string(),
            email: "test@example.com".to_string(),
            ..Default::default()
        },
        if with_keys {
            vec![test_user_key("key-1", 1, 1)]
        } else {
            vec![]
        },
        if with_address {
            vec![test_address("addr-1", "test@example.com")]
        } else {
            vec![]
        },
    )
}

pub fn test_mls_store() -> Arc<RwLock<MlsStore>> {
    Arc::new(RwLock::new(MlsStore {
        clients: HashMap::new(),
        group_map: HashMap::new(),
        config: MlsClientConfig::default(),
    }))
}

pub fn default_app_state() -> AppState {
    AppState {
        app_version: Some("macos-meet@1.0.0".to_string()),
        user_agent: Some("Mac OS X 10.15.7".to_string()),
        active_user: None,
        active_livekit_access_token: None,
        active_livekit_websocket_url: None,
        meeting_display_name_session_key: None,
        mls_store: test_mls_store(),
        active_user_info: None,
        join_start_time: None,
        join_mls_time: None,
        total_join_start_time: None,
        join_type: None,
    }
}

async fn test_http_client_with_host(http_host: &str) -> ProtonHttpClient {
    let config = ApiConfig {
        spec: (
            "macos-meet@1.0.0".to_string(),
            "Mac OS X 10.15.7".to_string(),
        ),
        auth: None,
        url_prefix: None,
        env: Some("atlas".to_string()),
        proxy: None,
    };
    ProtonHttpClient::new(config, AuthStore::atlas(None), http_host.to_string())
        .await
        .expect("failed to build test http client")
}

/// Real atlas host — may succeed when CI has network access.
pub async fn test_proton_http_client() -> Arc<ProtonHttpClient> {
    Arc::new(test_http_client_with_host("atlas.proton.black/api").await)
}

const UNREACHABLE_MUON_SERVER: &str = "http://127.0.0.1:1";

/// Unreachable muon env so session-based HTTP calls fail without hitting atlas.
pub async fn unreachable_test_proton_http_client() -> Arc<ProtonHttpClient> {
    let config = ApiConfig {
        spec: (
            "macos-meet@1.0.0".to_string(),
            "Mac OS X 10.15.7".to_string(),
        ),
        auth: None,
        url_prefix: None,
        env: Some(UNREACHABLE_MUON_SERVER.to_string()),
        proxy: None,
    };
    Arc::new(
        ProtonHttpClient::new(
            config,
            AuthStore::from_custom_env_str(
                UNREACHABLE_MUON_SERVER.to_string(),
                Arc::new(Mutex::new(Auth::None)),
            ),
            "127.0.0.1:1".to_string(),
        )
        .await
        .expect("failed to build unreachable test http client"),
    )
}

pub fn minimal_ws_mock() -> MockWebSocketClient {
    let mut ws = MockWebSocketClient::new();
    ws.expect_get_connection_state()
        .returning(|| Box::pin(ready(ConnectionState::Disconnected)));
    ws
}

pub fn minimal_user_key_provider() -> Arc<dyn UserKeyProvider> {
    Arc::new(MockUserKeyProvider::new())
}

pub async fn minimal_service() -> Service {
    Service::new(
        Arc::new(MockHttpClient::new()),
        Arc::new(MockUserApi::new()),
        Arc::new(MockUserRepository::new()),
        Arc::new(minimal_ws_mock()),
        test_mls_store(),
    )
}

pub fn minimal_room_service() -> Arc<RoomService> {
    Arc::new(RoomService::new(
        Arc::new(MockHttpClient::new()),
        Arc::new(MockMeetingApi::new()),
        Arc::new(MeetCryptoClient::new()),
    ))
}

pub async fn build_app(state: AppState) -> App {
    build_app_with_http(state, test_proton_http_client().await).await
}

pub async fn build_app_with_http(state: AppState, http_client: Arc<ProtonHttpClient>) -> App {
    App::from_test_parts(
        Arc::new(RwLock::new(state)),
        Arc::new(minimal_ws_mock()),
        http_client.clone(),
        http_client.clone(),
        http_client.clone(),
        http_client,
        minimal_user_key_provider(),
        Arc::new(RwLock::new(minimal_service().await)),
        minimal_room_service(),
    )
}

pub async fn build_app_with_test_http(
    state: AppState,
    test_http: Arc<dyn crate::domain::user::ports::HttpClient>,
) -> App {
    let http_client = test_proton_http_client().await;
    App::from_test_parts(
        Arc::new(RwLock::new(state)),
        Arc::new(minimal_ws_mock()),
        test_http.clone(),
        http_client.clone(),
        http_client.clone(),
        http_client,
        minimal_user_key_provider(),
        Arc::new(RwLock::new(minimal_service().await)),
        minimal_room_service(),
    )
}

pub async fn build_app_with_service(state: AppState, service: Service) -> App {
    let http_client = test_proton_http_client().await;
    App::from_test_parts(
        Arc::new(RwLock::new(state)),
        Arc::new(minimal_ws_mock()),
        http_client.clone(),
        http_client.clone(),
        http_client.clone(),
        http_client,
        minimal_user_key_provider(),
        Arc::new(RwLock::new(service)),
        minimal_room_service(),
    )
}

pub fn auth_service(user_api: MockUserApi, user_repository: MockUserRepository) -> Service {
    Service::new(
        Arc::new(MockHttpClient::new()),
        Arc::new(user_api),
        Arc::new(user_repository),
        Arc::new(minimal_ws_mock()),
        test_mls_store(),
    )
}

pub fn test_proton_user(user_id: &str) -> ProtonUser {
    ProtonUser {
        id: user_id.to_string(),
        name: "Test User".to_string(),
        email: "test@example.com".to_string(),
        ..Default::default()
    }
}

pub fn test_upcoming_meeting(id: &str) -> UpcomingMeeting {
    UpcomingMeeting {
        id: id.to_string(),
        address_id: None,
        meeting_link_name: "LINK123".to_string(),
        meeting_name: "Test Meeting".to_string(),
        meeting_password: "password".to_string(),
        meeting_type: MeetingType::Instant,
        start_time: None,
        end_time: None,
        r_rule: None,
        time_zone: None,
        calendar_id: None,
        proton_calendar: 0,
        create_time: None,
        last_used_time: None,
        calendar_event_id: None,
    }
}

pub fn test_meet_info() -> MeetInfo {
    MeetInfo {
        meet_name: "Test Meeting".to_string(),
        meet_link_name: "LINK123".to_string(),
        access_token: "access-token".to_string(),
        websocket_url: "wss://livekit.example".to_string(),
        participants_count: 2,
        is_locked: false,
        max_duration: 3600,
        max_participants: 100,
        expiration_time: None,
    }
}

pub fn state_with_authenticated_user() -> AppState {
    let mut state = default_app_state();
    state.active_user = Some(test_user_state("user-1", true, true));
    state
}

pub fn test_user_identifier(suffix: &str) -> meet_identifiers::UserId {
    meet_identifiers::UserId::from_str(&format!("mimi://proton.me/u/{suffix}"))
        .expect("valid mimi user id")
}

pub fn state_with_participant_only(user_id_suffix: &str) -> AppState {
    let mut state = default_app_state();
    state.active_user_info = Some(UserTokenInfo {
        user_identifier: test_user_identifier(user_id_suffix),
        device_id: "device-1".to_string(),
    });
    state
}

pub fn state_with_active_participant(user_id_suffix: &str) -> AppState {
    let mut state = state_with_participant_only(user_id_suffix);
    state.active_livekit_access_token = Some("lk-token".to_string());
    state
}

pub fn state_with_join_metrics_prereqs(user_id: &str) -> AppState {
    let mut state = state_with_active_participant(user_id);
    state.join_start_time = Some(crate::utils::instant::now());
    state.total_join_start_time = Some(crate::utils::instant::now());
    state
}

pub fn state_with_join_metrics_full(user_id: &str) -> AppState {
    let mut state = state_with_join_metrics_prereqs(user_id);
    state.join_mls_time = Some(crate::utils::instant::now());
    state.join_type = Some(crate::infra::dto::realtime::JoinType::ExternalCommit);
    state
}

pub fn room_service_with_meeting_api(meeting_api: MockMeetingApi) -> Arc<RoomService> {
    Arc::new(RoomService::new(
        Arc::new(MockHttpClient::new()),
        Arc::new(meeting_api),
        Arc::new(MeetCryptoClient::new()),
    ))
}

pub fn room_service_with_meeting_api_and_crypto(
    meeting_api: MockMeetingApi,
    crypto: crate::domain::user::ports::crypto_client::MockCryptoClient,
) -> Arc<RoomService> {
    Arc::new(RoomService::new(
        Arc::new(MockHttpClient::new()),
        Arc::new(meeting_api),
        Arc::new(crypto),
    ))
}

pub fn room_service_with_http(http: MockHttpClient) -> Arc<RoomService> {
    Arc::new(RoomService::new(
        Arc::new(http),
        Arc::new(MockMeetingApi::new()),
        Arc::new(MeetCryptoClient::new()),
    ))
}

pub fn room_service_with_http_and_crypto(
    http: MockHttpClient,
    crypto: crate::domain::user::ports::crypto_client::MockCryptoClient,
) -> Arc<RoomService> {
    Arc::new(RoomService::new(
        Arc::new(http),
        Arc::new(MockMeetingApi::new()),
        Arc::new(crypto),
    ))
}

pub async fn build_app_with_room(state: AppState, room_service: Arc<RoomService>) -> App {
    let http_client = test_proton_http_client().await;
    App::from_test_parts(
        Arc::new(RwLock::new(state)),
        Arc::new(minimal_ws_mock()),
        http_client.clone(),
        http_client.clone(),
        http_client.clone(),
        http_client,
        minimal_user_key_provider(),
        Arc::new(RwLock::new(minimal_service().await)),
        room_service,
    )
}

pub async fn build_app_with_room_and_ws(
    state: AppState,
    room_service: Arc<RoomService>,
    ws: MockWebSocketClient,
) -> App {
    let http_client = test_proton_http_client().await;
    App::from_test_parts(
        Arc::new(RwLock::new(state)),
        Arc::new(ws),
        http_client.clone(),
        http_client.clone(),
        http_client.clone(),
        http_client,
        minimal_user_key_provider(),
        Arc::new(RwLock::new(minimal_service().await)),
        room_service,
    )
}

pub async fn build_app_with_room_and_service(
    state: AppState,
    service: Service,
    room_service: Arc<RoomService>,
) -> App {
    let http_client = test_proton_http_client().await;
    App::from_test_parts(
        Arc::new(RwLock::new(state)),
        Arc::new(minimal_ws_mock()),
        http_client.clone(),
        http_client.clone(),
        http_client.clone(),
        http_client,
        minimal_user_key_provider(),
        Arc::new(RwLock::new(service)),
        room_service,
    )
}

pub async fn build_app_with_ws_and_service(
    ws: Arc<MockWebSocketClient>,
    state: AppState,
    service: Service,
) -> App {
    let http_client = test_proton_http_client().await;
    App::from_test_parts(
        Arc::new(RwLock::new(state)),
        ws,
        http_client.clone(),
        http_client.clone(),
        http_client.clone(),
        http_client,
        minimal_user_key_provider(),
        Arc::new(RwLock::new(service)),
        minimal_room_service(),
    )
}

pub async fn build_app_with_user_key_provider(
    state: AppState,
    user_key_provider: Arc<dyn UserKeyProvider>,
) -> App {
    let http_client = test_proton_http_client().await;
    App::from_test_parts(
        Arc::new(RwLock::new(state)),
        Arc::new(minimal_ws_mock()),
        http_client.clone(),
        http_client.clone(),
        http_client.clone(),
        http_client,
        user_key_provider,
        Arc::new(RwLock::new(minimal_service().await)),
        minimal_room_service(),
    )
}

pub async fn build_app_with_room_and_user_key_provider(
    state: AppState,
    room_service: Arc<RoomService>,
    user_key_provider: Arc<dyn UserKeyProvider>,
) -> App {
    let http_client = test_proton_http_client().await;
    App::from_test_parts(
        Arc::new(RwLock::new(state)),
        Arc::new(minimal_ws_mock()),
        http_client.clone(),
        http_client.clone(),
        http_client.clone(),
        http_client,
        user_key_provider,
        Arc::new(RwLock::new(minimal_service().await)),
        room_service,
    )
}

pub async fn build_app_with_ws(ws: MockWebSocketClient, state: AppState) -> App {
    let http_client = test_proton_http_client().await;
    App::from_test_parts(
        Arc::new(RwLock::new(state)),
        Arc::new(ws),
        http_client.clone(),
        http_client.clone(),
        http_client.clone(),
        http_client,
        minimal_user_key_provider(),
        Arc::new(RwLock::new(minimal_service().await)),
        minimal_room_service(),
    )
}

/// Builds a [`Service`] with an MLS client registered for `meet_link` (via mocked HTTP).
pub async fn join_test_service_with_mls_client(
    email: &str,
    meet_link: &str,
) -> (Service, UserTokenInfo, Arc<RwLock<MlsStore>>) {
    let http = create_mock_http_client_for_mls(email, meet_link, false);
    let mls_store = test_mls_store();
    let service = Service::new(
        Arc::new(http),
        Arc::new(MockUserApi::new()),
        Arc::new(MockUserRepository::new()),
        Arc::new(minimal_ws_mock()),
        mls_store.clone(),
    );
    let user_info = service
        .create_mls_client("access-token", meet_link, "meet-password", None)
        .await
        .expect("create_mls_client should succeed with MLS HTTP mock");
    (service, user_info, mls_store)
}

/// Aligns app state MLS store with the service and sets the active participant.
pub fn app_state_with_mls_participant(
    mut state: AppState,
    mls_store: Arc<RwLock<MlsStore>>,
    user_info: UserTokenInfo,
    livekit_token: Option<&str>,
) -> AppState {
    state.mls_store = mls_store;
    state.active_user_info = Some(user_info);
    if let Some(token) = livekit_token {
        state.active_livekit_access_token = Some(token.to_string());
    }
    state
}

async fn mls_test_service(user_id: &str, meet_link: &str) -> (Service, Arc<RwLock<MlsStore>>) {
    let mls_store = test_mls_store();
    let http = create_mock_http_client_for_mls(user_id, meet_link, false);
    let service = Service::new(
        Arc::new(http),
        Arc::new(MockUserApi::new()),
        Arc::new(MockUserRepository::new()),
        Arc::new(minimal_ws_mock()),
        mls_store.clone(),
    );
    (service, mls_store)
}

/// Two [`Service`] instances in the same MLS group (external-commit join), for chat/crypto tests.
pub async fn two_user_mls_services_with_group(
    meet_link: &str,
    user1_id: &str,
    user2_id: &str,
) -> (
    Service,
    UserTokenInfo,
    Arc<RwLock<MlsStore>>,
    Service,
    UserTokenInfo,
    Arc<RwLock<MlsStore>>,
) {
    use crate::domain::user::ports::UserService;
    use mls_rs_codec::MlsEncode;
    use mls_spec::{messages::MlsMessageContent, Parsable};
    use mls_trait::MlsClientConfig;
    use proton_meet_mls::MlsGroupTrait;

    let (service1, store1) = mls_test_service(user1_id, meet_link).await;
    let (service2, store2) = mls_test_service(user2_id, meet_link).await;
    let ciphersuite = MlsClientConfig::default().ciphersuite;

    let user1 = service1
        .create_mls_client("access-token", meet_link, "meet-password", None)
        .await
        .expect("user1 mls client");
    let (group1, commit_bundle1) = service1
        .create_mls_group(&user1.user_id(), meet_link, meet_link, ciphersuite)
        .await
        .expect("user1 mls group");

    let user2 = service2
        .create_mls_client("access-token", meet_link, "meet-password", None)
        .await
        .expect("user2 mls client");

    let group_info_message = mls_spec::messages::MlsMessage::from_tls_bytes(
        &commit_bundle1
            .group_info
            .clone()
            .expect("group info")
            .mls_encode_to_vec()
            .expect("encode group info"),
    )
    .expect("parse group info tls");
    let group_info = match group_info_message.content {
        MlsMessageContent::GroupInfo(group_info) => group_info,
        _ => panic!("expected GroupInfo"),
    };

    let (_, commit_bundle2) = service2
        .create_external_commit(
            &user2.user_id(),
            meet_link,
            ciphersuite,
            group_info,
            commit_bundle1
                .ratchet_tree
                .expect("ratchet tree")
                .try_into()
                .expect("ratchet tree conversion"),
        )
        .await
        .expect("user2 external commit");

    group1
        .write()
        .await
        .decrypt_message(commit_bundle2.commit.clone())
        .await
        .expect("process user2 join commit");

    (service1, user1, store1, service2, user2, store2)
}

pub async fn build_app_with_mls_service(
    service: Service,
    mls_store: Arc<RwLock<MlsStore>>,
    user_info: UserTokenInfo,
) -> App {
    let state = app_state_with_mls_participant(default_app_state(), mls_store, user_info, None);
    build_app_with_service(state, service).await
}

pub async fn build_app_with_service_room_and_ws(
    state: AppState,
    service: Service,
    room_service: Arc<RoomService>,
    ws: MockWebSocketClient,
) -> App {
    let http_client = test_proton_http_client().await;
    App::from_test_parts(
        Arc::new(RwLock::new(state)),
        Arc::new(ws),
        http_client.clone(),
        http_client.clone(),
        http_client.clone(),
        http_client,
        minimal_user_key_provider(),
        Arc::new(RwLock::new(service)),
        room_service,
    )
}

/// Helpers for `#[ignore]` manual tests that hit real backends. Run with:
/// `cargo test -p proton-meet-core --lib -- --ignored`
#[cfg(all(test, not(target_family = "wasm")))]
pub mod manual {
    use super::App;
    use crate::errors::core::MeetCoreError;
    use crate::infra::adapters::storage::UserKeyProviderAdapter;
    use crate::infra::muon::AuthStore;
    use crate::infra::ports::user_key_provider::UserKeyProvider;
    use muon::auth::Auth;
    use std::sync::Arc;
    use tokio::sync::Mutex;

    pub fn user_key_provider() -> Arc<dyn UserKeyProvider> {
        Arc::new(UserKeyProviderAdapter::new())
    }

    pub async fn app_for_atlas(
        atlas: &str,
        db_path: impl Into<String>,
        ws_host: impl Into<String>,
        app_version: &str,
    ) -> Result<App, MeetCoreError> {
        let api_host = format!("https://{atlas}.proton.black/api");
        let http_host = format!("{atlas}.proton.black/api");
        App::new(
            api_host,
            app_version.to_string(),
            "Mac OS X 10.15.7".to_string(),
            db_path.into(),
            AuthStore::atlas(Some(atlas.to_string())),
            http_host,
            ws_host.into(),
            None,
            user_key_provider(),
        )
        .await
    }

    pub async fn app_for_custom_api(
        api_url: &str,
        http_host: &str,
        db_path: impl Into<String>,
        ws_host: impl Into<String>,
        app_version: &str,
    ) -> Result<App, MeetCoreError> {
        App::new(
            api_url.to_string(),
            app_version.to_string(),
            "Mac OS X 10.15.7".to_string(),
            db_path.into(),
            AuthStore::from_custom_env_str(api_url.to_string(), Arc::new(Mutex::new(Auth::None))),
            http_host.to_string(),
            ws_host.into(),
            None,
            user_key_provider(),
        )
        .await
    }
}
