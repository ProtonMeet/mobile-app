use crate::domain::user::models::meet_link_info::MeetParticipant;
use crate::domain::user::models::participant_track_settings::ParticipantTrackSettings;
use crate::domain::user::models::{
    login::Modulus,
    meet_link_info::{AccessTokenInfo, MeetLinkAuthInfo, MeetLinkInfo},
    meeting::{Meeting, MeetingInfo},
    user_settings::UserSettings,
};
#[cfg(test)]
use crate::domain::user::ports::mls_api::AgentKeyPackage;
use crate::domain::user::ports::mls_api::MlsApi;
use crate::errors::http_client::HttpClientError;
#[cfg(test)]
use crate::infra::dto::realtime::{
    GroupInfoSummaryData, MlsCommitInfo, MlsProposalInfo, ServiceMetricsRequest,
    VersionedGroupInfoData,
};
#[cfg(test)]
use mls_spec::{drafts::ratchet_tree_options::RatchetTreeOption, messages::MlsMessage};
#[cfg(test)]
use proton_meet_macro::async_trait;
#[cfg(test)]
use proton_meet_macro::async_trait_with_mock;

#[cfg_attr(target_family = "wasm", async_trait::async_trait(?Send))]
#[cfg_attr(not(target_family = "wasm"), async_trait::async_trait)]
pub trait HttpClient: MlsApi + Send + Sync {
    fn get_session(&self) -> crate::infra::muon::MeetSession;

    async fn auth_meet_link(
        &self,
        meet_link_name: &str,
        client_ephemeral: &str,
        client_proof: &str,
        srp_session: &str,
    ) -> Result<MeetLinkAuthInfo, HttpClientError>;

    async fn update_participant_track_settings(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
        audio_enabled: Option<u8>,
        video_enabled: Option<u8>,
    ) -> Result<ParticipantTrackSettings, HttpClientError>;

    async fn fetch_access_token(
        &self,
        meet_link_name: &str,
        display_name: &str,
        encrypted_display_name: &str,
    ) -> Result<AccessTokenInfo, HttpClientError>;

    async fn get_meet_info(&self, meet_link_name: &str) -> Result<MeetingInfo, HttpClientError>;

    async fn get_active_meetings(&self) -> Result<Vec<Meeting>, HttpClientError>;

    async fn get_user_settings(&self) -> Result<UserSettings, HttpClientError>;

    async fn get_meet_link_info(
        &self,
        meet_link_name: &str,
    ) -> Result<MeetLinkInfo, HttpClientError>;

    async fn get_participants(
        &self,
        meet_link_name: &str,
    ) -> Result<Vec<MeetParticipant>, HttpClientError>;

    async fn get_participants_count(&self, meet_link_name: &str) -> Result<u32, HttpClientError>;

    async fn get_modulus(&self) -> Result<Modulus, HttpClientError>;

    async fn remove_participant(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
    ) -> Result<(), HttpClientError>;

    /// Ping the server and return RTT in milliseconds
    async fn ping(&self) -> Result<u64, HttpClientError>;
}

#[cfg(test)]
// `mockall` does not synthesize expectations for inherited trait methods.
// Keep one generated test surface and bridge it to both production ports.
#[async_trait_with_mock]
pub trait HttpClientMethods: Send + Sync {
    fn get_session(&self) -> crate::infra::muon::MeetSession;

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

    async fn cancel_join_request(
        &self,
        base64_sd_kbt: &str,
        meeting_link_name: &str,
    ) -> Result<(), HttpClientError>;

    async fn auth_meet_link(
        &self,
        meet_link_name: &str,
        client_ephemeral: &str,
        client_proof: &str,
        srp_session: &str,
    ) -> Result<MeetLinkAuthInfo, HttpClientError>;

    async fn update_participant_track_settings(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
        audio_enabled: Option<u8>,
        video_enabled: Option<u8>,
    ) -> Result<ParticipantTrackSettings, HttpClientError>;

