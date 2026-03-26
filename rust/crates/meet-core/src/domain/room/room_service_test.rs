#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use crate::domain::room::RoomService;
    use crate::domain::user::{
        models::{
            meet_link_info::{AccessTokenInfo, MeetLinkAuthInfo, MeetLinkInfo},
            meeting::{Meeting, MeetingInfo},
            participant_track_settings::ParticipantTrackSettings,
        },
        ports::{
            crypto_client::MockCryptoClient, http_client::MockHttpClient,
            meeting_api::MockMeetingApi,
        },
    };
    use crate::errors::http_client::HttpClientError;
    use mockall::predicate::eq;
    use proton_meet_crypto::{CryptoError, SRPProof, MEET_DISPLAY_NAME_AAD, MEET_METADATA_AAD};
    use proton_meet_macro::unified_test;
    use std::future::ready;

    // Test data constants
    const TEST_MEET_LINK_NAME: &str = "test_meet_link";
    const TEST_MEET_LINK_PASSWORD: &str = "secure_meeting_password";
    const TEST_DISPLAY_NAME: &str = "John Doe";
    const TEST_MEETING_NAME: &str = "Team Standup";
    const TEST_ACCESS_TOKEN: &str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9";
    const TEST_WEBSOCKET_URL: &str = "wss://meet.proton.me/ws";
    const TEST_PARTICIPANT_UUID: &str = "test_participant_uuid";

    // Helper functions to create test data
    fn create_test_meet_link_info() -> MeetLinkInfo {
        MeetLinkInfo {
            modulus: "c3f4a2b8e9d7f6e5a4b3c2d1e0f9a8b7c6d5e4f3a2b1".to_string(),
            server_ephemeral: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0".to_string(),
            srp_session: "session_abc123def456".to_string(),
            salt: "salt_xyz789uvw012".to_string(),
        }
    }

    fn create_test_srp_proof() -> SRPProof {
        SRPProof {
            client_ephemeral: "client_ephemeral_123".to_string(),
            client_proof: "client_proof_456".to_string(),
            expected_server_proof: "server_proof_789".to_string(),
        }
    }

    fn create_test_auth_info() -> MeetLinkAuthInfo {
        MeetLinkAuthInfo {
            server_proof: "server_proof_789".to_string(),
            uid: "uid_abc123".to_string(),
            access_token: Some(TEST_ACCESS_TOKEN.to_string()),
        }
    }

    fn create_test_meeting_info() -> MeetingInfo {
        MeetingInfo {
            meeting_name: "encrypted_name_data".to_string(),
            salt: "encryption_salt_123".to_string(),
            session_key: "session_key_encrypted".to_string(),
            meeting_link_name: TEST_MEET_LINK_NAME.to_string(),
            locked: 0,
            max_duration: 3600,
            max_participants: 100,
            expiration_time: None,
        }
    }

    #[tokio::test]
    #[cfg(not(target_family = "wasm"))]
    async fn test_join_meeting_success() {
        let meet_link_info = create_test_meet_link_info();
        let srp_proof = create_test_srp_proof();
        let auth_info = create_test_auth_info();
        let meeting_info = create_test_meeting_info();

        let mut http_client = MockHttpClient::new();
        let mut crypto_client = MockCryptoClient::new();

        // Setup HTTP client expectations
        http_client
            .expect_get_meet_link_info()
            .with(eq(TEST_MEET_LINK_NAME))
            .once()
            .returning({
                let meet_link_info = meet_link_info.clone();
                move |_| Box::pin(ready(Ok(meet_link_info.clone())))
            });

        http_client
            .expect_auth_meet_link()
            .with(
                eq(TEST_MEET_LINK_NAME),
                eq(srp_proof.client_ephemeral.clone()),
                eq(srp_proof.client_proof.clone()),
                eq(meet_link_info.srp_session.clone()),
            )
            .once()
            .returning({
                let auth_info = auth_info.clone();
                move |_, _, _, _| Box::pin(ready(Ok(auth_info.clone())))
            });

        http_client
            .expect_get_meet_info()
            .with(eq(TEST_MEET_LINK_NAME))
            .once()
            .returning({
                let meeting_info = meeting_info.clone();
                move |_| Box::pin(ready(Ok(meeting_info.clone())))
            });

        http_client
            .expect_fetch_access_token()
            .with(
                eq(TEST_MEET_LINK_NAME),
                eq(TEST_DISPLAY_NAME),
                eq("enc_display_name"),
            )
            .once()
            .returning(|_, _, _| {
                Box::pin(ready(Ok(AccessTokenInfo {
                    access_token: TEST_ACCESS_TOKEN.to_string(),
                    websocket_url: TEST_WEBSOCKET_URL.to_string(),
                })))
            });

        // Setup crypto client expectations
        crypto_client
            .expect_generate_srp_proof()
            .with(
                eq(TEST_MEET_LINK_PASSWORD),
                eq(meet_link_info.modulus.clone()),
                eq(meet_link_info.server_ephemeral.clone()),
                eq(meet_link_info.salt.clone()),
            )
            .once()
            .returning({
                let srp_proof = srp_proof.clone();
                move |_, _, _, _| Box::pin(ready(Ok(srp_proof.clone())))
            });

        crypto_client
            .expect_compute_key_password()
            .with(eq(TEST_MEET_LINK_PASSWORD), eq(meeting_info.salt.clone()))
            .once()
            .returning(|_, _| Box::pin(ready(Ok("computed_key_password".to_string()))));

        crypto_client
            .expect_decrypt_session_key()
            .with(
                eq(meeting_info.session_key.clone()),
                eq("computed_key_password"),
            )
            .once()
            .returning(|_, _| Box::pin(ready(Ok("decrypted_session_key".to_string()))));

        crypto_client
            .expect_decrypt_message()
            .with(
                eq(meeting_info.meeting_name.clone()),
                eq("decrypted_session_key"),
                eq(MEET_METADATA_AAD),
            )
            .once()
            .returning(|_, _, _| Box::pin(ready(Ok(TEST_MEETING_NAME.to_string()))));

        crypto_client
            .expect_encrypt_message()
            .with(
                eq(TEST_DISPLAY_NAME),
                eq("decrypted_session_key"),
                eq(MEET_DISPLAY_NAME_AAD),
            )
            .once()
            .returning(|_, _, _| Box::pin(ready(Ok("enc_display_name".to_string()))));

        let room_service = RoomService::new(
            Arc::new(http_client),
            Arc::new(MockMeetingApi::new()),
            Arc::new(crypto_client),
        );

        let result = room_service
            .join_meeting(
                TEST_MEET_LINK_NAME,
                TEST_MEET_LINK_PASSWORD,
                TEST_DISPLAY_NAME,
            )
            .await;

        assert!(result.is_ok());
        let (meet_info, session_key) = result.unwrap();
        assert_eq!(meet_info.meet_name, TEST_MEETING_NAME);
        assert_eq!(meet_info.meet_link_name, TEST_MEET_LINK_NAME);
        assert_eq!(meet_info.access_token, TEST_ACCESS_TOKEN);
        assert_eq!(meet_info.websocket_url, TEST_WEBSOCKET_URL);
        assert_eq!(session_key.as_deref(), Some("decrypted_session_key"));
    }

    #[unified_test]
    async fn test_join_meeting_srp_proof_mismatch() {
        let meet_link_info = create_test_meet_link_info();
        let srp_proof = create_test_srp_proof();
        let mut auth_info = create_test_auth_info();
        // Create mismatched server proof
        auth_info.server_proof = "mismatched_server_proof".to_string();

        let mut http_client = MockHttpClient::new();
        let mut crypto_client = MockCryptoClient::new();

        http_client
            .expect_get_meet_link_info()
            .with(eq(TEST_MEET_LINK_NAME))
            .once()
            .returning({
                let meet_link_info = meet_link_info.clone();
                move |_| Box::pin(ready(Ok(meet_link_info.clone())))
            });

        crypto_client
            .expect_generate_srp_proof()
            .with(
                eq(TEST_MEET_LINK_PASSWORD),
                eq(meet_link_info.modulus.clone()),
                eq(meet_link_info.server_ephemeral.clone()),
                eq(meet_link_info.salt.clone()),
            )
            .once()
            .returning({
                let srp_proof = srp_proof.clone();
                move |_, _, _, _| Box::pin(ready(Ok(srp_proof.clone())))
            });

        http_client
            .expect_auth_meet_link()
            .with(
                eq(TEST_MEET_LINK_NAME),
                eq(srp_proof.client_ephemeral.clone()),
                eq(srp_proof.client_proof.clone()),
                eq(meet_link_info.srp_session.clone()),
            )
            .once()
            .returning({
                let auth_info = auth_info.clone();
                move |_, _, _, _| Box::pin(ready(Ok(auth_info.clone())))
            });

        let room_service = RoomService::new(
            Arc::new(http_client),
            Arc::new(MockMeetingApi::new()),
            Arc::new(crypto_client),
        );

        let result = room_service
            .join_meeting(
                TEST_MEET_LINK_NAME,
                TEST_MEET_LINK_PASSWORD,
                TEST_DISPLAY_NAME,
            )
            .await;

        assert!(result.is_err());
        let error_message = result.unwrap_err().to_string();
        assert!(error_message.contains("SRP proof mismatch"));
    }

    #[unified_test]
    async fn test_join_meeting_get_meet_link_info_fails() {
        let mut http_client = MockHttpClient::new();
        let crypto_client = MockCryptoClient::new();

        http_client
            .expect_get_meet_link_info()
            .with(eq(TEST_MEET_LINK_NAME))
            .once()
            .returning(|_| {
                Box::pin(ready(Err(HttpClientError::MlsHttpError {
                    message: "Network error".to_string(),
                })))
            });

        let room_service = RoomService::new(
            Arc::new(http_client),
            Arc::new(MockMeetingApi::new()),
            Arc::new(crypto_client),
        );

        let result = room_service
            .join_meeting(
                TEST_MEET_LINK_NAME,
                TEST_MEET_LINK_PASSWORD,
                TEST_DISPLAY_NAME,
            )
            .await;

        assert!(result.is_err());
    }

    #[unified_test]
    async fn test_join_meeting_crypto_error() {
        let meet_link_info = create_test_meet_link_info();

        let mut http_client = MockHttpClient::new();
        let mut crypto_client = MockCryptoClient::new();

        http_client
            .expect_get_meet_link_info()
            .with(eq(TEST_MEET_LINK_NAME))
            .once()
            .returning({
                let meet_link_info = meet_link_info.clone();
                move |_| Box::pin(ready(Ok(meet_link_info.clone())))
            });

        crypto_client
            .expect_generate_srp_proof()
            .with(
                eq(TEST_MEET_LINK_PASSWORD),
                eq(meet_link_info.modulus.clone()),
                eq(meet_link_info.server_ephemeral.clone()),
                eq(meet_link_info.salt.clone()),
            )
            .once()
            .returning(|_, _, _, _| {
                Box::pin(ready(Err(CryptoError::SrpError(
                    "Crypto error".to_string(),
                ))))
            });

        let room_service = RoomService::new(
            Arc::new(http_client),
            Arc::new(MockMeetingApi::new()),
            Arc::new(crypto_client),
        );

        let result = room_service
            .join_meeting(
                TEST_MEET_LINK_NAME,
                TEST_MEET_LINK_PASSWORD,
                TEST_DISPLAY_NAME,
            )
            .await;

        assert!(result.is_err());
    }

    #[unified_test]
    async fn test_get_active_meetings() {
        let mut http_client = MockHttpClient::new();
        let expected_meetings = vec![
            Meeting {
                id: "meeting1".to_string(),
                meeting_link_name: "link1".to_string(),
                ..Default::default()
            },
            Meeting {
                id: "meeting2".to_string(),
                meeting_link_name: "link2".to_string(),
                ..Default::default()
            },
        ];

        http_client.expect_get_active_meetings().once().returning({
            let expected_meetings = expected_meetings.clone();
            move || Box::pin(ready(Ok(expected_meetings.clone())))
        });

        let room_service = RoomService::new(
            Arc::new(http_client),
            Arc::new(MockMeetingApi::new()),
            Arc::new(MockCryptoClient::new()),
        );

        let result = room_service.get_active_meetings().await;

        assert!(result.is_ok());
        let meetings = result.unwrap();
        assert_eq!(meetings.len(), 2);
        assert_eq!(meetings[0].id, "meeting1");
        assert_eq!(meetings[1].id, "meeting2");
    }

    #[unified_test]
    async fn test_get_participants() {
        let mut http_client = MockHttpClient::new();
        let expected_participants = vec![
            crate::domain::user::models::meet_link_info::MeetParticipant {
                participant_uuid: "participant1".to_string(),
                display_name: "Participant 1".to_string(),
                encrypted_display_name: None,
                can_subscribe: Some(1),
                can_publish: Some(1),
                can_publish_data: Some(1),
                is_admin: Some(0),
                is_host: Some(0),
            },
            crate::domain::user::models::meet_link_info::MeetParticipant {
                participant_uuid: "participant2".to_string(),
                display_name: "Participant 2".to_string(),
                encrypted_display_name: None,
                can_subscribe: Some(1),
                can_publish: Some(0),
                can_publish_data: Some(1),
                is_admin: Some(0),
                is_host: Some(0),
            },
        ];

        http_client
            .expect_get_participants()
            .with(eq(TEST_MEET_LINK_NAME))
            .once()
            .returning({
                let expected_participants = expected_participants.clone();
                move |_| Box::pin(ready(Ok(expected_participants.clone())))
            });

        let room_service = RoomService::new(
            Arc::new(http_client),
            Arc::new(MockMeetingApi::new()),
            Arc::new(MockCryptoClient::new()),
        );

        let result = room_service.get_participants(TEST_MEET_LINK_NAME).await;

        assert!(result.is_ok());
        let participants = result.unwrap();
        assert_eq!(participants.len(), 2);
        assert_eq!(participants[0].participant_uuid, "participant1");
        assert_eq!(participants[1].participant_uuid, "participant2");
    }

    #[unified_test]
    async fn test_end_meeting() {
        let mut meeting_api = MockMeetingApi::new();

        meeting_api
            .expect_end_meeting()
            .with(eq(TEST_MEETING_NAME), eq(TEST_ACCESS_TOKEN))
            .once()
            .returning(|_, _| Box::pin(ready(Ok(()))));

        let room_service = RoomService::new(
            Arc::new(MockHttpClient::new()),
            Arc::new(meeting_api),
            Arc::new(MockCryptoClient::new()),
        );

        let result = room_service
            .end_meeting(TEST_MEETING_NAME, TEST_ACCESS_TOKEN)
            .await;

        assert!(result.is_ok());
    }

    #[unified_test]
    async fn test_update_participant_track_settings() {
        let mut http_client = MockHttpClient::new();
        let expected_settings = ParticipantTrackSettings { audio: 1, video: 1 };

        http_client
            .expect_update_participant_track_settings()
            .with(
                eq(TEST_MEET_LINK_NAME),
                eq(TEST_ACCESS_TOKEN),
                eq(TEST_PARTICIPANT_UUID),
                eq(Some(1u8)),
                eq(Some(1u8)),
            )
            .once()
            .returning({
                let expected_settings = expected_settings.clone();
                move |_, _, _, _, _| Box::pin(ready(Ok(expected_settings.clone())))
            });

        let room_service = RoomService::new(
            Arc::new(http_client),
            Arc::new(MockMeetingApi::new()),
            Arc::new(MockCryptoClient::new()),
        );

        let result = room_service
            .update_participant_track_settings(
                TEST_MEET_LINK_NAME,
                TEST_ACCESS_TOKEN,
                TEST_PARTICIPANT_UUID,
                Some(1),
                Some(1),
            )
            .await;

        assert!(result.is_ok());
        let settings = result.unwrap();
        assert_eq!(settings.audio, 1);
        assert_eq!(settings.video, 1);
    }

    #[unified_test]
    async fn test_remove_participant() {
        let mut http_client = MockHttpClient::new();

        http_client
            .expect_remove_participant()
            .with(
                eq(TEST_MEET_LINK_NAME),
                eq(TEST_ACCESS_TOKEN),
                eq(TEST_PARTICIPANT_UUID),
            )
            .once()
            .returning(|_, _, _| Box::pin(ready(Ok(()))));

        let room_service = RoomService::new(
            Arc::new(http_client),
            Arc::new(MockMeetingApi::new()),
            Arc::new(MockCryptoClient::new()),
        );

        let result = room_service
            .remove_participant(
                TEST_MEET_LINK_NAME,
                TEST_ACCESS_TOKEN,
                TEST_PARTICIPANT_UUID,
            )
            .await;

        assert!(result.is_ok());
    }
}
