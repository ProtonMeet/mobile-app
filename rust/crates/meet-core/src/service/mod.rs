// Application Service (orchestrator) for the meet application

pub mod agent_host_service;
#[cfg(not(target_family = "wasm"))]
pub mod auth;
pub mod caption;
pub mod services_bundle;
// forder name is same with module name, ignore for now and refactor later
pub mod mls_service;
pub mod service_state;
pub mod user_service;
pub mod utils;
pub mod waiting_room_setting;

const DELAY_PER_RANK_MS: u64 = 100;
const RANK_GROUP_SIZE: u64 = 3;
const RANK_GROUP_DELAY_MS: u64 = 5000;

struct StaggerStats {
    delay_ms: u64,
    rank_group: u64,
}
fn compute_stagger_time(rank: u64, rank_group_delay: u64) -> StaggerStats {
    use rand::Rng as _;

    let rank_group = rank / RANK_GROUP_SIZE;
    let random_jitter = rand::thread_rng().gen_range(0..=20);

    StaggerStats {
        rank_group,
        delay_ms: random_jitter * DELAY_PER_RANK_MS + rank_group * rank_group_delay,
    }
}

#[cfg(test)]
mod test {
    use std::{collections::HashMap, future::ready, sync::Arc};

    use base64::{prelude::BASE64_STANDARD, Engine};
    use cose_key_thumbprint::CoseKeyThumbprint;
    use ed25519_dalek::pkcs8::DecodePrivateKey;
    use esdicawt::{cose_key_set::CoseKeySet, spec::CwtAny, Issuer, IssuerParams};
    use identity::{Ed25519Issuer, IdentityResult, SdCwt};
    use mls_trait::{MlsClientConfig, MlsGroup};
    use proton_claims::{reexports::SpiceOidcClaims, ClientType, MimiProvider, ProtonMeetClaims};
    use proton_meet_mls::{kv::MemKv, MlsStore};
    use spki::{der::pem::LineEnding, DecodePublicKey, EncodePublicKey};
    use tokio::sync::RwLock;
    use uuid::Uuid;

    #[cfg(not(target_family = "wasm"))]
    use crate::service::auth::AuthServiceImpl;
    use crate::{
        domain::{
            mls::ports::{KeyPackagePort, MockKeyPackagePort},
            room::{RoomService, WaitingRoomService},
            user::ports::{
                meeting_api::{MeetingApi, MockMeetingApi},
                user_api::{MockUserApi, UserApi},
                ArcUserRepository, ArcWebSocketClient, CryptoClient, HttpClient, MlsApi,
                MockCryptoClient, MockHttpClient, MockMlsApi, MockUserRepository,
                MockWebSocketClient, UserService,
            },
        },
        infra::mimi_subject_parser::ANONYMOUS_USER_IDENTIFIER,
        service::{
            caption::CaptionServiceImpl, services_bundle::ServiceBundle, user_service::Service,
        },
        utils::server_time::ServerTimeTracker,
    };

    /// Used by [`create_test_service_bundle_with_host`] to create test service bundles.
    #[derive(Default)]
    pub(super) struct ServiceBundleDI {
        pub http_client: Option<Arc<dyn HttpClient>>,
        pub mls_api: Option<Arc<dyn MlsApi>>,
        pub meeting_api: Option<Arc<dyn MeetingApi>>,
        pub ws_client: Option<ArcWebSocketClient>,
        pub mls_store: Option<Arc<RwLock<MlsStore>>>,
        pub server_time_tracker: Option<ServerTimeTracker>,
        pub crypto_client: Option<Arc<dyn CryptoClient>>,
        pub key_packages: Option<Arc<dyn KeyPackagePort>>,
        pub user_api: Option<Arc<dyn UserApi>>,
        pub user_repository: Option<ArcUserRepository>,
    }

    /// Returned by [`create_test_service_bundle_with_host`] containing all the instances used to create a bundle
    #[allow(unused)]
    pub(super) struct PopulatedServiceBundleDI {
        pub http_client: Arc<dyn HttpClient>,
        pub mls_api: Arc<dyn MlsApi>,
        pub meeting_api: Arc<dyn MeetingApi>,
        pub ws_client: ArcWebSocketClient,
        pub mls_store: Arc<RwLock<MlsStore>>,
        pub server_time_tracker: ServerTimeTracker,
        pub crypto_client: Arc<dyn CryptoClient>,
        pub key_packages: Arc<dyn KeyPackagePort>,
        pub user_api: Arc<dyn UserApi>,
        pub user_repository: ArcUserRepository,

        // The following field contains the services not casted to their respective traits.
        #[cfg(not(target_family = "wasm"))]
        pub auth_service: Arc<AuthServiceImpl>,
        pub caption_service: Arc<CaptionServiceImpl>,
    }

    fn generate_mimi_device_id(
        holder_verifying_key: &ed25519_dalek::VerifyingKey,
    ) -> IdentityResult<String> {
        let thumbprint =
            CoseKeyThumbprint::<32>::compute::<sha2::Sha256>(holder_verifying_key).unwrap();
        Ok(thumbprint.to_string())
    }

