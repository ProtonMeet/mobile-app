use meet_type::fanout::GroupInfoSummaryData;
use mls_spec::drafts::ratchet_tree_options::RatchetTreeOption;
use mls_spec::messages::MlsMessage;
use mls_spec::{Parsable, Serializable};
use muon::auth::Auth;
use muon::common::sdk::Sdk;
#[cfg(not(target_family = "wasm"))]
use muon::common::Scheme;
use muon::{App, ProtonRequest, ProtonResponse};

use proton_meet_macro::async_trait;
use serde::{Deserialize, Serialize};

use crate::domain::user::models::login::Modulus;
use crate::domain::user::models::meet_link_info::{
    AccessTokenInfo, MeetLinkAuthInfo, MeetLinkInfo, MeetParticipant,
};
use crate::domain::user::models::meeting::{Meeting, MeetingInfo};
use crate::domain::user::models::participant_track_settings::ParticipantTrackSettings;
use crate::domain::user::models::user_settings::UserSettings;
use crate::domain::user::ports::{AgentKeyPackage, HttpClient};
use crate::errors::http_client::HttpClientError;
use crate::infra::dto::access_token::{
    AccessTokenRequest, AccessTokenResponse, GetSdCwtRequest, GetSdCwtResponse,
};
use crate::infra::dto::login::GetModulusResponse;
use crate::infra::dto::meet_link_info::{
    AuthMeetLinkRequest, AuthMeetLinkResponse, MeetInfoResponse, MeetLinkInfoResponse,
    MeetParticipantsCountResponse, MeetParticipantsResponse,
};
use crate::infra::dto::meeting::ActiveMeetingsResponse;
use crate::infra::dto::participant_track_settings::{
    ParticipantTrackSettingsRequest, ParticipantTrackSettingsResponse,
};
use crate::infra::dto::realtime::{
    GroupInfoVersion, MlsCommitInfo, MlsProposalInfo, RTCMessageIn, RTCMessageInContent,
    RatchetTreeAndGroupInfo, ServiceMetricsRequest, VersionedGroupInfoData,
};
use crate::infra::dto::remove_participant::{RemoveParticipantRequest, RemoveParticipantResponse};
use crate::infra::dto::user_settings::UserSettingsResponse;
use crate::infra::group_info_payload::{
    compress_group_info_json, serialize_update_group_info_request, UpdateGroupInfoRequest,
};
use crate::infra::http_client_util::HttpClientUtil;
use crate::infra::mls_response_ext::MlsResponseExt;
#[cfg(target_arch = "wasm32")]
use crate::infra::muon::environment_from_str;
#[cfg(all(not(target_family = "wasm"), not(feature = "insecure-tls")))]
use crate::infra::muon::is_prod_environment;
use crate::infra::muon::{
    build_meet_client, meet_sdk_from_app, MeetClient, MeetClientExt, MeetSession,
};
#[cfg(not(target_arch = "wasm32"))]
use crate::infra::muon::{AuthStore, SharedAuth};
use crate::infra::proton_response_ext::ProtonResponseExt;
use reqwest;
use reqwest::header::{HeaderMap, HeaderValue, USER_AGENT};
use std::sync::{Arc, Mutex};
use tokio::sync::RwLock;
use url::Url;

/// Error code returned by the API when the meeting link is locked
const MEETING_LOCKED_ERROR_CODE: u16 = 2502;

/// Error code returned by the API when SRP parameters are invalid — i.e. the
/// URL/custom password the caller supplied does not match the meeting link.
const INVALID_SRP_PARAMS_ERROR_CODE: u16 = 2026;

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
}

impl ProtonHttpClient {
    /// Helper function to build a URL from http_host and a path
    fn build_http_url(&self, path: &str) -> Result<Url, HttpClientError> {
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
        res.map_err(HttpClientError::from)
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
            mls_builder.default_headers(mls_default_headers).build()?
        };

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
        })
    }
}

#[async_trait]
impl HttpClient for ProtonHttpClient {
    fn get_session(&self) -> MeetSession {
        ProtonHttpClient::get_session(self)
    }

