use muon::auth::Auth;
#[cfg(not(target_family = "wasm"))]
use muon::common::Scheme;
use muon::common::sdk::Sdk;
use muon::{App, ProtonRequest, ProtonResponse};

use crate::domain::user::models::login::Modulus;
use crate::domain::user::models::meet_link_info::{
    AccessTokenInfo, MeetLinkAuthInfo, MeetLinkInfo, MeetParticipant,
};
use crate::domain::user::models::meeting::{Meeting, MeetingInfo};
use crate::domain::user::models::participant_track_settings::ParticipantTrackSettings;
use crate::domain::user::models::user_settings::UserSettings;
use crate::domain::user::ports::HttpClient;
use crate::errors::http_client::HttpClientError;
use crate::infra::dto::access_token::{AccessTokenRequest, AccessTokenResponse};
use crate::infra::dto::login::GetModulusResponse;
use crate::infra::dto::meet_link_info::{
    AuthMeetLinkRequest, AuthMeetLinkResponse, MeetInfoResponse, MeetLinkInfoResponse,
    MeetParticipantsCountResponse, MeetParticipantsResponse,
};
use crate::infra::dto::meeting::ActiveMeetingsResponse;
use crate::infra::dto::participant_track_settings::{
    ParticipantTrackSettingsRequest, ParticipantTrackSettingsResponse,
};
use crate::infra::dto::remove_participant::{RemoveParticipantRequest, RemoveParticipantResponse};
use crate::infra::dto::user_settings::{
    UpdateUserSettingsWaitingRoomRequest, UserSettingsResponse,
};
use crate::infra::http_client_util::HttpClientUtil;
#[cfg(target_arch = "wasm32")]
use crate::infra::muon::environment_from_str;
#[cfg(all(not(target_family = "wasm"), not(feature = "insecure-tls")))]
use crate::infra::muon::is_prod_environment;
#[cfg(not(target_arch = "wasm32"))]
use crate::infra::muon::{AuthStore, SharedAuth};
use crate::infra::muon::{
    MeetClient, MeetClientExt, MeetSession, build_meet_client, meet_sdk_from_app,
};
use crate::infra::proton_response_ext::ProtonResponseExt;
use crate::utils::server_time::ServerTimeTracker;
use proton_meet_macro::async_trait;
use reqwest::header::{HeaderMap, HeaderValue, USER_AGENT};
use std::sync::{Arc, Mutex};
use tokio::sync::RwLock;
use url::Url;

/// Error code returned by the API when the meeting link is locked
const MEETING_LOCKED_ERROR_CODE: u16 = 2502;

/// Error code returned by the API when SRP parameters are invalid — i.e. the
/// URL/custom password the caller supplied does not match the meeting link.
const INVALID_SRP_PARAMS_ERROR_CODE: u16 = 2026;

/// Max time to wait for a full MLS HTTP request/response round-trip before
/// giving up. reqwest has no default timeout, so without this a stalled
/// connection (e.g. a reused but silently-dropped keep-alive socket, or a
/// server that received the request but never responds) hangs the whole join
/// flow forever. Applied per-request in [`ProtonHttpClient::send_mls`], so it
/// guards every MLS call on both native and wasm.
const MLS_REQUEST_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(30);

/// Max time to wait for the TCP/TLS connection to be established (native only;
/// not configurable on the wasm fetch backend).
#[cfg(not(target_family = "wasm"))]
const MLS_CONNECT_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);

/// How long an idle pooled connection may be kept before being discarded
/// (native only). Kept short so we stop reusing connections that an
/// intermediary (NAT/load balancer) has silently closed — the main cause of
/// the intermittent "stuck forever" joins.
#[cfg(not(target_family = "wasm"))]
const MLS_POOL_IDLE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(15);

/// TCP keepalive interval for pooled connections (native only). Helps detect
/// dead peers instead of waiting indefinitely on a half-open socket.
#[cfg(not(target_family = "wasm"))]
const MLS_TCP_KEEPALIVE: std::time::Duration = std::time::Duration::from_secs(15);