    fn generate_mimi_subject(
        mimi_host: &str,
        holder_verifying_key: &ed25519_dalek::VerifyingKey,
        primary_email: Option<String>,
        username: Option<String>,
    ) -> IdentityResult<String> {
        let mimi_device_id = generate_mimi_device_id(holder_verifying_key)?;

        let user_identifier = match (primary_email, username) {
            (Some(email), _) => email,  // Proton user with primary email
            (None, Some(name)) => name, // Proton user without primary email
            (None, None) => ANONYMOUS_USER_IDENTIFIER.to_string(), // Guest user
        };

        Ok(format!(
            "mimi://{mimi_host}/d/{user_identifier}/{mimi_device_id}"
        ))
    }

    pub fn mock_sdcwt_issuance(
        holder_confirmation_key_pem: &str,
        meeting_link_name: &str,
        email: &str,
        organization_role: proton_claims::Role,
        is_host: bool,
    ) -> IdentityResult<(SdCwt, ed25519_dalek::SigningKey)> {
        let payload = ProtonMeetClaims {
            meeting_id: meeting_link_name.to_string(),
            uuid: Uuid::new_v4().into_bytes(),
            oidc_claims: SpiceOidcClaims::default(),
            role: organization_role,
            mimi_provider: MimiProvider::ProtonAg,
            is_from_server: false,
            is_host,
            client_type: ClientType::Guest,
        };

        let issuer_sk = "-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIDR7w12ON3uzdZd8g6HIGOiGe/ozjj0rpBKs1VTVCyCM
-----END PRIVATE KEY-----";

        let issuer_signing_key = ed25519_dalek::SigningKey::from_pkcs8_pem(issuer_sk).unwrap();
        let issuer = Ed25519Issuer::new(issuer_signing_key.clone());
        let holder_verifying_key =
            ed25519_dalek::VerifyingKey::from_public_key_pem(holder_confirmation_key_pem).unwrap();
        let holder_confirmation_key = (&holder_verifying_key).try_into().unwrap();

        // For mock, treat participant_uid as email if it contains '@', otherwise as username
        let (primary_email, username) = if email.contains('@') {
            (Some(email.to_string()), None)
        } else {
            (None, Some(email.to_string()))
        };

        let sub = generate_mimi_subject(
            "meet.proton.me",
            &holder_verifying_key,
            primary_email,
            username,
        )
        .unwrap();

        let params = IssuerParams {
            protected_claims: None,
            unprotected_claims: None,
            payload: Some(payload),
            subject: Some(&sub),
            audience: None,
            expiry: None,
            with_not_before: true,
            with_issued_at: true,
            cti: None,
            cnonce: None,
            key_location: "https://auth.proton.me/issuer.cwk",
            holder_confirmation_key,
            issuer: "mimi://i/proton.me",
            leeway: Default::default(),
            artificial_time: None,
        };

        let sd_cwt = issuer.issue_cwt(&mut rand::thread_rng(), params).unwrap();
        Ok((sd_cwt, issuer_signing_key))
    }

    /// Helper function to create a mock MLS API with common expectations
    pub(super) fn create_mock_mls_api(
        email: &str,
        meeting_link_name: &str,
        is_host: bool,
    ) -> MockMlsApi {
        let mut mls_api = MockMlsApi::new();

        let issuer_sk = "-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIDR7w12ON3uzdZd8g6HIGOiGe/ozjj0rpBKs1VTVCyCM
-----END PRIVATE KEY-----";

        let issuer_signing_key = ed25519_dalek::SigningKey::from_pkcs8_pem(issuer_sk).unwrap();
        let cks = CoseKeySet::new(&issuer_signing_key).unwrap();
        let email = email.to_string();
        let meeting_link_name = meeting_link_name.to_string();

        mls_api
            .expect_fetch_sd_cwt()
            .returning(move |_, _, base64_holder_verifying_key, _| {
                let holder_verifying_key =
                    BASE64_STANDARD.decode(base64_holder_verifying_key).unwrap();
                let holder_verifying_key = ed25519_dalek::VerifyingKey::from_bytes(
                    &holder_verifying_key.as_slice().try_into().unwrap(),
                )
                .unwrap();
                let holder_verifying_key_pem = holder_verifying_key
                    .to_public_key_pem(LineEnding::LF)
                    .unwrap();
                let (sd_cwt, _issuer_signing_key) = mock_sdcwt_issuance(
                    &holder_verifying_key_pem,
                    &meeting_link_name,
                    &email,
                    proton_claims::Role::User,
                    is_host,
                )
                .unwrap();
                let base64_sd_cwt = BASE64_STANDARD.encode(sd_cwt.to_cbor_bytes().unwrap());
                Box::pin(ready(Ok(base64_sd_cwt)))
            });

        let cks_clone = cks.clone();
        mls_api
            .expect_fetch_cose_key_set()
            .returning(move || Box::pin(ready(Ok(cks_clone.to_cbor_bytes().unwrap()))));
        mls_api
            .expect_fetch_external_sender()
            .returning(move || Box::pin(ready(Ok(vec![]))));

        mls_api
    }

