use mls_spec::drafts::ratchet_tree_options::RatchetTreeOption;
use mls_spec::messages::MlsMessage;
use mls_spec::{Parsable, Serializable};
use proton_meet_macro::async_trait;
use serde::{Deserialize, Serialize};

use crate::domain::user::ports::{AgentKeyPackage, MlsApi};
use crate::errors::http_client::HttpClientError;
use crate::infra::dto::access_token::{GetSdCwtRequest, GetSdCwtResponse};
use crate::infra::dto::common::ApiResponse;
use crate::infra::dto::realtime::{
    GroupInfoSummaryData, GroupInfoVersion, MlsCommitInfo, MlsProposalInfo, RTCMessageIn,
    RTCMessageInContent, RatchetTreeAndGroupInfo, ServiceMetricsRequest, VersionedGroupInfoData,
};
use crate::infra::group_info_payload::{
    UpdateGroupInfoRequest, compress_group_info_json, serialize_update_group_info_request,
};
use crate::infra::http_client::ProtonHttpClient;
use crate::infra::mls_response_ext::{MlsResponseExt, mls_error_for_status};

#[async_trait]
impl MlsApi for ProtonHttpClient {
    async fn get_group_info(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<VersionedGroupInfoData, HttpClientError> {
        let url = self.build_http_url("v1/groupInfo")?;
        let response = self
            .send_mls(self.mls_session().get(url).bearer_auth(base64_sd_kbt))
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
            .send_mls(self.mls_session().get(url).bearer_auth(base64_sd_kbt))
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
            let mut messages = Vec::with_capacity(proposals.len());
            messages.extend(proposals.into_iter().filter_map(|proposal| {
                let rtc_message_in = RTCMessageIn {
                    content: RTCMessageInContent::Proposal(proposal),
                };
                rtc_message_in.to_tls_bytes().ok()
            }));
            messages
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
        let compressed_data =
            compress_group_info_json(&data).map_err(|e| HttpClientError::MlsHttpError {
                message: e.to_string(),
            })?;

        #[cfg(debug_assertions)]
        {
            let uncompressed_size = data.len();
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
            .send_mls(
                self.mls_session()
                    .post(url)
                    .header("Content-Type", "application/json")
                    .header("Content-Encoding", "zstd; q=3")
                    .body(compressed_data)
                    .bearer_auth(base64_sd_kbt),
            )
            .await?;

        response.ensure_success().await?;
        Ok(())
    }

    async fn join_group_by_proposal(
        &self,
        base64_sd_kbt: &str,
        external_proposal: &MlsMessage,
    ) -> Result<(), HttpClientError> {
        let encoded_proposal = external_proposal.to_tls_bytes()?;
        #[derive(Serialize)]
        #[serde(rename_all = "PascalCase")]
        struct JoinGroupByProposalRequest {
            proposal: Vec<u8>,
        }
        let join_group_by_proposal_request = JoinGroupByProposalRequest {
            proposal: encoded_proposal,
        };
        let url = self.build_http_url("v1/join")?;
        let response = self
            .send_mls(
                self.mls_session()
                    .post(url)
                    .json(&join_group_by_proposal_request)
                    .bearer_auth(base64_sd_kbt),
            )
            .await
            .inspect_err(|e| {
                #[cfg(target_family = "wasm")]
                log::info!("Failed to join group by proposal inside: {e:?}\n");
                #[cfg(not(target_family = "wasm"))]
                tracing::info!("Failed to join group by proposal inside: {e:?}\n");
            })?;
        response.ensure_success().await?;

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
            .send_mls(
                self.mls_session()
                    .post(url)
                    .header("Content-Type", "application/octet-stream")
                    .bearer_auth(base64_sd_kbt)
                    .body(encrypted_key_package.to_vec()),
            )
            .await?;

        let status = response.status();
        if status == reqwest::StatusCode::ACCEPTED {
            let data = response.parse_response::<SubmitJoinRequestData>().await?;
            return Ok(data.request_id);
        }

        let body_bytes = response.body_bytes().await?;
        if !status.is_success() {
            return Err(mls_error_for_status(status, &body_bytes));
        }

        if let Ok(api_response) =
            serde_json::from_slice::<ApiResponse<SubmitJoinRequestData>>(&body_bytes)
            && !api_response.success
        {
            return Err(HttpClientError::MlsResponseError {
                status,
                details: None,
                message: api_response
                    .error
                    .unwrap_or_else(|| "Join request rejected".into()),
            });
        }

        let parsed = crate::errors::http_client::response_error_from_api_failure_body(
            &body_bytes,
            status.as_u16(),
        );
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
            .send_mls(
                self.mls_session()
                    .post(url)
                    .header("Content-Type", "application/json")
                    .bearer_auth(base64_sd_kbt)
                    .body(serde_json::to_vec(&body).map_err(|e| {
                        HttpClientError::MlsDeserializeError {
                            status: reqwest::StatusCode::INTERNAL_SERVER_ERROR,
                            details: None,
                            message: e.to_string(),
                        }
                    })?),
            )
            .await?;

        response.ensure_success().await?;
        Ok(())
    }

    async fn cancel_join_request(
        &self,
        base64_sd_kbt: &str,
        meeting_link_name: &str,
    ) -> Result<(), HttpClientError> {
        let url = self.build_http_url(&format!("v1/joinRequest/{meeting_link_name}"))?;

        let response = self
            .send_mls(self.mls_session().delete(url).bearer_auth(base64_sd_kbt))
            .await?;

        if response.status() == reqwest::StatusCode::NOT_FOUND {
            return Ok(());
        }

        response.ensure_success().await?;
        Ok(())
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
            .send_mls(
                self.mls_session()
                    .post(url)
                    .json(&GetSdCwtRequest {
                        meet_link_name,
                        holder_confirmation_key: base64_holder_confirmation_key,
                        session_id,
                    })
                    .bearer_auth(access_token),
            )
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
        use base64::Engine as _;
        use base64::engine::general_purpose::STANDARD as B64;

        let url = self.build_http_url("v1/agent/bundle")?;

        #[derive(Serialize)]
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

        let response = self
            .send_mls(
                self.mls_session()
                    .post(url)
                    .bearer_auth(base64_sd_kbt)
                    .json(&body),
            )
            .await?;
        response.ensure_success().await?;
        Ok(())
    }

    async fn fetch_agent_keypackage(
        &self,
        base64_sd_kbt: &str,
        agent_device_id: &str,
    ) -> Result<AgentKeyPackage, HttpClientError> {
        use base64::Engine as _;
        use base64::engine::general_purpose::STANDARD as B64;

        let mut url = self.build_http_url("v1/agent/keypackage")?;
        url.query_pairs_mut()
            .append_pair("agent_device_id", agent_device_id);

        #[derive(Deserialize)]
        #[serde(rename_all = "PascalCase")]
        struct KpResp {
            key_package: String,
            hpke_public_key: String,
        }

        let response = self
            .send_mls(self.mls_session().get(url).bearer_auth(base64_sd_kbt))
            .await?;
        let resp = response.parse_api_response::<KpResp>().await?;

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

        let response = self
            .send_mls(self.mls_session().get(url).bearer_auth(base64_sd_kbt))
            .await?;
        let resp = response.parse_api_response::<ListResp>().await?;
        Ok(resp.device_ids)
    }

    async fn fetch_external_sender(&self) -> Result<Vec<u8>, HttpClientError> {
        if let Some(cached) = self.external_sender_cache().read().await.as_ref() {
            return Ok(cached.clone());
        }

        let url = self.build_http_url(".well-known/external-sender")?;
        let response = self
            .send_mls(self.mls_session().get(url))
            .await
            .map_err(|e| {
                tracing::info!("Failed to fetch external sender inside: {:?}\n", e);
                e
            })?;
        let external_sender_certs = response.success_bytes().await?;

        if external_sender_certs.is_empty() {
            tracing::warn!("External sender response is empty; skipping cache to allow retry");
            return Ok(external_sender_certs);
        }

        *self.external_sender_cache().write().await = Some(external_sender_certs.clone());

        Ok(external_sender_certs)
    }

    async fn fetch_cose_key_set(&self) -> Result<Vec<u8>, HttpClientError> {
        if let Some(cached) = self.cks_cache().read().await.as_ref() {
            return Ok(cached.clone());
        }

        let url = self.build_http_url(".well-known/cks")?;
        let response = self
            .send_mls(self.mls_session().get(url))
            .await
            .map_err(|e| {
                tracing::info!("Failed to fetch cose key set inside: {:?}\n", e);
                e
            })?;
        let cks_bytes = response.success_bytes().await?;

        *self.cks_cache().write().await = Some(cks_bytes.clone());

        Ok(cks_bytes)
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
            .send_mls(
                self.mls_session()
                    .post(url)
                    .json(metrics_request)
                    .bearer_auth(base64_sd_kbt),
            )
            .await?;
        response.ensure_success().await?;
        Ok(())
    }
}

#[derive(Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct GroupInfoResponse {
    pub meeting_id: String,
    pub data: Option<Vec<u8>>,
    pub epoch: Option<u64>,
    pub group_id: Option<Vec<u8>>,
    pub version: Option<u32>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn api_response_into_data_returns_success_payload() {
        let json = r#"{"success":true,"data":{"value":7}}"#;
        let response: ApiResponse<serde_json::Value> = serde_json::from_str(json).unwrap();
        let data = response.into_data().unwrap();
        assert_eq!(data["value"], 7);
    }
}