fn single_header<'a>(headers: &'a HeaderMap, name: &str) -> Option<&'a str> {
    let mut values = headers.get_all(name).iter();
    let value = values.next()?;
    if values.next().is_some() {
        tracing::debug!("Ignoring ambiguous {name} server time response header");
        return None;
    }
    value.to_str().ok()
}

#[derive(Debug)]
pub struct ApiConfig {
    /// A tupple composed of `app_version` and `user_agent`
    pub spec: (String, String),
    /// The api client initial auth data
    pub auth: Option<Auth>,
    /// An optional prefix to use on every api endpoint call
    pub url_prefix: Option<String>,
    /// The env for the api client
    /// could be [altas, prod, or rul link]
    pub env: Option<String>,
    /// The proxy address. Enable `allow-dangerous-env`` feature to use this
    pub proxy: Option<ProxyConfig>,
}

#[derive(Debug)]
pub struct ProxyConfig {
    pub host: String,
    pub port: u16,
}

#[derive(Debug, Clone)]
pub struct ProtonHttpClient {
    client: Arc<Mutex<MeetClient>>,
    session: Arc<Mutex<MeetSession>>,
    pub http_host: String,
    mls_session: reqwest::Client,
    #[cfg_attr(target_arch = "wasm32", allow(dead_code))]
    app_version: String,
    #[cfg_attr(target_arch = "wasm32", allow(dead_code))]
    user_agent: String,
    meet_sdk: Option<Sdk>,
    cks_cache: Arc<RwLock<Option<Vec<u8>>>>,
    external_sender_cache: Arc<RwLock<Option<Vec<u8>>>>,
    server_time: ServerTimeTracker,
}

impl ProtonHttpClient {
    /// Helper function to build a URL from http_host and a path
    pub(crate) fn build_http_url(&self, path: &str) -> Result<Url, HttpClientError> {
        let mut base = self.http_host.trim_end_matches('/').to_string();

        // Add back trailing slash if the base has a path component
        // This ensures URL::join doesn't replace the last segment
        if base.contains('/') && !base.ends_with('/') {
            base.push('/');
        }

        let base_url = if base.starts_with("https://") {
            base
        } else {
            format!("https://{base}")
        };
        let url = Url::parse(&base_url)?.join(path)?;
        Ok(url)
    }

    pub(crate) fn mls_session(&self) -> &reqwest::Client {
        &self.mls_session
    }

    pub(crate) fn server_time_tracker(&self) -> ServerTimeTracker {
        self.server_time.clone()
    }

    pub(crate) async fn send_mls(
        &self,
        request: reqwest::RequestBuilder,
    ) -> Result<reqwest::Response, HttpClientError> {
        // Per-request timeout is the lowest-level guard every MLS request goes
        // through. It works on both native and wasm (browser fetch via
        // AbortController), so no MLS call can hang forever. A timeout surfaces
        // as `HttpClientError::MlsNetworkTimeout` (see `From<reqwest::Error>`).
        let response = request.timeout(MLS_REQUEST_TIMEOUT).send().await?;
        self.observe_server_time_headers(response.headers());
        Ok(response)
    }

    pub(crate) fn cks_cache(&self) -> &RwLock<Option<Vec<u8>>> {
        &self.cks_cache
    }

    pub(crate) fn external_sender_cache(&self) -> &RwLock<Option<Vec<u8>>> {
        &self.external_sender_cache
    }

    pub fn get_session(&self) -> MeetSession {
        self.session
            .lock()
            .expect("ProtonHttpClient session lock poisoned")
            .clone()
    }

    pub fn muon_client(&self) -> MeetClient {
        self.client
            .lock()
            .expect("ProtonHttpClient client lock poisoned")
            .clone()
    }

    pub(crate) async fn send_session_request(
        &self,
        req: ProtonRequest,
    ) -> Result<ProtonResponse, HttpClientError> {
        self.send_on_session(&self.get_session(), req).await
    }