    /// Creates a test [`ServicesBundle`].
    ///
    /// Reads from the provided [`ServiceBundleDI`] for arguments to give to the different services. `None` values are
    /// replaced with empty `Mock*` instances, with two exceptions:
    /// - [`MlsApi`] is created from the provided `user_id`, `meet_link_name` and `is_host`, using [`create_mock_mls_api`].
    /// - [`WebSocketClient`][crate::domain::user::ports::WebSocketClient] is set to always return
    ///     [`Connected`](crate::domain::user::ports::ConnectionState::Connected) when
    ///     [`get_connection_state`](crate::domain::user::ports::WebSocketClient::get_connection_state) is called.
    fn create_test_service_bundle_with_host(
        user_id: &str,
        meet_link_name: &str,
        is_host: bool,
        di: ServiceBundleDI,
    ) -> (ServiceBundle, PopulatedServiceBundleDI) {
        let http_client = di
            .http_client
            .unwrap_or_else(|| Arc::new(MockHttpClient::new()));
        let mls_api = di
            .mls_api
            .unwrap_or_else(|| Arc::new(create_mock_mls_api(user_id, meet_link_name, is_host)));
        let meeting_api = di
            .meeting_api
            .unwrap_or_else(|| Arc::new(MockMeetingApi::new()));
        let ws_client = di.ws_client.unwrap_or_else(|| {
            let mut ws_client = MockWebSocketClient::new();
            ws_client.expect_get_connection_state().returning(|| {
                Box::pin(ready(
                    crate::domain::user::ports::ConnectionState::Connected,
                ))
            });
            Arc::new(ws_client)
        });
        let mls_store = di.mls_store.unwrap_or_else(|| {
            Arc::new(RwLock::new(MlsStore {
                clients: HashMap::new(),
                group_map: HashMap::new(),
                config: MlsClientConfig::default(),
            }))
        });
        let server_time_tracker = di
            .server_time_tracker
            .unwrap_or_else(|| ServerTimeTracker::new());
        let crypto_client = di
            .crypto_client
            .unwrap_or_else(|| Arc::new(MockCryptoClient::new()));
        let key_packages = di
            .key_packages
            .unwrap_or_else(|| Arc::new(MockKeyPackagePort::new()));
        let user_api = di.user_api.unwrap_or_else(|| Arc::new(MockUserApi::new()));
        let user_repository = di
            .user_repository
            .unwrap_or_else(|| Arc::new(MockUserRepository::new()));

        let user_service = Arc::new(RwLock::new(Service::new(
            http_client.clone(),
            mls_api.clone(),
            meeting_api.clone(),
            ws_client.clone(),
            mls_store.clone(),
            server_time_tracker.clone(),
        )));

        #[cfg(not(target_family = "wasm"))]
        let auth_service = Arc::new(AuthServiceImpl::new(
            user_api.clone(),
            user_repository.clone(),
        ));
        let caption_service = Arc::new(CaptionServiceImpl::new(
            mls_api.clone(),
            mls_store.clone(),
            user_service.clone(),
            meeting_api.clone(),
        ));

        (
            ServiceBundle::new(
                Arc::new(RoomService::new(
                    http_client.clone(),
                    meeting_api.clone(),
                    crypto_client.clone(),
                )),
                Arc::new(WaitingRoomService::new(
                    crypto_client.clone(),
                    key_packages.clone(),
                )),
                #[cfg(not(target_family = "wasm"))]
                auth_service.clone(),
                caption_service.clone(),
                user_service,
            ),
            PopulatedServiceBundleDI {
                http_client,
                mls_api,
                meeting_api,
                ws_client,
                mls_store,
                server_time_tracker,
                crypto_client,
                key_packages,
                user_api,
                user_repository,
                #[cfg(not(target_family = "wasm"))]
                auth_service,
                caption_service,
            },
        )
    }

    pub fn create_test_service_bundle(
        user_id: &str,
        meet_link_name: &str,
        di: ServiceBundleDI,
    ) -> (ServiceBundle, PopulatedServiceBundleDI) {
        create_test_service_bundle_with_host(user_id, meet_link_name, false, di)
    }

    pub(super) async fn setup_single_user_group(
        room_id: &str,
        di: ServiceBundleDI,
    ) -> (
        ServiceBundle,
        PopulatedServiceBundleDI,
        Arc<RwLock<MlsGroup<MemKv>>>,
        proton_meet_mls::CipherSuite,
        String,
    ) {
        let config = MlsClientConfig::default();
        let (bundle, populated) = create_test_service_bundle("psk-unit-user", room_id, di);
        let user_token_info = bundle
            .user_service
            .read()
            .await
            .create_mls_client("access_token", room_id, "meet_password", None)
            .await
            .unwrap();

        let (group, _) = bundle
            .user_service
            .read()
            .await
            .create_mls_group(
                &user_token_info.user_id(),
                room_id,
                room_id,
                config.ciphersuite,
            )
            .await
            .unwrap();

        let user_key = {
            let store = populated.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("client should exist")
        };

        (bundle, populated, group, config.ciphersuite, user_key)
    }
}
