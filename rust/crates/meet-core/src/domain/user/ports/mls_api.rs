use crate::errors::http_client::HttpClientError;
use crate::infra::dto::realtime::{
    GroupInfoSummaryData, MlsCommitInfo, MlsProposalInfo, ServiceMetricsRequest,
    VersionedGroupInfoData,
};
use mls_spec::{drafts::ratchet_tree_options::RatchetTreeOption, messages::MlsMessage};
use proton_meet_macro::async_trait_with_mock;

/// An agent's uploaded KeyPackage, decoded to raw bytes by the HTTP impl.
#[derive(Debug, Clone)]
pub struct AgentKeyPackage {
    pub key_package: Vec<u8>,
    pub hpke_public_key: Vec<u8>,
}

/// HTTP API used by the MLS service.
#[async_trait_with_mock]
pub trait MlsApi: Send + Sync {
    async fn get_group_info(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<VersionedGroupInfoData, HttpClientError>;

    async fn get_group_info_summary(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<GroupInfoSummaryData, HttpClientError>;

    async fn update_group_info(
        &self,
        base64_sd_kbt: &str,
        mls_message: &MlsMessage,
        ratchet_tree: &RatchetTreeOption,
        mls_commit_info: Option<&MlsCommitInfo>,
        proposals: Option<Vec<MlsProposalInfo>>,
    ) -> Result<(), HttpClientError>;

    async fn join_group_by_proposal(
        &self,
        base64_sd_kbt: &str,
        mls_message: &MlsMessage,
    ) -> Result<(), HttpClientError>;

    async fn submit_join_request(
        &self,
        base64_sd_kbt: &str,
        meeting_link_name: &str,
        encrypted_key_package: &[u8],
    ) -> Result<String, HttpClientError>;

    async fn reject_join_request(
        &self,
        base64_sd_kbt: &str,
        meeting_link_name: &str,
        request_id: &str,
        participant_uid: &str,
    ) -> Result<(), HttpClientError>;

    /// Guest cancels their outstanding waiting-room join request.
    /// The server derives `participant_uid` from the SD-CWT; no body is sent.
    async fn cancel_join_request(
        &self,
        base64_sd_kbt: &str,
        meeting_link_name: &str,
    ) -> Result<(), HttpClientError>;

    async fn fetch_sd_cwt(
        &self,
        meet_link_name: &str,
        access_token: &str,
        base64_holder_confirmation_key: &str,
        session_id: Option<&str>,
    ) -> Result<String, HttpClientError>;

    async fn fetch_cose_key_set(&self) -> Result<Vec<u8>, HttpClientError>;

    async fn fetch_external_sender(&self) -> Result<Vec<u8>, HttpClientError>;

    /// `POST /v1/agent/bundle`: push the encrypted agent bundle.
    async fn post_agent_bundle(
        &self,
        base64_sd_kbt: &str,
        agent_device_id: &str,
        psk_id: &[u8],
        encrypted_psk: &[u8],
        welcome: &[u8],
        ratchet_tree: &[u8],
    ) -> Result<(), HttpClientError>;

    /// `GET /v1/agent/keypackage?agent_device_id=...`: fetch the agent KeyPackage.
    async fn fetch_agent_keypackage(
        &self,
        base64_sd_kbt: &str,
        agent_device_id: &str,
    ) -> Result<AgentKeyPackage, HttpClientError>;

    /// `GET /v1/agent/keypackages`: list the uploaded agent device IDs.
    async fn list_agent_keypackages(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<Vec<String>, HttpClientError>;

    async fn send_metrics(
        &self,
        base64_sd_kbt: &str,
        app_version: &str,
        user_agent: &str,
        metrics_request: &ServiceMetricsRequest,
    ) -> Result<(), HttpClientError>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use mls_spec::Parsable;
    use proton_meet_macro::unified_test;
    use std::sync::LazyLock;

    const TEST_KBT: &str = "base64-sd-kbt";
    const TEST_LINK: &str = "test-meet-link";
    const TEST_TOKEN: &str = "access-token";

    fn placeholder_mls_message() -> MlsMessage {
        static MSG: LazyLock<MlsMessage> = LazyLock::new(|| {
            MlsMessage::from_tls_bytes(crate::mocks::HTTP_CLIENT_GROUP_INFO_TLS)
                .expect("port test group info fixture")
        });
        MSG.clone()
    }

    fn sample_versioned_group_info() -> VersionedGroupInfoData {
        VersionedGroupInfoData {
            version: crate::infra::dto::realtime::GroupInfoVersion::V1,
            data: crate::infra::dto::realtime::RatchetTreeAndGroupInfo {
                ratchet_tree: RatchetTreeOption::DistributionService,
                group_info: placeholder_mls_message(),
            },
        }
    }

    fn sample_ratchet_tree() -> RatchetTreeOption {
        RatchetTreeOption::DistributionService
    }

    fn empty_metrics_request() -> ServiceMetricsRequest {
        ServiceMetricsRequest {
            user_join_time: None,
            user_retry_count: None,
            error_code: None,
            connection_lost: None,
            user_epoch_health: None,
            designated_committer: None,
            user_rejoin: None,
        }
    }

    #[unified_test]
    async fn get_group_info_success() {
        let versioned = sample_versioned_group_info();
        let mut mock = MockMlsApi::new();
        let expected = versioned.clone();
        mock.expect_get_group_info()
            .withf(|kbt| kbt == TEST_KBT)
            .returning(move |_| {
                let value = expected.clone();
                Box::pin(async move { Ok(value) })
            });

        let result = mock.get_group_info(TEST_KBT).await.unwrap();
        assert_eq!(
            result.version,
            crate::infra::dto::realtime::GroupInfoVersion::V1
        );
        assert_eq!(result.data.group_info, versioned.data.group_info);
        assert!(matches!(
            result.data.ratchet_tree,
            RatchetTreeOption::DistributionService
        ));
    }

    #[unified_test]
    async fn get_group_info_summary_success() {
        let summary = GroupInfoSummaryData {
            epoch: 7,
            group_id: vec![1, 2, 3],
        };
        let mut mock = MockMlsApi::new();
        let expected = summary.clone();
        mock.expect_get_group_info_summary()
            .withf(|kbt| kbt == TEST_KBT)
            .returning(move |_| {
                let value = expected.clone();
                Box::pin(async move { Ok(value) })
            });

        let result = mock.get_group_info_summary(TEST_KBT).await.unwrap();
        assert_eq!(result.epoch, 7);
        assert_eq!(result.group_id, vec![1, 2, 3]);
    }

    #[unified_test]
    async fn update_group_info_success() {
        let group_info = placeholder_mls_message();
        let ratchet = sample_ratchet_tree();
        let mut mock = MockMlsApi::new();
        mock.expect_update_group_info()
            .withf(|kbt, _, _, _, _| kbt == TEST_KBT)
            .returning(|_, _, _, _, _| Box::pin(async { Ok(()) }));

        mock.update_group_info(TEST_KBT, &group_info, &ratchet, None, None)
            .await
            .unwrap();
    }

    #[unified_test]
    async fn join_group_by_proposal_success() {
        let group_info = placeholder_mls_message();
        let mut mock = MockMlsApi::new();
        mock.expect_join_group_by_proposal()
            .withf(|kbt, _| kbt == TEST_KBT)
            .returning(|_, _| Box::pin(async { Ok(()) }));

        mock.join_group_by_proposal(TEST_KBT, &group_info)
            .await
            .unwrap();
    }

    #[unified_test]
    async fn fetch_sd_cwt_success() {
        let mut mock = MockMlsApi::new();
        mock.expect_fetch_sd_cwt()
            .withf(|link, token, key, session| {
                link == TEST_LINK
                    && token == TEST_TOKEN
                    && key == "holder-key"
                    && session == &Some("session-id")
            })
            .returning(|_, _, _, _| Box::pin(async { Ok("sd-cwt".to_string()) }));

        let result = mock
            .fetch_sd_cwt(TEST_LINK, TEST_TOKEN, "holder-key", Some("session-id"))
            .await
            .unwrap();
        assert_eq!(result, "sd-cwt");
    }

    #[unified_test]
    async fn fetch_cose_key_set_success() {
        let mut mock = MockMlsApi::new();
        mock.expect_fetch_cose_key_set()
            .returning(|| Box::pin(async { Ok(vec![1, 2, 3]) }));

        assert_eq!(mock.fetch_cose_key_set().await.unwrap(), vec![1, 2, 3]);
    }

    #[unified_test]
    async fn send_metrics_success() {
        let metrics = empty_metrics_request();
        let mut mock = MockMlsApi::new();
        mock.expect_send_metrics()
            .withf(|kbt, version, agent, _| {
                kbt == TEST_KBT && version == "1.0.0" && agent == "test-agent"
            })
            .returning(|_, _, _, _| Box::pin(async { Ok(()) }));

        mock.send_metrics(TEST_KBT, "1.0.0", "test-agent", &metrics)
            .await
            .unwrap();
    }

    #[unified_test]
    async fn fetch_external_sender_success() {
        let mut mock = MockMlsApi::new();
        mock.expect_fetch_external_sender()
            .returning(|| Box::pin(async { Ok(vec![9, 8, 7]) }));

        assert_eq!(mock.fetch_external_sender().await.unwrap(), vec![9, 8, 7]);
    }
}