    pub(crate) async fn send_on_session(
        &self,
        session: &MeetSession,
        req: ProtonRequest,
    ) -> Result<ProtonResponse, HttpClientError> {
        let res = if let Some(sdk) = &self.meet_sdk {
            session.send_with_sdk(req, sdk).await
        } else {
            // this is fallback in case meet_sdk is not set remove when muon stop supporting
            #[allow(deprecated)]
            session.send(req).await
        };
        match res {
            Ok(response) => {
                self.observe_server_time_headers(response.headers());
                Ok(response)
            }
            Err(error) => {
                self.observe_muon_error(&error);
                Err(HttpClientError::from(error))
            }
        }
    }

    fn observe_muon_error(&self, error: &muon::Error) {
        let mut source: Option<&(dyn std::error::Error + 'static)> = Some(error);
        while let Some(source_error) = source {
            if let Some(status_error) = source_error.downcast_ref::<muon::http::StatusErr>() {
                self.observe_server_time_headers(status_error.1.headers());
            }
            if let Some(auth_error) = source_error.downcast_ref::<muon::common::AuthErr>() {
                match auth_error {
                    muon::common::AuthErr::Refresh(Some(status_error))
                    | muon::common::AuthErr::Session(Some(status_error)) => {
                        self.observe_server_time_headers(status_error.1.headers());
                    }
                    muon::common::AuthErr::Refresh(None) | muon::common::AuthErr::Session(None) => {
                    }
                }
            }
            source = source_error.source();
        }
    }

    fn observe_server_time_headers(&self, headers: &HeaderMap) {
        self.server_time.observe_header_values(
            single_header(headers, "x-pm-date"),
            single_header(headers, "date"),
        );
    }

    /// Rebuild the muon client from `auth_store` and swap in a fresh session.
    #[cfg(not(target_arch = "wasm32"))]
    pub(crate) async fn sync_auth_store(
        &self,
        auth_store: AuthStore,
    ) -> Result<(), HttpClientError> {
        let app = App::new(self.app_version.clone())
            .map_err(|e| HttpClientError::MlsHttpError {
                message: format!("invalid app version: {e}"),
            })?
            .with_user_agent(self.user_agent.clone());
        let client = build_meet_client(app, auth_store.environment.clone(), auth_store, None)?;
        self.replace_session(client).await
    }

    /// Build a muon client with the given auth store (loads auth into the local store).
    #[cfg(not(target_arch = "wasm32"))]
    pub(crate) fn build_client(&self, store: AuthStore) -> Result<MeetClient, HttpClientError> {
        let app = App::new(self.app_version.clone())
            .map_err(|e| HttpClientError::MlsHttpError {
                message: format!("invalid app version: {e}"),
            })?
            .with_user_agent(self.user_agent.clone());
        build_meet_client(app, store.environment.clone(), store, None)
            .map_err(HttpClientError::from)
    }

    /// Replace the active muon session (e.g. after promoting desktop web login auth).
    #[cfg_attr(target_arch = "wasm32", allow(dead_code))]
    pub(crate) async fn replace_session(&self, client: MeetClient) -> Result<(), HttpClientError> {
        let session = client
            .default_session()
            .await
            .map_err(HttpClientError::from)?;
        const SESSION_UPDATE_FAILED: &str = "Unable to complete sign-in. Please try again.";
        let mut client_guard = self
            .client
            .lock()
            .map_err(|_| HttpClientError::MlsHttpError {
                message: SESSION_UPDATE_FAILED.to_string(),
            })?;
        *client_guard = client;
        let mut session_guard = self
            .session
            .lock()
            .map_err(|_| HttpClientError::MlsHttpError {
                message: SESSION_UPDATE_FAILED.to_string(),
            })?;
        *session_guard = session;
        Ok(())
    }

    /// Fresh muon session for desktop web login — does not touch the main session.
    #[cfg(not(target_arch = "wasm32"))]
    pub async fn new_isolated_login_client(
        &self,
    ) -> Result<(MeetSession, SharedAuth), HttpClientError> {
        let environment = self.get_session().env().clone();
        let login_auth = Arc::new(tokio::sync::Mutex::new(Auth::None));
        let login_store = AuthStore {
            environment,
            auth: login_auth.clone(),
        };
        let client = self.build_client(login_store)?;
        let session = client
            .default_session()
            .await
            .map_err(HttpClientError::from)?;
        Ok((session, login_auth))
    }

    fn mls_default_headers(
        app_version: &str,
        user_agent: &str,
    ) -> Result<HeaderMap, HttpClientError> {
        let mut headers = HeaderMap::new();
        headers.insert(
            USER_AGENT,
            HeaderValue::from_str(user_agent).map_err(|e| HttpClientError::MlsHttpError {
                message: format!("invalid User-Agent header value: {e}"),
            })?,
        );
        headers.insert(
            reqwest::header::HeaderName::from_static("x-app-version"),
            HeaderValue::from_str(app_version).map_err(|e| HttpClientError::MlsHttpError {
                message: format!("invalid X-App-Version header value: {e}"),
            })?,
        );
        Ok(headers)
    }

    /// Build a proton HTTP client with muon persistence (native only).
    #[cfg(not(target_arch = "wasm32"))]
    pub async fn new(
        config: ApiConfig,
        auth_store: AuthStore,
        http_host: String,
    ) -> Result<Self, anyhow::Error> {
        let app_version = config.spec.0.clone();
        let user_agent = config.spec.1.clone();
        let mls_default_headers =
            Self::mls_default_headers(&app_version, &user_agent).map_err(anyhow::Error::from)?;
        let app = App::new(app_version.clone())?.with_user_agent(user_agent.clone());
        let meet_sdk = meet_sdk_from_app(&app);
        let environment = auth_store.environment.clone();
        let client = build_meet_client(app, environment, auth_store, config.proxy.as_ref())?;
        let session = client.default_session().await?;
        Self::from_parts(
            config,
            client,
            session,
            http_host,
            app_version,
            user_agent,
            meet_sdk,
            mls_default_headers,
        )
        .await
    }

    #[cfg(not(target_arch = "wasm32"))]
    pub(crate) async fn new_with_server_time(
        config: ApiConfig,
        auth_store: AuthStore,
        http_host: String,
        server_time: ServerTimeTracker,
    ) -> Result<Self, anyhow::Error> {
        let mut client = Self::new(config, auth_store, http_host).await?;
        client.server_time = server_time;
        Ok(client)
    }

    /// Build a proton HTTP client without muon persistence (WASM).
    #[cfg(target_arch = "wasm32")]
    pub async fn new(config: ApiConfig, http_host: String) -> Result<Self, anyhow::Error> {
        let app_version = config.spec.0.clone();
        let user_agent = config.spec.1.clone();
        let mls_default_headers =
            Self::mls_default_headers(&app_version, &user_agent).map_err(anyhow::Error::from)?;
        let app = App::new(app_version.clone())?.with_user_agent(user_agent.clone());
        let meet_sdk = meet_sdk_from_app(&app);
        let environment = environment_from_str(config.env.as_deref().unwrap_or("atlas"));
        let client = build_meet_client(app, environment, config.proxy.as_ref())?;
        let initial_auth = config.auth.clone().unwrap_or(Auth::None);
        let mut session = client.default_session().await?;
        if let (Some(user_id), Some(uid)) = (initial_auth.user_id(), initial_auth.uid()) {
            session = session.auth().from_uid(user_id, uid).await;
        }
        Self::from_parts(
            config,
            client,
            session,
            http_host,
            app_version,
            user_agent,
            meet_sdk,
            mls_default_headers,
        )
        .await
    }

    #[allow(clippy::too_many_arguments)]
    #[cfg_attr(target_arch = "wasm32", allow(unused_variables))]
    async fn from_parts(
        config: ApiConfig,
        client: MeetClient,
        session: MeetSession,
        http_host: String,
        app_version: String,
        user_agent: String,
        meet_sdk: Option<Sdk>,
        mls_default_headers: HeaderMap,
    ) -> Result<Self, anyhow::Error> {
        #[cfg(not(target_family = "wasm"))]
        let mls_session = {
            #[cfg(feature = "insecure-tls")]
            let mut mls_builder = {
                use crate::utils::reqwest::dev_reqwest_builder;
                dev_reqwest_builder()
            };

            #[cfg(not(feature = "insecure-tls"))]
            let mut mls_builder = {
                use crate::infra::tls_pinning::build_prod_tls_config;

                let is_prod = match config.env.as_deref() {
                    None => true,
                    Some(s) => is_prod_environment(s),
                };

                if is_prod {
                    let tls_config = build_prod_tls_config().map_err(|e| {
                        HttpClientError::ProxyError(format!("Failed to build prod TLS config: {e}"))
                    })?;
                    reqwest::ClientBuilder::new().use_preconfigured_tls(tls_config)
                } else {
                    reqwest::ClientBuilder::new()
                }
            };

            if let Some(proxy) = &config.proxy {
                mls_builder = mls_builder.proxy(
                    reqwest::Proxy::all(format!(
                        "{}://{}:{}",
                        Scheme::Http,
                        proxy.host,
                        proxy.port
                    ))
                    .map_err(|e| {
                        HttpClientError::ProxyError(format!("Invalid proxy configuration: {e}"))
                    })?,
                );
            }
            mls_builder
                // Fail fast on a stalled connect/response instead of hanging
                // the join flow indefinitely.
                .connect_timeout(MLS_CONNECT_TIMEOUT)
                .timeout(MLS_REQUEST_TIMEOUT)
                // Avoid reusing keep-alive connections that have been silently
                // dropped by an intermediary; this is the main source of the
                // intermittent "stuck on Encrypting with MLS" joins.
                .pool_idle_timeout(MLS_POOL_IDLE_TIMEOUT)
                .tcp_keepalive(MLS_TCP_KEEPALIVE)
                .default_headers(mls_default_headers)
                .build()?
        };

        // The wasm fetch backend does not support connection-level timeout /
        // pooling knobs, so the per-request timeout in `send_mls` is what
        // guards MLS calls on wasm.
        #[cfg(target_family = "wasm")]
        let mls_session = reqwest::ClientBuilder::new()
            .default_headers(mls_default_headers)
            .build()?;

        Ok(Self {
            client: Arc::new(Mutex::new(client)),
            session: Arc::new(Mutex::new(session)),
            http_host,
            mls_session,
            app_version,
            user_agent,
            meet_sdk,
            cks_cache: Arc::new(RwLock::new(None)),
            external_sender_cache: Arc::new(RwLock::new(None)),
            server_time: ServerTimeTracker::new(),
        })
    }
}

#[async_trait]
impl HttpClient for ProtonHttpClient {
    fn get_session(&self) -> MeetSession {
        ProtonHttpClient::get_session(self)
    }

