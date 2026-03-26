use meet_type::fanout::GroupInfoSummaryData;
use mls_spec::drafts::ratchet_tree_options::RatchetTreeOption;
use mls_spec::messages::MlsMessage;
use mls_spec::{Parsable, Serializable};
#[cfg(not(target_family = "wasm"))]
use muon::common::{ConstProxy, Endpoint, Scheme};
use muon::store::Store;
use muon::{
    client::Auth,
    common::Host,
    store::DynStore,
    tls::{TlsCert, Verifier, VerifyRes},
    App, Client,
};

use proton_meet_macro::async_trait;
use serde::{Deserialize, Serialize};

use crate::domain::user::models::login::Modulus;
use crate::domain::user::models::meet_link_info::{
    AccessTokenInfo, MeetLinkAuthInfo, MeetLinkInfo, MeetParticipant,
};
use crate::domain::user::models::meeting::{Meeting, MeetingInfo};
use crate::domain::user::models::participant_track_settings::ParticipantTrackSettings;
use crate::domain::user::models::user_settings::UserSettings;
use crate::domain::user::ports::HttpClient;
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
use crate::infra::http_client_util::HttpClientUtil;
use crate::infra::mls_response_ext::MlsResponseExt;
use crate::infra::proton_response_ext::ProtonResponseExt;
use reqwest;
use std::sync::Arc;
use tokio::sync::RwLock;
use url::Url;

/// Error code returned by the API when the meeting link is locked
const MEETING_LOCKED_ERROR_CODE: u16 = 2502;

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
    /// The muon auth store. web doesn't need but flutter side needs
    pub store: Option<DynStore>,
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
    session: Client,
    http_host: String,
    mls_session: reqwest::Client,
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

    pub fn get_session(&self) -> Client {
        self.session.clone()
    }

    pub fn new(
        config: ApiConfig,
        auth_store: Box<dyn Store>,
        http_host: String,
    ) -> Result<Self, anyhow::Error> {
        let (app_version, user_agent) = config.spec;
        let app = App::new(app_version)?.with_user_agent(user_agent);

        #[cfg(not(target_family = "wasm"))]
        let mut builder = Client::builder(app, auth_store);
        #[cfg(target_family = "wasm")]
        let builder = Client::builder(app, auth_store);

        #[cfg(not(target_family = "wasm"))]
        if let Some(proxy) = &config.proxy {
            if let Ok(host) = Host::direct(proxy.host.clone()) {
                builder = builder.verifier(UnSafeVerifier);
                builder = builder.proxy(ConstProxy::new(Endpoint::new(
                    Scheme::Http,
                    host,
                    proxy.port,
                )));
            }
        }
        let session = builder.build()?;

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
                use muon::env::EnvId;

                let is_prod = match config.env.as_deref() {
                    None => true,
                    Some(s) => matches!(s.parse::<EnvId>(), Ok(EnvId::Prod)),
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
            mls_builder.build()?
        };

        #[cfg(target_family = "wasm")]
        let mls_session = reqwest::ClientBuilder::new().build()?;

        Ok(Self {
            session,
            http_host,
            mls_session,
            cks_cache: Arc::new(RwLock::new(None)),
            external_sender_cache: Arc::new(RwLock::new(None)),
        })
    }
}

#[async_trait]
impl HttpClient for ProtonHttpClient {
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

        #[derive(Debug, Serialize)]
        #[serde(rename_all = "PascalCase")]
        struct UpdateGroupInfoRequest {
            data: Vec<u8>,
            commit_data: Option<Vec<u8>>,
            proposals: Option<Vec<Vec<u8>>>,
        }

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

        let data = serde_json::to_vec(&update_group_info_request).map_err(|e| {
            HttpClientError::MlsHttpError {
                message: format!("Failed to serialize request: {e}"),
            }
        })?;
        let uncompressed_size = data.len();