    async fn get_group_info(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<VersionedGroupInfoData, HttpClientError> {
        let url = self.build_http_url("v1/groupInfo")?;

        let response = self
            .mls_session
            .get(url)
            .header("Authorization", format!("Bearer {base64_sd_kbt}"))
            .send()
            .await?;

        let response = response.parse_response::<GroupInfoResponse>().await?;
        let ratchet_tree_and_group_info = if let Some(data) = response.data {
            RatchetTreeAndGroupInfo::from_tls_bytes(&data)?
        } else {
            return Err(HttpClientError::GroupInfoEmpty);
        };
        let version = response.version.ok_or(HttpClientError::GroupInfoEmpty)?;
        let result = VersionedGroupInfoData {
            version: GroupInfoVersion::try_from(version)?,
            data: ratchet_tree_and_group_info,
        };
        Ok(result)
    }

    async fn get_group_info_summary(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<GroupInfoSummaryData, HttpClientError> {
        let mut url = self.build_http_url("v1/groupInfo")?;
        url.query_pairs_mut().append_pair("summary", "true");

        let response = self
            .mls_session
            .get(url)
            .header("Authorization", format!("Bearer {base64_sd_kbt}"))
            .send()
            .await?;

        let response = response.parse_response::<GroupInfoResponse>().await?;
        let epoch = response
            .epoch
            .ok_or(HttpClientError::GroupInfoSummaryEmpty)?;
        let group_id = response
            .group_id
            .ok_or(HttpClientError::GroupInfoSummaryEmpty)?;

        Ok(GroupInfoSummaryData { epoch, group_id })
    }

    async fn update_group_info(
        &self,
        base64_sd_kbt: &str,
        mls_message: &MlsMessage,
        ratchet_tree: &RatchetTreeOption,
        mls_commit_info: Option<&MlsCommitInfo>,
        proposals: Option<Vec<MlsProposalInfo>>,
    ) -> Result<(), HttpClientError> {
        // Create a properly formatted URL
        let url = self.build_http_url("v1/groupInfo")?;

        let commit_data = {
            if let Some(mls_commit_info) = mls_commit_info {
                let rtc_message_in = RTCMessageIn {
                    content: RTCMessageInContent::SendCommit(mls_commit_info.clone()),
                };
                let encoded_payload = rtc_message_in.to_tls_bytes()?;
                Some(encoded_payload)
            } else {
                None
            }
        };

        let proposal_messages = proposals.map(|proposals| {
            proposals
                .iter()
                .flat_map(|proposal| {
                    let rtc_message_in = RTCMessageIn {
                        content: RTCMessageInContent::Proposal(proposal.clone()),
                    };
                    let encoded_payload = rtc_message_in.to_tls_bytes().ok()?;
                    Some(encoded_payload)
                })
                .collect()
        });

        let update_group_info_request = UpdateGroupInfoRequest {
            data: RatchetTreeAndGroupInfo {
                ratchet_tree: ratchet_tree.clone(),
                group_info: mls_message.clone(),
            }
            .to_tls_bytes()?,
            commit_data,
            proposals: proposal_messages,
        };

        let data =
            serialize_update_group_info_request(&update_group_info_request).map_err(|e| {
                HttpClientError::MlsHttpError {
                    message: e.to_string(),
                }
            })?;
        let uncompressed_size = data.len();

        let compressed_data =
            compress_group_info_json(&data).map_err(|e| HttpClientError::MlsHttpError {
                message: e.to_string(),
            })?;

        #[cfg(debug_assertions)]
        {
            let compression_ratio = if uncompressed_size > 0 {
                (compressed_data.len() as f64 / uncompressed_size as f64) * 100.0
            } else {
                0.0
            };
            tracing::info!(
                "update_group_info_request size: {} (compressed: {}, ratio: {:.1}%)",
                uncompressed_size,
                compressed_data.len(),
                compression_ratio
            );
        }

        let response = self
            .mls_session
            .post(url)
            .header("Content-Type", "application/json")
            .header("Content-Encoding", "zstd; q=3")
            .body(compressed_data)
            .header("Authorization", format!("Bearer {base64_sd_kbt}"))
            .send()
            .await?;

        // Check if the response was successful
        response.error_for_status()?;

        Ok(())
    }

    async fn join_group_by_proposal(
        &self,
        base64_sd_kbt: &str,
        external_proposal: &MlsMessage,
    ) -> Result<(), HttpClientError> {
        let encoded_proposal = external_proposal.to_tls_bytes()?;
        #[derive(Debug, Serialize)]
        #[serde(rename_all = "PascalCase")]
        struct JoinGroupByProposalRequest {
            proposal: Vec<u8>,
        }
        let join_group_by_proposal_request = JoinGroupByProposalRequest {
            proposal: encoded_proposal,
        };
        let url = self.build_http_url("v1/join")?;
        let response = self
            .mls_session
            .post(url)
            .json(&join_group_by_proposal_request)
            .header("Authorization", format!("Bearer {base64_sd_kbt}"))
            .send()
            .await
            .inspect_err(|e| {
                #[cfg(target_family = "wasm")]
                log::info!("Failed to join group by proposal inside: {e:?}\n");
                #[cfg(not(target_family = "wasm"))]
                tracing::info!("Failed to join group by proposal inside: {e:?}\n");
            })?;
        response.error_for_status()?;

        Ok(())
    }

    async fn submit_join_request(
        &self,
        base64_sd_kbt: &str,
        meeting_link_name: &str,
        encrypted_key_package: &[u8],
    ) -> Result<String, HttpClientError> {
        let url = self.build_http_url(&format!("v1/joinRequest/{meeting_link_name}"))?;

        #[derive(Debug, Deserialize)]
        struct SubmitJoinRequestData {
            request_id: String,
        }

        let response = self
            .mls_session
            .post(url)
            .header("Content-Type", "application/octet-stream")
            .header("Authorization", format!("Bearer {base64_sd_kbt}"))
            .body(encrypted_key_package.to_vec())
            .send()
            .await?;

        let status = response.status();
        if status == reqwest::StatusCode::ACCEPTED {
            let data = response.parse_response::<SubmitJoinRequestData>().await?;
            return Ok(data.request_id);
        }

        use crate::errors::http_client::response_error_from_api_failure_body;

        let body_bytes =
            response
                .bytes()
                .await
                .map_err(|err| HttpClientError::MlsDeserializeError {
                    status,
                    details: None,
                    message: err.to_string(),
                })?;

        if let Ok(api_response) =
            serde_json::from_slice::<ApiResponse<SubmitJoinRequestData>>(&body_bytes)
        {
            if !api_response.success {
                return Err(HttpClientError::MlsResponseError {
                    status,
                    details: None,
                    message: api_response
                        .error
                        .unwrap_or_else(|| "Join request rejected".into()),
                });
            }
        }

        let parsed = response_error_from_api_failure_body(&body_bytes, status.as_u16());
        Err(HttpClientError::MlsResponseError {
            status,
            message: parsed.error,
            details: Some(parsed.details.to_string()),
        })
    }

    async fn reject_join_request(
        &self,
        base64_sd_kbt: &str,
        meeting_link_name: &str,
        request_id: &str,
        participant_uid: &str,
    ) -> Result<(), HttpClientError> {
        let url = self.build_http_url(&format!("v1/joinRequest/{meeting_link_name}/reject"))?;

        #[derive(Serialize)]
        struct RejectJoinRequestBody<'a> {
            request_id: &'a str,
            participant_uid: &'a str,
        }

        let body = RejectJoinRequestBody {
            request_id,
            participant_uid,
        };

        let response = self
            .mls_session
            .post(url)
            .header("Content-Type", "application/json")
            .header("Authorization", format!("Bearer {base64_sd_kbt}"))
            .body(
                serde_json::to_vec(&body).map_err(|e| HttpClientError::MlsDeserializeError {
                    status: reqwest::StatusCode::INTERNAL_SERVER_ERROR,
                    details: None,
                    message: e.to_string(),
                })?,
            )
            .send()
            .await?;

        response.error_for_status()?;
        Ok(())
    }

    async fn cancel_join_request(
        &self,
        base64_sd_kbt: &str,
        meeting_link_name: &str,
    ) -> Result<(), HttpClientError> {
        let url = self.build_http_url(&format!("v1/joinRequest/{meeting_link_name}"))?;

        let response = self
            .mls_session
            .delete(url)
            .header("Authorization", format!("Bearer {base64_sd_kbt}"))
            .send()
            .await?;

        if response.status() == reqwest::StatusCode::NOT_FOUND {
            return Ok(());
        }

        response.error_for_status()?;
        Ok(())
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

    async fn fetch_sd_cwt(
        &self,
        meet_link_name: &str,
        access_token: &str,
        base64_holder_confirmation_key: &str,
        session_id: Option<&str>,
    ) -> Result<String, HttpClientError> {
        let url = self.build_http_url("v1/session")?;
        let response = self
            .mls_session
            .post(url)
            .json(&GetSdCwtRequest {
                meet_link_name: meet_link_name.to_string(),
                holder_confirmation_key: base64_holder_confirmation_key.to_string(),
                session_id: session_id.map(|s| s.to_string()),
            })
            .header("Authorization", format!("Bearer {access_token}"))
            .send()
            .await?;
        let response = response.parse_response::<GetSdCwtResponse>().await?;
        Ok(response.token)
    }

    async fn post_agent_bundle(
        &self,
        base64_sd_kbt: &str,
        agent_device_id: &str,
        psk_id: &[u8],
        encrypted_psk: &[u8],
        welcome: &[u8],
        ratchet_tree: &[u8],
    ) -> Result<(), HttpClientError> {
        use base64::engine::general_purpose::STANDARD as B64;
        use base64::Engine as _;

        let url = self.build_http_url("v1/agent/bundle")?;

        #[derive(Debug, Serialize)]
        #[serde(rename_all = "PascalCase")]
        struct PushAgentBundleRequest<'a> {
            agent_device_id: &'a str,
            psk_id: String,
            encrypted_psk: String,
            welcome: String,
            ratchet_tree: String,
        }

        let body = PushAgentBundleRequest {
            agent_device_id,
            psk_id: B64.encode(psk_id),
            encrypted_psk: B64.encode(encrypted_psk),
            welcome: B64.encode(welcome),
            ratchet_tree: B64.encode(ratchet_tree),
        };

        self.mls_session
            .post(url)
            .bearer_auth(base64_sd_kbt)
            .json(&body)
            .send()
            .await?
            .error_for_status()?;
        Ok(())
    }

    async fn fetch_agent_keypackage(
        &self,
        base64_sd_kbt: &str,
        agent_device_id: &str,
    ) -> Result<AgentKeyPackage, HttpClientError> {
        use base64::engine::general_purpose::STANDARD as B64;
        use base64::Engine as _;

        let mut url = self.build_http_url("v1/agent/keypackage")?;
        url.query_pairs_mut()
            .append_pair("agent_device_id", agent_device_id);

        #[derive(Deserialize)]
        #[serde(rename_all = "PascalCase")]
        struct KpResp {
            key_package: String,
            hpke_public_key: String,
        }

        let resp: KpResp = self
            .mls_session
            .get(url)
            .bearer_auth(base64_sd_kbt)
            .send()
            .await?
            .error_for_status()?
            .json::<ApiResponse<KpResp>>()
            .await?
            .into_data()?;

        let decode = |field: &str, value: &str| {
            B64.decode(value)
                .map_err(|e| HttpClientError::MlsHttpError {
                    message: format!("agent keypackage: decode {field}: {e}"),
                })
        };
        Ok(AgentKeyPackage {
            key_package: decode("KeyPackage", &resp.key_package)?,
            hpke_public_key: decode("HpkePublicKey", &resp.hpke_public_key)?,
        })
    }

    async fn list_agent_keypackages(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<Vec<String>, HttpClientError> {
        let url = self.build_http_url("v1/agent/keypackages")?;

        #[derive(Deserialize)]
        #[serde(rename_all = "PascalCase")]
        struct ListResp {
            device_ids: Vec<String>,
        }

        let resp: ListResp = self
            .mls_session
            .get(url)
            .bearer_auth(base64_sd_kbt)
            .send()
            .await?
            .error_for_status()?
            .json::<ApiResponse<ListResp>>()
            .await?
            .into_data()?;
        Ok(resp.device_ids)
    }

    async fn fetch_external_sender(&self) -> Result<Vec<u8>, HttpClientError> {
        if let Some(cached) = self.external_sender_cache.read().await.as_ref() {
            return Ok(cached.clone());
        }

        let url = self.build_http_url(".well-known/external-sender")?;
        let response = self.mls_session.get(url).send().await.map_err(|e| {
            tracing::info!("Failed to fetch external sender inside: {:?}\n", e);
            e
        })?;
        let response = response.error_for_status()?;
        let external_sender_certs = response.bytes().await?;
        let external_sender_certs = external_sender_certs.to_vec();

        if external_sender_certs.is_empty() {
            tracing::warn!("External sender response is empty; skipping cache to allow retry");
            return Ok(external_sender_certs);
        }

        {
            let mut cache = self.external_sender_cache.write().await;
            *cache = Some(external_sender_certs.clone());
        }

        Ok(external_sender_certs)
    }

    async fn fetch_cose_key_set(&self) -> Result<Vec<u8>, HttpClientError> {
        if let Some(cached) = self.cks_cache.read().await.as_ref() {
            return Ok(cached.clone());
        }

        let url = self.build_http_url(".well-known/cks")?;
        let response = self.mls_session.get(url).send().await.map_err(|e| {
            tracing::info!("Failed to fetch cose key set inside: {:?}\n", e);
            e
        })?;
        let response = response.error_for_status()?;
        let cks_bytes = response.bytes().await?;
        let cks_bytes = cks_bytes.to_vec();

        {
            let mut cache = self.cks_cache.write().await;
            *cache = Some(cks_bytes.clone());
        }

        Ok(cks_bytes)
    }

    async fn get_modulus(&self) -> Result<Modulus, HttpClientError> {
        let req = self.get("/core/v4/auth/modulus");
        let res = self.send_session_request(req).await?;
        let modulus_res = res.parse_response::<GetModulusResponse>()?;
        Ok(modulus_res.into())
    }

    async fn send_metrics(
        &self,
        base64_sd_kbt: &str,
        _app_version: &str,
        _user_agent: &str,
        metrics_request: &ServiceMetricsRequest,
    ) -> Result<(), HttpClientError> {
        let url = self.build_http_url("v1/metrics")?;
        let response = self
            .mls_session
            .post(url)
            .json(metrics_request)
            .header("Authorization", format!("Bearer {base64_sd_kbt}"))
            .send()
            .await?;
        response.error_for_status()?;
        Ok(())
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

#[derive(Debug, Deserialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
}

impl<T> ApiResponse<T> {
    /// Unwrap the `{ success, data, error }` envelope into `data`, mapping a
    /// `success: false` or missing-`data` response to an `MlsHttpError`.
    fn into_data(self) -> Result<T, HttpClientError> {
        if !self.success {
            return Err(HttpClientError::MlsHttpError {
                message: self.error.unwrap_or_else(|| "request failed".to_string()),
            });
        }
        self.data.ok_or_else(|| HttpClientError::MlsHttpError {
            message: "response missing data".to_string(),
        })
    }

    fn into_ok(self) -> Result<(), HttpClientError> {
        if !self.success {
            return Err(HttpClientError::MlsHttpError {
                message: self.error.unwrap_or_else(|| "request failed".to_string()),
            });
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct GroupInfoResponse {
    pub meeting_id: String,
    pub data: Option<Vec<u8>>, // Serialized MLS data
    pub epoch: Option<u64>,
    pub group_id: Option<Vec<u8>>,
    pub version: Option<u32>,
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

    #[test]
    fn api_response_into_ok_accepts_success_true() {
        let json = r#"{"success":true}"#;
        let resp: ApiResponse<serde::de::IgnoredAny> = serde_json::from_str(json).unwrap();
        assert!(resp.into_ok().is_ok());
    }

    #[test]
    fn api_response_into_ok_rejects_success_false_with_server_error_message() {
        let json = r#"{"success":false,"error":"agent device unknown"}"#;
        let resp: ApiResponse<serde::de::IgnoredAny> = serde_json::from_str(json).unwrap();
        match resp.into_ok() {
            Err(HttpClientError::MlsHttpError { message }) => {
                assert_eq!(message, "agent device unknown");
            }
            other => panic!("expected MlsHttpError with server message, got {other:?}"),
        }
    }

    #[test]
    fn api_response_into_ok_rejects_success_false_with_no_error_field() {
        let json = r#"{"success":false}"#;
        let resp: ApiResponse<serde::de::IgnoredAny> = serde_json::from_str(json).unwrap();
        assert!(matches!(
            resp.into_ok(),
            Err(HttpClientError::MlsHttpError { .. })
        ));
    }
}