    async fn get_meet_link_info(
        &self,
        meet_link_name: &str,
    ) -> Result<MeetLinkInfo, HttpClientError> {
        let req = self.get(format!("/meet/v1/meetings/links/{meet_link_name}/info"));
        let res = self.send_session_request(req).await?;
        let meet_link_info_res = res.parse_response::<MeetLinkInfoResponse>()?;
        Ok(meet_link_info_res.into())
    }

    async fn get_participants(
        &self,
        meet_link_name: &str,
    ) -> Result<Vec<MeetParticipant>, HttpClientError> {
        let req = self.get(format!(
            "/meet/v1/meetings/links/{meet_link_name}/participants"
        ));
        let res = self.send_session_request(req).await?;
        let participants_res = res.parse_response::<MeetParticipantsResponse>()?;
        Ok(participants_res.into())
    }

    async fn get_participants_count(&self, meet_link_name: &str) -> Result<u32, HttpClientError> {
        let req = self.get(format!(
            "/meet/v1/meetings/links/{meet_link_name}/participants/count"
        ));
        let res = self.send_session_request(req).await?;
        let count_res = res.parse_response::<MeetParticipantsCountResponse>()?;
        Ok(count_res.current)
    }

    async fn auth_meet_link(
        &self,
        meet_link_name: &str,
        client_ephemeral: &str,
        client_proof: &str,
        srp_session: &str,
    ) -> Result<MeetLinkAuthInfo, HttpClientError> {
        let req = self
            .post(format!("/meet/v1/meetings/links/{meet_link_name}/auth"))
            .body_json(AuthMeetLinkRequest {
                client_ephemeral: client_ephemeral.to_string(),
                client_proof: client_proof.to_string(),
                srp_session: srp_session.to_string(),
            })?;
        let res = self.send_session_request(req).await?;
        let auth_meet_link_res = match res.parse_response::<AuthMeetLinkResponse>() {
            Ok(response) => response,
            Err(HttpClientError::ErrorCode(_, ref error))
                if error.code == INVALID_SRP_PARAMS_ERROR_CODE =>
            {
                return Err(HttpClientError::IncorrectPassword);
            }
            Err(e) => return Err(e),
        };
        Ok(auth_meet_link_res.into())
    }