    async fn fetch_access_token(
        &self,
        meet_link_name: &str,
        display_name: &str,
        encrypted_display_name: &str,
    ) -> Result<AccessTokenInfo, HttpClientError>;

    async fn get_meet_info(&self, meet_link_name: &str) -> Result<MeetingInfo, HttpClientError>;

    async fn get_active_meetings(&self) -> Result<Vec<Meeting>, HttpClientError>;

    async fn get_user_settings(&self) -> Result<UserSettings, HttpClientError>;

    async fn fetch_sd_cwt(
        &self,
        meet_link_name: &str,
        access_token: &str,
        base64_holder_confirmation_key: &str,
        session_id: Option<&str>,
    ) -> Result<String, HttpClientError>;

    async fn fetch_cose_key_set(&self) -> Result<Vec<u8>, HttpClientError>;

    async fn get_meet_link_info(
        &self,
        meet_link_name: &str,
    ) -> Result<MeetLinkInfo, HttpClientError>;

    async fn get_participants(
        &self,
        meet_link_name: &str,
    ) -> Result<Vec<MeetParticipant>, HttpClientError>;

    async fn get_participants_count(&self, meet_link_name: &str) -> Result<u32, HttpClientError>;

    async fn get_modulus(&self) -> Result<Modulus, HttpClientError>;

    async fn remove_participant(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
    ) -> Result<(), HttpClientError>;

    async fn ping(&self) -> Result<u64, HttpClientError>;

    async fn fetch_external_sender(&self) -> Result<Vec<u8>, HttpClientError>;

    async fn post_agent_bundle(
        &self,
        base64_sd_kbt: &str,
        agent_device_id: &str,
        psk_id: &[u8],
        encrypted_psk: &[u8],
        welcome: &[u8],
        ratchet_tree: &[u8],
    ) -> Result<(), HttpClientError>;