        // Compress the JSON body with zstd
        let compressed_data =
            zstd::bulk::compress(&data, 3).map_err(|e| HttpClientError::MlsHttpError {
                message: format!("Failed to compress request: {e}"),
            })?;

        let compression_ratio = if uncompressed_size > 0 {
            (compressed_data.len() as f64 / uncompressed_size as f64) * 100.0
        } else {
            0.0
        };
        #[cfg(debug_assertions)]
        tracing::info!(
            "update_group_info_request size: {} (compressed: {}, ratio: {:.1}%)",
            uncompressed_size,
            compressed_data.len(),
            compression_ratio
        );

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

    async fn get_meet_link_info(
        &self,
        meet_link_name: &str,
    ) -> Result<MeetLinkInfo, HttpClientError> {
        let req = self.get(format!("/meet/v1/meetings/links/{meet_link_name}/info"));
        let res = self.get_session().send(req).await?;
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
        let res = self.get_session().send(req).await?;
        let participants_res = res.parse_response::<MeetParticipantsResponse>()?;
        Ok(participants_res.into())
    }

    async fn get_participants_count(&self, meet_link_name: &str) -> Result<u32, HttpClientError> {
        let req = self.get(format!(
            "/meet/v1/meetings/links/{meet_link_name}/participants/count"
        ));
        let res = self.get_session().send(req).await?;
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
        let res = self.get_session().send(req).await?;
        let auth_meet_link_res = res.parse_response::<AuthMeetLinkResponse>()?;
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
        let res = self.get_session().send(req).await?;

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
        let res = self.session.send(req).await?;
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
        let res = self.get_session().send(req).await?;
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
        let res = self.get_session().send(req).await?;
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
        let res = self.get_session().send(req).await?;
        let active_meetings_res = res.parse_response::<ActiveMeetingsResponse>()?;
        Ok(active_meetings_res
            .meetings
            .into_iter()
            .map(|m| m.try_into())
            .collect::<Result<Vec<Meeting>, _>>()?)
    }

    async fn get_user_settings(&self) -> Result<UserSettings, HttpClientError> {
        let req = self.get("/meet/v1/user-settings");
        let res = self.get_session().send(req).await?;
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
        let res = self.get_session().send(req).await?;
        let modulus_res = res.parse_response::<GetModulusResponse>()?;
        Ok(modulus_res.into())
    }