    async fn update_participant_track_settings(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
        audio_enabled: Option<u8>,
        video_enabled: Option<u8>,
    ) -> Result<ParticipantTrackSettings, HttpClientError> {
        let req = self.put(format!("/meet/v1/meetings/links/{meet_link_name}/participants/{participant_uuid}/track-settings")).body_json(
            ParticipantTrackSettingsRequest {
                access_token: access_token.to_string(),
                audio: audio_enabled,
                video: video_enabled,
            })?;
        let res = self.send_session_request(req).await?;

        #[cfg(debug_assertions)]
        tracing::info!(
            "Participant track settings response code: {}, body: {:?}",
            res.status(),
            res.body_str()
        );
        #[cfg(not(debug_assertions))]
        tracing::info!("Participant track settings response code: {}", res.status());

        let participant_track_settings_res: ParticipantTrackSettingsResponse =
            res.into_body_json()?;
        Ok(participant_track_settings_res.into())
    }

    async fn remove_participant(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
    ) -> Result<(), HttpClientError> {
        let req = self
            .post(format!(
                "/meet/v1/meetings/links/{meet_link_name}/participants/{participant_uuid}/remove"
            ))
            .body_json(RemoveParticipantRequest {
                access_token: access_token.to_string(),
            })?;
        let res = self.send_session_request(req).await?;
        #[cfg(debug_assertions)]
        tracing::debug!(
            "Remove participant response code: {}, body: {:?}",
            res.status(),
            res.body_str()
        );
        #[cfg(not(debug_assertions))]
        tracing::debug!("Remove participant response code: {}", res.status());
        let _remove_participant_res: RemoveParticipantResponse = res.into_body_json()?;
        Ok(())
    }