    async fn fetch_agent_keypackage(
        &self,
        base64_sd_kbt: &str,
        agent_device_id: &str,
    ) -> Result<AgentKeyPackage, HttpClientError>;

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
pub type MockHttpClient = MockHttpClientMethods;

#[cfg(test)]
#[async_trait]
impl<T> MlsApi for T
where
    T: HttpClientMethods + Send + Sync,
{
    async fn get_group_info(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<VersionedGroupInfoData, HttpClientError> {
        HttpClientMethods::get_group_info(self, base64_sd_kbt).await
    }

    async fn get_group_info_summary(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<GroupInfoSummaryData, HttpClientError> {
        HttpClientMethods::get_group_info_summary(self, base64_sd_kbt).await
    }

    async fn update_group_info(
        &self,
        base64_sd_kbt: &str,
        mls_message: &MlsMessage,
        ratchet_tree: &RatchetTreeOption,
        mls_commit_info: Option<&MlsCommitInfo>,
        proposals: Option<Vec<MlsProposalInfo>>,
    ) -> Result<(), HttpClientError> {
        HttpClientMethods::update_group_info(
            self,
            base64_sd_kbt,
            mls_message,
            ratchet_tree,
            mls_commit_info,
            proposals,
        )
        .await
    }

    async fn join_group_by_proposal(
        &self,
        base64_sd_kbt: &str,
        mls_message: &MlsMessage,
    ) -> Result<(), HttpClientError> {
        HttpClientMethods::join_group_by_proposal(self, base64_sd_kbt, mls_message).await
    }

    async fn submit_join_request(
        &self,
        base64_sd_kbt: &str,
        meeting_link_name: &str,
        encrypted_key_package: &[u8],
    ) -> Result<String, HttpClientError> {
        HttpClientMethods::submit_join_request(
            self,
            base64_sd_kbt,
            meeting_link_name,
            encrypted_key_package,
        )
        .await
    }

    async fn reject_join_request(
        &self,
        base64_sd_kbt: &str,
        meeting_link_name: &str,
        request_id: &str,
        participant_uid: &str,
    ) -> Result<(), HttpClientError> {
        HttpClientMethods::reject_join_request(
            self,
            base64_sd_kbt,
            meeting_link_name,
            request_id,
            participant_uid,
        )
        .await
    }

    async fn cancel_join_request(
        &self,
        base64_sd_kbt: &str,
        meeting_link_name: &str,
    ) -> Result<(), HttpClientError> {
        HttpClientMethods::cancel_join_request(self, base64_sd_kbt, meeting_link_name).await
    }

    async fn fetch_sd_cwt(
        &self,
        meet_link_name: &str,
        access_token: &str,
        base64_holder_confirmation_key: &str,
        session_id: Option<&str>,
    ) -> Result<String, HttpClientError> {
        HttpClientMethods::fetch_sd_cwt(
            self,
            meet_link_name,
            access_token,
            base64_holder_confirmation_key,
            session_id,
        )
        .await
    }

    async fn fetch_cose_key_set(&self) -> Result<Vec<u8>, HttpClientError> {
        HttpClientMethods::fetch_cose_key_set(self).await
    }

    async fn fetch_external_sender(&self) -> Result<Vec<u8>, HttpClientError> {
        HttpClientMethods::fetch_external_sender(self).await
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
        HttpClientMethods::post_agent_bundle(
            self,
            base64_sd_kbt,
            agent_device_id,
            psk_id,
            encrypted_psk,
            welcome,
            ratchet_tree,
        )
        .await
    }

    async fn fetch_agent_keypackage(
        &self,
        base64_sd_kbt: &str,
        agent_device_id: &str,
    ) -> Result<AgentKeyPackage, HttpClientError> {
        HttpClientMethods::fetch_agent_keypackage(self, base64_sd_kbt, agent_device_id).await
    }

    async fn list_agent_keypackages(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<Vec<String>, HttpClientError> {
        HttpClientMethods::list_agent_keypackages(self, base64_sd_kbt).await
    }

    async fn send_metrics(
        &self,
        base64_sd_kbt: &str,
        app_version: &str,
        user_agent: &str,
        metrics_request: &ServiceMetricsRequest,
    ) -> Result<(), HttpClientError> {
        HttpClientMethods::send_metrics(
            self,
            base64_sd_kbt,
            app_version,
            user_agent,
            metrics_request,
        )
        .await
    }
}

#[cfg(test)]
#[async_trait]
impl<T> HttpClient for T
where
    T: HttpClientMethods + Send + Sync,
{
    fn get_session(&self) -> crate::infra::muon::MeetSession {
        HttpClientMethods::get_session(self)
    }

    async fn auth_meet_link(
        &self,
        meet_link_name: &str,
        client_ephemeral: &str,
        client_proof: &str,
        srp_session: &str,
    ) -> Result<MeetLinkAuthInfo, HttpClientError> {
        HttpClientMethods::auth_meet_link(
            self,
            meet_link_name,
            client_ephemeral,
            client_proof,
            srp_session,
        )
        .await
    }

    async fn update_participant_track_settings(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
        audio_enabled: Option<u8>,
        video_enabled: Option<u8>,
    ) -> Result<ParticipantTrackSettings, HttpClientError> {
        HttpClientMethods::update_participant_track_settings(
            self,
            meet_link_name,
            access_token,
            participant_uuid,
            audio_enabled,
            video_enabled,
        )
        .await
    }

    async fn fetch_access_token(
        &self,
        meet_link_name: &str,
        display_name: &str,
        encrypted_display_name: &str,
    ) -> Result<AccessTokenInfo, HttpClientError> {
        HttpClientMethods::fetch_access_token(
            self,
            meet_link_name,
            display_name,
            encrypted_display_name,
        )
        .await
    }

    async fn get_meet_info(&self, meet_link_name: &str) -> Result<MeetingInfo, HttpClientError> {
        HttpClientMethods::get_meet_info(self, meet_link_name).await
    }

    async fn get_active_meetings(&self) -> Result<Vec<Meeting>, HttpClientError> {
        HttpClientMethods::get_active_meetings(self).await
    }

    async fn get_user_settings(&self) -> Result<UserSettings, HttpClientError> {
        HttpClientMethods::get_user_settings(self).await
    }

    async fn get_meet_link_info(
        &self,
        meet_link_name: &str,
    ) -> Result<MeetLinkInfo, HttpClientError> {
        HttpClientMethods::get_meet_link_info(self, meet_link_name).await
    }

    async fn get_participants(
        &self,
        meet_link_name: &str,
    ) -> Result<Vec<MeetParticipant>, HttpClientError> {
        HttpClientMethods::get_participants(self, meet_link_name).await
    }

    async fn get_participants_count(&self, meet_link_name: &str) -> Result<u32, HttpClientError> {
        HttpClientMethods::get_participants_count(self, meet_link_name).await
    }

    async fn get_modulus(&self) -> Result<Modulus, HttpClientError> {
        HttpClientMethods::get_modulus(self).await
    }

    async fn remove_participant(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
    ) -> Result<(), HttpClientError> {
        HttpClientMethods::remove_participant(self, meet_link_name, access_token, participant_uuid)
            .await
    }

    async fn ping(&self) -> Result<u64, HttpClientError> {
        HttpClientMethods::ping(self).await
    }
}

#[cfg(test)]
mod tests {
    use proton_meet_macro::unified_test;

    use super::*;
    use crate::domain::user::models::meet_link_info::{
        AccessTokenInfo, MeetLinkAuthInfo, MeetLinkInfo,
    };
    use crate::domain::user::models::meeting::{Meeting, MeetingInfo};
    use crate::domain::user::models::participant_track_settings::ParticipantTrackSettings;
    use crate::domain::user::models::{login::Modulus, user_settings::UserSettings};
    use crate::errors::http_client::HttpClientError;
    const TEST_LINK: &str = "test-meet-link";
    const TEST_TOKEN: &str = "access-token";
    const TEST_PARTICIPANT: &str = "participant-uuid";

    fn sample_meet_link_info() -> MeetLinkInfo {
        MeetLinkInfo {
            modulus: "modulus".to_string(),
            salt: "salt".to_string(),
            server_ephemeral: "server-ephemeral".to_string(),
            srp_session: "srp-session".to_string(),
        }
    }

    fn sample_meet_link_auth() -> MeetLinkAuthInfo {
        MeetLinkAuthInfo {
            server_proof: "server-proof".to_string(),
            uid: "uid-123".to_string(),
            access_token: Some(TEST_TOKEN.to_string()),
        }
    }

    fn sample_access_token_info() -> AccessTokenInfo {
        AccessTokenInfo {
            access_token: TEST_TOKEN.to_string(),
            websocket_url: "wss://meet.proton.me/ws".to_string(),
        }
    }

    fn sample_meeting_info() -> MeetingInfo {
        MeetingInfo {
            meeting_link_name: TEST_LINK.to_string(),
            meeting_name: "encrypted-name".to_string(),
            salt: "salt".to_string(),
            session_key: "session-key".to_string(),
            locked: 0,
            max_duration: 3600,
            max_participants: 25,
            expiration_time: None,
            waiting_room: 0,
            manage_waiting_room: 0,
            personal_meeting: 0,
        }
    }

    fn sample_meeting() -> Meeting {
        Meeting {
            id: "meeting-id".to_string(),
            meeting_link_name: TEST_LINK.to_string(),
            meeting_name: "encrypted-name".to_string(),
            ..Default::default()
        }
    }

    fn sample_user_settings() -> UserSettings {
        UserSettings {
            meeting_id: "meeting-id".to_string(),
            address_id: "address-id".to_string(),
        }
    }

    fn sample_participant() -> MeetParticipant {
        MeetParticipant {
            participant_uuid: TEST_PARTICIPANT.to_string(),
            display_name: Some("Alice".to_string()),
            encrypted_display_name: None,
            can_subscribe: Some(1),
            can_publish: Some(1),
            can_publish_data: Some(1),
            is_admin: Some(0),
            is_host: Some(1),
        }
    }

    fn sample_track_settings() -> ParticipantTrackSettings {
        ParticipantTrackSettings { audio: 1, video: 0 }
    }

    fn sample_modulus() -> Modulus {
        Modulus {
            modulus_id: "modulus-id".to_string(),
            modulus: "modulus".to_string(),
        }
    }

    #[unified_test]
    async fn get_session_returns_bound_session() {
        use crate::infra::muon::support::test_support;

        let session = test_support::build_test_client_with_session().await;
        let session_key = session.session_key();
        let bound_session = session.clone();
        let mut mock = MockHttpClient::new();
        mock.expect_get_session()
            .times(1)
            .returning(move || bound_session.clone());

        let got = HttpClient::get_session(&mock);
        assert_eq!(got.session_key(), session_key);
    }

    #[unified_test]
    async fn auth_meet_link_success() {
        let auth = sample_meet_link_auth();
        let mut mock = MockHttpClient::new();
        let expected = auth.clone();
        mock.expect_auth_meet_link()
            .withf(|link, ep, proof, session| {
                link == TEST_LINK
                    && ep == "client-ephemeral"
                    && proof == "client-proof"
                    && session == "srp-session"
            })
            .returning(move |_, _, _, _| {
                let value = expected.clone();
                Box::pin(async move { Ok(value) })
            });

        let result = HttpClient::auth_meet_link(
            &mock,
            TEST_LINK,
            "client-ephemeral",
            "client-proof",
            "srp-session",
        )
        .await
        .unwrap();
        assert_eq!(result.uid, "uid-123");
    }

    #[unified_test]
    async fn update_participant_track_settings_success() {
        let settings = sample_track_settings();
        let mut mock = MockHttpClient::new();
        let expected = settings.clone();
        mock.expect_update_participant_track_settings()
            .withf(|link, token, uuid, audio, video| {
                link == TEST_LINK
                    && token == TEST_TOKEN
                    && uuid == TEST_PARTICIPANT
                    && *audio == Some(1)
                    && *video == Some(0)
            })
            .returning(move |_, _, _, _, _| {
                let value = expected.clone();
                Box::pin(async move { Ok(value) })
            });

        let result = HttpClient::update_participant_track_settings(
            &mock,
            TEST_LINK,
            TEST_TOKEN,
            TEST_PARTICIPANT,
            Some(1),
            Some(0),
        )
        .await
        .unwrap();
        assert_eq!(result.audio, 1);
        assert_eq!(result.video, 0);
    }

    #[unified_test]
    async fn fetch_access_token_success() {
        let token_info = sample_access_token_info();
        let mut mock = MockHttpClient::new();
        let expected = token_info.clone();
        mock.expect_fetch_access_token()
            .withf(|link, name, enc| link == TEST_LINK && name == "Alice" && enc == "enc-name")
            .returning(move |_, _, _| {
                let value = expected.clone();
                Box::pin(async move { Ok(value) })
            });

        let result = HttpClient::fetch_access_token(&mock, TEST_LINK, "Alice", "enc-name")
            .await
            .unwrap();
        assert_eq!(result.access_token, TEST_TOKEN);
    }

    #[unified_test]
    async fn get_meet_info_success() {
        let info = sample_meeting_info();
        let mut mock = MockHttpClient::new();
        let expected = info.clone();
        mock.expect_get_meet_info()
            .withf(|link| link == TEST_LINK)
            .returning(move |_| {
                let value = expected.clone();
                Box::pin(async move { Ok(value) })
            });

        let result = HttpClient::get_meet_info(&mock, TEST_LINK).await.unwrap();
        assert_eq!(result.meeting_link_name, TEST_LINK);
    }

    #[unified_test]
    async fn get_active_meetings_success() {
        let meetings = vec![sample_meeting()];
        let mut mock = MockHttpClient::new();
        let expected = meetings.clone();
        mock.expect_get_active_meetings().returning(move || {
            let value = expected.clone();
            Box::pin(async move { Ok(value) })
        });

        let result = HttpClient::get_active_meetings(&mock).await.unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].id, "meeting-id");
    }

    #[unified_test]
    async fn get_user_settings_success() {
        let settings = sample_user_settings();
        let mut mock = MockHttpClient::new();
        let expected = settings.clone();
        mock.expect_get_user_settings().returning(move || {
            let value = expected.clone();
            Box::pin(async move { Ok(value) })
        });

        let result = HttpClient::get_user_settings(&mock).await.unwrap();
        assert_eq!(result.meeting_id, "meeting-id");
    }

    #[unified_test]
    async fn get_meet_link_info_success() {
        let link_info = sample_meet_link_info();
        let mut mock = MockHttpClient::new();
        let expected = link_info.clone();
        mock.expect_get_meet_link_info()
            .withf(|link| link == TEST_LINK)
            .returning(move |_| {
                let value = expected.clone();
                Box::pin(async move { Ok(value) })
            });

        let result = HttpClient::get_meet_link_info(&mock, TEST_LINK)
            .await
            .unwrap();
        assert_eq!(result.srp_session, "srp-session");
    }

    #[unified_test]
    async fn get_participants_success() {
        let participants = vec![sample_participant()];
        let mut mock = MockHttpClient::new();
        let expected = participants.clone();
        mock.expect_get_participants()
            .withf(|link| link == TEST_LINK)
            .returning(move |_| {
                let value = expected.clone();
                Box::pin(async move { Ok(value) })
            });

        let result = HttpClient::get_participants(&mock, TEST_LINK)
            .await
            .unwrap();
        assert_eq!(result[0].participant_uuid, TEST_PARTICIPANT);
    }

    #[unified_test]
    async fn get_participants_count_success() {
        let mut mock = MockHttpClient::new();
        mock.expect_get_participants_count()
            .withf(|link| link == TEST_LINK)
            .returning(|_| Box::pin(async { Ok(3) }));

        assert_eq!(
            HttpClient::get_participants_count(&mock, TEST_LINK)
                .await
                .unwrap(),
            3
        );
    }

    #[unified_test]
    async fn get_modulus_success() {
        let modulus = sample_modulus();
        let mut mock = MockHttpClient::new();
        let expected = modulus.clone();
        mock.expect_get_modulus().returning(move || {
            let value = expected.clone();
            Box::pin(async move { Ok(value) })
        });

        let result = HttpClient::get_modulus(&mock).await.unwrap();
        assert_eq!(result.modulus_id, "modulus-id");
    }

    #[unified_test]
    async fn remove_participant_success() {
        let mut mock = MockHttpClient::new();
        mock.expect_remove_participant()
            .withf(|link, token, uuid| {
                link == TEST_LINK && token == TEST_TOKEN && uuid == TEST_PARTICIPANT
            })
            .returning(|_, _, _| Box::pin(async { Ok(()) }));

        HttpClient::remove_participant(&mock, TEST_LINK, TEST_TOKEN, TEST_PARTICIPANT)
            .await
            .unwrap();
    }

    #[unified_test]
    async fn ping_success() {
        let mut mock = MockHttpClient::new();
        mock.expect_ping().returning(|| Box::pin(async { Ok(42) }));

        assert_eq!(HttpClient::ping(&mock).await.unwrap(), 42);
    }

    #[unified_test]
    async fn ping_failure() {
        let mut mock = MockHttpClient::new();
        mock.expect_ping().returning(|| {
            Box::pin(async {
                Err(HttpClientError::MlsHttpError {
                    message: "ping failed".into(),
                })
            })
        });

        let result = HttpClient::ping(&mock).await;
        assert!(matches!(
            result,
            Err(HttpClientError::MlsHttpError { message: _ })
        ));
    }
}