    async fn send_metrics(
        &self,
        base64_sd_kbt: &str,
        app_version: &str,
        user_agent: &str,
        metrics_request: &ServiceMetricsRequest,
    ) -> Result<(), HttpClientError> {
        let url = self.build_http_url("v1/metrics")?;
        let response = self
            .mls_session
            .post(url)
            .json(metrics_request)
            .header("X-App-Version", app_version)
            .header("User-Agent", user_agent)
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
        let res = self.get_session().send(req).await?;

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

/// An unsafe verifier that always makes Accept decisions.
#[derive(Debug)]
pub struct UnSafeVerifier;

impl Verifier for UnSafeVerifier {
    fn verify(&self, _: &Host, _: &TlsCert, _: &[TlsCert]) -> Result<VerifyRes, muon::Error> {
        if cfg!(feature = "allow-dangerous-env") {
            Ok(VerifyRes::Accept)
        } else {
            Ok(VerifyRes::Delegate)
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
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

#[cfg(test)]
mod tests {
    use super::*;
    use async_trait::async_trait;
    use muon::{env::EnvId, store::StoreError};

    #[derive(Debug)]
    struct MockStore;

    #[async_trait]
    impl Store for MockStore {
        fn env(&self) -> EnvId {
            EnvId::Prod
        }

        async fn get_auth(&self) -> Auth {
            Auth::None
        }

        async fn set_auth(&mut self, auth: Auth) -> Result<Auth, StoreError> {
            Ok(auth)
        }
    }

    fn create_test_client(http_host: &str) -> ProtonHttpClient {
        let config = ApiConfig {
            spec: ("macos-meet@0.0.1".to_string(), "test-agent".to_string()),
            auth: None,
            url_prefix: None,
            env: None,
            store: None,
            proxy: None,
        };

        ProtonHttpClient::new(config, Box::new(MockStore), http_host.to_string()).unwrap()
    }

    #[test]
    fn test_build_http_url_with_meet_proton_me() {
        let client = create_test_client("meet.proton.me/api");

        let url = client.build_http_url("v1/meetings").unwrap();
        assert_eq!(url.as_str(), "https://meet.proton.me/api/v1/meetings");
    }

    #[test]
    fn test_build_http_url_with_path() {
        let client = create_test_client("meet.proton.me/meet/api/");

        let url = client
            .build_http_url("v1/meetings/links/test/info")
            .unwrap();
        assert_eq!(
            url.as_str(),
            "https://meet.proton.me/meet/api/v1/meetings/links/test/info"
        );
    }

    #[test]
    fn test_build_http_url_with_mls_endpoints() {
        let client = create_test_client("meet.proton.me/meet/api");

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

    #[test]
    fn test_build_http_url_with_trailing_slash() {
        let client = create_test_client("meet.proton.me/meet/api/");

        let url = client.build_http_url("v1/groupInfo").unwrap();
        assert_eq!(url.as_str(), "https://meet.proton.me/meet/api/v1/groupInfo");
    }

    #[test]
    fn test_build_http_url_with_explicit_https() {
        let client = create_test_client("https://meet.proton.me/meet/api");

        let url = client.build_http_url("v1/groupInfo").unwrap();
        assert_eq!(url.as_str(), "https://meet.proton.me/meet/api/v1/groupInfo");
    }

    #[test]
    fn test_mls_session_uses_pinning_for_prod_env() {
        let config = ApiConfig {
            spec: ("macos-meet@0.0.1".to_string(), "test-agent".to_string()),
            auth: None,
            url_prefix: None,
            env: None,
            store: None,
            proxy: None,
        };
        let client = ProtonHttpClient::new(
            config,
            Box::new(MockStore),
            "meet.proton.me/meet/api".to_string(),
        );
        assert!(
            client.is_ok(),
            "prod env should build successfully: {:?}",
            client.err()
        );
    }

    #[test]
    fn test_mls_session_uses_pinning_for_explicit_prod_env() {
        let config = ApiConfig {
            spec: ("macos-meet@0.0.1".to_string(), "test-agent".to_string()),
            auth: None,
            url_prefix: None,
            env: Some("prod".to_string()),
            store: None,
            proxy: None,
        };
        let client = ProtonHttpClient::new(
            config,
            Box::new(MockStore),
            "meet.proton.me/meet/api".to_string(),
        );
        assert!(
            client.is_ok(),
            "explicit prod env should build: {:?}",
            client.err()
        );
    }

    #[test]
    fn test_mls_session_skips_pinning_for_atlas_env() {
        let config = ApiConfig {
            spec: ("macos-meet@0.0.1".to_string(), "test-agent".to_string()),
            auth: None,
            url_prefix: None,
            env: Some("atlas".to_string()),
            store: None,
            proxy: None,
        };
        let client = ProtonHttpClient::new(
            config,
            Box::new(MockStore),
            "meet-mls.proton.black".to_string(),
        );
        assert!(client.is_ok(), "atlas env should build: {:?}", client.err());
    }

    #[test]
    fn test_mls_session_skips_pinning_for_custom_url_env() {
        let config = ApiConfig {
            spec: ("macos-meet@0.0.1".to_string(), "test-agent".to_string()),
            auth: None,
            url_prefix: None,
            env: Some("https://localhost:8080".to_string()),
            store: None,
            proxy: None,
        };
        let client =
            ProtonHttpClient::new(config, Box::new(MockStore), "localhost:8080".to_string());
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
