use crate::domain::user::models::meet_link_info::MeetParticipant;
use crate::domain::user::models::participant_track_settings::ParticipantTrackSettings;
use crate::domain::user::models::{
    login::Modulus,
    meet_link_info::{AccessTokenInfo, MeetLinkAuthInfo, MeetLinkInfo},
    meeting::{Meeting, MeetingInfo},
    user_settings::UserSettings,
};
use crate::errors::http_client::HttpClientError;
use proton_meet_macro::async_trait_with_mock;

#[async_trait_with_mock]
pub trait HttpClient: Send + Sync {
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

    async fn update_user_settings_waiting_room(
        &self,
        enable: bool,
    ) -> Result<UserSettings, HttpClientError>;

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
            address_id: Some("address-id".to_string()),
            waiting_room: false,
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