    async fn get_meet_info(&self, meet_link_name: &str) -> Result<MeetingInfo, HttpClientError> {
        let req = self.get(format!("/meet/v1/meetings/links/{meet_link_name}"));
        let res = self.send_session_request(req).await?;
        let meet_link_info_res = res.parse_response::<MeetInfoResponse>()?;
        Ok(meet_link_info_res.into())
    }

    async fn fetch_access_token(
        &self,
        meet_link_name: &str,
        display_name: &str,
        encrypted_display_name: &str,
    ) -> Result<AccessTokenInfo, HttpClientError> {
        let req = self
            .post(format!(
                "/meet/v1/meetings/links/{meet_link_name}/access-tokens"
            ))
            .body_json(AccessTokenRequest {
                display_name: display_name.to_string(),
                encrypted_display_name: encrypted_display_name.to_string(),
            })?;
        let res = self.send_session_request(req).await?;
        let access_token_res = match res.parse_response::<AccessTokenResponse>() {
            Ok(response) => response,
            Err(HttpClientError::ErrorCode(_, ref error))
                if error.code == MEETING_LOCKED_ERROR_CODE =>
            {
                return Err(HttpClientError::MeetingLocked);
            }
            Err(e) => return Err(e),
        };
        Ok(AccessTokenInfo {
            access_token: access_token_res.access_token,
            websocket_url: access_token_res.websocket_url,
        })
    }

    async fn get_active_meetings(&self) -> Result<Vec<Meeting>, HttpClientError> {
        let req = self.get("/meet/v1/meetings/active");
        let res = self.send_session_request(req).await?;
        let active_meetings_res = res.parse_response::<ActiveMeetingsResponse>()?;
        Ok(active_meetings_res
            .meetings
            .into_iter()
            .map(|m| m.try_into())
            .collect::<Result<Vec<Meeting>, _>>()?)
    }

    async fn get_user_settings(&self) -> Result<UserSettings, HttpClientError> {
        let req = self.get("/meet/v1/user-settings");
        let res = self.send_session_request(req).await?;
        let user_settings_res = res.parse_response::<UserSettingsResponse>()?;
        Ok(user_settings_res.into())
    }

    async fn update_user_settings_waiting_room(
        &self,
        enable: bool,
    ) -> Result<UserSettings, HttpClientError> {
        let req = self
            .put("/meet/v1/user-settings/waiting-room")
            .body_json(UpdateUserSettingsWaitingRoomRequest::new(enable))?;
        let res = self.send_session_request(req).await?;
        let user_settings_res = res.parse_response::<UserSettingsResponse>()?;
        Ok(user_settings_res.into())
    }

    async fn get_modulus(&self) -> Result<Modulus, HttpClientError> {
        let req = self.get("/core/v4/auth/modulus");
        let res = self.send_session_request(req).await?;
        let modulus_res = res.parse_response::<GetModulusResponse>()?;
        Ok(modulus_res.into())
    }

    async fn ping(&self) -> Result<u64, HttpClientError> {
        use crate::errors::http_client::response_error_from_api_failure_body;

        let start = crate::utils::instant::now();
        let req = self.get("/tests/ping");
        let res = self.send_session_request(req).await?;

        let status = res.status();
        let body = res.body().to_vec();
        if !status.is_success() {
            let parsed = response_error_from_api_failure_body(&body, status.as_u16());
            return Err(HttpClientError::ErrorCode(status, parsed));
        }
        let rtt_ms = start.elapsed().as_millis() as u64;
        Ok(rtt_ms)
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use proton_meet_macro::unified_test;

    async fn create_test_client(http_host: &str) -> ProtonHttpClient {
        let config = ApiConfig {
            spec: ("macos-meet@0.0.1".to_string(), "test-agent".to_string()),
            auth: None,
            url_prefix: None,
            env: None,
            proxy: None,
        };

        ProtonHttpClient::new(config, AuthStore::prod(), http_host.to_string())
            .await
            .unwrap()
    }

    #[test]
    fn single_header_rejects_ambiguous_values() {
        let mut headers = HeaderMap::new();
        headers.append(
            "date",
            HeaderValue::from_static("Mon, 17 Aug 2026 09:49:56 GMT"),
        );
        headers.append(
            "date",
            HeaderValue::from_static("Mon, 17 Aug 2026 09:49:57 GMT"),
        );

        assert_eq!(single_header(&headers, "date"), None);
    }

    #[unified_test]
    async fn test_build_http_url_with_meet_proton_me() {
        let client = create_test_client("meet.proton.me/api").await;

        let url = client.build_http_url("v1/meetings").unwrap();
        assert_eq!(url.as_str(), "https://meet.proton.me/api/v1/meetings");
    }

    #[unified_test]
    async fn test_build_http_url_with_path() {
        let client = create_test_client("meet.proton.me/meet/api/").await;

        let url = client
            .build_http_url("v1/meetings/links/test/info")
            .unwrap();
        assert_eq!(
            url.as_str(),
            "https://meet.proton.me/meet/api/v1/meetings/links/test/info"
        );
    }

    #[unified_test]
    async fn test_build_http_url_with_mls_endpoints() {
        let client = create_test_client("meet.proton.me/meet/api").await;

        let url = client.build_http_url("v1/groupInfo").unwrap();
        assert_eq!(url.as_str(), "https://meet.proton.me/meet/api/v1/groupInfo");

        let url = client.build_http_url("v1/session").unwrap();
        assert_eq!(url.as_str(), "https://meet.proton.me/meet/api/v1/session");

        let url = client.build_http_url(".well-known/cks").unwrap();
        assert_eq!(
            url.as_str(),
            "https://meet.proton.me/meet/api/.well-known/cks"
        );
    }

    #[unified_test]
    async fn test_build_http_url_with_trailing_slash() {
        let client = create_test_client("meet.proton.me/meet/api/").await;

        let url = client.build_http_url("v1/groupInfo").unwrap();
        assert_eq!(url.as_str(), "https://meet.proton.me/meet/api/v1/groupInfo");
    }

    #[unified_test]
    async fn test_build_http_url_with_explicit_https() {
        let client = create_test_client("https://meet.proton.me/meet/api").await;

        let url = client.build_http_url("v1/groupInfo").unwrap();
        assert_eq!(url.as_str(), "https://meet.proton.me/meet/api/v1/groupInfo");
    }

    #[unified_test]
    async fn test_mls_session_stores_client_spec() {
        let config = ApiConfig {
            spec: (
                "macos-meet@9.8.7".to_string(),
                "ProtonMeet/1.0 (macOS 14.0; MacBookPro)".to_string(),
            ),
            auth: None,
            url_prefix: None,
            env: None,
            proxy: None,
        };
        let client = ProtonHttpClient::new(
            config,
            AuthStore::prod(),
            "meet.proton.me/meet/api".to_string(),
        )
        .await
        .expect("client should build");
        assert_eq!(client.app_version, "macos-meet@9.8.7");
        assert_eq!(client.user_agent, "ProtonMeet/1.0 (macOS 14.0; MacBookPro)");
    }

    #[unified_test]
    async fn test_mls_session_uses_pinning_for_prod_env() {
        let config = ApiConfig {
            spec: ("macos-meet@0.0.1".to_string(), "test-agent".to_string()),
            auth: None,
            url_prefix: None,
            env: None,
            proxy: None,
        };
        let client = ProtonHttpClient::new(
            config,
            AuthStore::prod(),
            "meet.proton.me/meet/api".to_string(),
        )
        .await;
        assert!(
            client.is_ok(),
            "prod env should build successfully: {:?}",
            client.err()
        );
    }

    #[unified_test]
    async fn test_mls_session_uses_pinning_for_explicit_prod_env() {
        let config = ApiConfig {
            spec: ("macos-meet@0.0.1".to_string(), "test-agent".to_string()),
            auth: None,
            url_prefix: None,
            env: Some("prod".to_string()),
            proxy: None,
        };
        let client = ProtonHttpClient::new(
            config,
            AuthStore::prod(),
            "meet.proton.me/meet/api".to_string(),
        )
        .await;
        assert!(
            client.is_ok(),
            "explicit prod env should build: {:?}",
            client.err()
        );
    }

    #[unified_test]
    async fn test_mls_session_skips_pinning_for_atlas_env() {
        let config = ApiConfig {
            spec: ("macos-meet@0.0.1".to_string(), "test-agent".to_string()),
            auth: None,
            url_prefix: None,
            env: Some("atlas".to_string()),
            proxy: None,
        };
        let client = ProtonHttpClient::new(
            config,
            AuthStore::atlas(None),
            "meet-mls.proton.black".to_string(),
        )
        .await;
        assert!(client.is_ok(), "atlas env should build: {:?}", client.err());
    }

    #[unified_test]
    async fn test_mls_session_skips_pinning_for_custom_url_env() {
        let config = ApiConfig {
            spec: ("macos-meet@0.0.1".to_string(), "test-agent".to_string()),
            auth: None,
            url_prefix: None,
            env: Some("https://localhost:8080".to_string()),
            proxy: None,
        };
        let client = ProtonHttpClient::new(
            config,
            AuthStore::from_custom_env_str(
                "https://localhost:8080".to_string(),
                Arc::new(tokio::sync::Mutex::new(Auth::None)),
            ),
            "localhost:8080".to_string(),
        )
        .await;
        assert!(
            client.is_ok(),
            "custom URL env should build: {:?}",
            client.err()
        );
    }

    #[test]
    fn test_prod_tls_config_contains_pinning_verifier() {
        #[cfg(not(target_family = "wasm"))]
        {
            use crate::infra::tls_pinning::build_prod_tls_config;
            let config = build_prod_tls_config().expect("prod TLS config should build");
            let debug_str = format!("{config:?}");
            assert!(
                debug_str.contains("CertPinningVerifier"),
                "prod TLS config should use CertPinningVerifier, got: {debug_str}"
            );
        }
    }
}
