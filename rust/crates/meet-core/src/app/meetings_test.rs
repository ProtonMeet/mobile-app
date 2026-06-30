use chrono::{TimeZone, Utc};
use mockall::predicate::eq;
use std::{future::ready, sync::Arc};

use crate::app::test_support::{
    build_app, build_app_with_http, build_app_with_room, build_app_with_room_and_user_key_provider,
    build_app_with_user_key_provider, default_app_state, room_service_with_http,
    room_service_with_http_and_crypto, room_service_with_meeting_api,
    room_service_with_meeting_api_and_crypto, state_with_authenticated_user,
    unreachable_test_proton_http_client,
};
use crate::app::App;
use crate::domain::user::{
    models::{
        meet_link_info::{AccessTokenInfo, MeetLinkAuthInfo, MeetLinkInfo},
        meeting::{Meeting, MeetingInfo, MeetingType},
    },
    ports::{crypto_client::MockCryptoClient, meeting_api::MockMeetingApi, MockHttpClient},
};
use crate::errors::{core::MeetCoreError, http_client::HttpClientError};
use crate::infra::{ports::user_key_provider::MockUserKeyProvider, storage::error::StorageError};
use proton_meet_crypto::{MEET_DISPLAY_NAME_AAD, MEET_METADATA_AAD};

#[test]
fn to_utc_datetime_parses_seconds() {
    let dt = App::to_utc_datetime(1_700_000_000).unwrap();
    assert_eq!(dt, Utc.timestamp_opt(1_700_000_000, 0).unwrap());
}

#[test]
fn to_utc_datetime_parses_milliseconds() {
    let dt = App::to_utc_datetime(1_700_000_000_123).unwrap();
    assert_eq!(dt, Utc.timestamp_opt(1_700_000_000, 123_000_000).unwrap());
}

#[test]
fn to_utc_datetime_returns_none_for_invalid_timestamp() {
    assert!(App::to_utc_datetime(i64::MAX).is_none());
}

#[test]
fn to_utc_datetime_handles_negative_millisecond_timestamps() {
    let dt = App::to_utc_datetime(-1_700_000_000_123).unwrap();
    assert_eq!(dt, Utc.timestamp_opt(-1_700_000_001, 877_000_000).unwrap());
}

#[tokio::test]
async fn edit_meeting_name_requires_authenticated_user() {
    let app = build_app(default_app_state()).await;
    let err = app
        .edit_meeting_name(
            "meeting-id".to_string(),
            "new name".to_string(),
            "password".to_string(),
        )
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::NoActiveUser));
}

#[tokio::test]
async fn update_meeting_schedule_requires_authenticated_user() {
    let app = build_app(default_app_state()).await;
    let err = app
        .update_meeting_schedule(
            "meeting-id".to_string(),
            "name".to_string(),
            "password".to_string(),
            None,
            None,
            None,
            None,
        )
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::NoActiveUser));
}

#[tokio::test]
async fn create_meeting_with_session_requires_authenticated_user() {
    let app = build_app(default_app_state()).await;
    let err = app
        .create_meeting(
            "name".to_string(),
            true,
            MeetingType::Instant,
            None,
            None,
            None,
            None,
            None,
        )
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::NoActiveUser));
}

#[tokio::test]
async fn create_personal_meeting_requires_authenticated_user() {
    let app = build_app(default_app_state()).await;
    let err = app
        .create_personal_meeting("personal".to_string(), None, false)
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::NoActiveUser));
}

#[tokio::test]
async fn get_upcoming_meetings_requires_active_user() {
    let app = build_app(default_app_state()).await;
    let err = app.get_upcoming_meetings().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::NoActiveUser));
}

#[tokio::test]
async fn get_upcoming_meetings_maps_passphrase_storage_error() {
    let mut provider = MockUserKeyProvider::new();
    provider
        .expect_get_user_key_passphrase()
        .once()
        .returning(|_| {
            Box::pin(ready(Err(StorageError::DbNotFound {
                name: "user-1".to_string(),
            })))
        });

    let app =
        build_app_with_user_key_provider(state_with_authenticated_user(), Arc::new(provider)).await;
    let err = app.get_upcoming_meetings().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::StorageError { .. }));
}

#[tokio::test]
async fn lock_meeting_delegates_to_room_service() {
    let mut meeting_api = MockMeetingApi::new();
    meeting_api
        .expect_lock_meeting()
        .with(eq("LINK123"))
        .once()
        .returning(|_| Box::pin(ready(Ok(()))));

    let app = build_app_with_room(
        default_app_state(),
        room_service_with_meeting_api(meeting_api),
    )
    .await;
    app.lock_meeting("LINK123".to_string()).await.unwrap();
}

#[tokio::test]
async fn unlock_meeting_delegates_to_room_service() {
    let mut meeting_api = MockMeetingApi::new();
    meeting_api
        .expect_unlock_meeting()
        .with(eq("LINK123"))
        .once()
        .returning(|_| Box::pin(ready(Ok(()))));

    let app = build_app_with_room(
        default_app_state(),
        room_service_with_meeting_api(meeting_api),
    )
    .await;
    app.unlock_meeting("LINK123".to_string()).await.unwrap();
}

#[tokio::test]
async fn authenticate_meeting_link_propagates_room_service_error() {
    let mut http = MockHttpClient::new();
    http.expect_get_meet_link_info().once().returning(|_| {
        Box::pin(ready(Err(HttpClientError::Deserialize(
            "offline".to_string(),
        ))))
    });

    let app = build_app_with_room(default_app_state(), room_service_with_http(http)).await;
    assert!(app
        .authenticate_meeting_link(
            "LINK123".to_string(),
            "password".to_string(),
            "Alice".to_string(),
        )
        .await
        .is_err());
}

#[tokio::test]
async fn create_meeting_without_session_propagates_room_service_error() {
    let mut http = MockHttpClient::new();
    http.expect_get_modulus().once().returning(|| {
        Box::pin(ready(Err(HttpClientError::Deserialize(
            "offline".to_string(),
        ))))
    });

    let app = build_app_with_room(default_app_state(), room_service_with_http(http)).await;
    assert!(app
        .create_meeting(
            "instant".to_string(),
            false,
            MeetingType::Scheduled,
            None,
            None,
            None,
            None,
            None,
        )
        .await
        .is_err());
}

#[tokio::test]
async fn delete_meeting_propagates_http_error_without_network() {
    let app = build_app_with_http(
        default_app_state(),
        unreachable_test_proton_http_client().await,
    )
    .await;
    let err = app.delete_meeting("LINK123".to_string()).await;
    assert!(err.is_err());
}

#[tokio::test]
async fn send_meeting_feedback_rejects_score_below_range() {
    let app = build_app(default_app_state()).await;
    let err = app
        .send_meeting_feedback("link", 0, vec![])
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::InvalidInput { field, .. } if field == "score"));
}

#[tokio::test]
async fn send_meeting_feedback_rejects_score_above_range() {
    let app = build_app(default_app_state()).await;
    let err = app
        .send_meeting_feedback("link", 6, vec![])
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::InvalidInput { field, .. } if field == "score"));
}

#[tokio::test]
async fn send_meeting_feedback_joins_feedback_parts() {
    let app = build_app(default_app_state()).await;
    let result = app
        .send_meeting_feedback("link", 3, vec!["audio".to_string(), "video".to_string()])
        .await;
    assert!(!matches!(result, Err(MeetCoreError::InvalidInput { .. })));
}

#[tokio::test]
async fn get_active_meetings_delegates_to_room_service() {
    let mut http = MockHttpClient::new();
    http.expect_get_active_meetings()
        .once()
        .returning(|| Box::pin(ready(Ok(vec![Meeting::default()]))));

    let app = build_app_with_room(default_app_state(), room_service_with_http(http)).await;
    assert_eq!(app.get_active_meetings().await.unwrap().len(), 1);
}

#[tokio::test]
async fn get_meeting_info_delegates_to_room_service() {
    let mut meeting_api = MockMeetingApi::new();
    meeting_api
        .expect_get_meeting_info()
        .with(eq("LINK123"))
        .once()
        .returning(|_| {
            Box::pin(ready(Ok(MeetingInfo {
                meeting_link_name: "LINK123".to_string(),
                meeting_name: "enc".to_string(),
                salt: "salt".to_string(),
                session_key: "sk".to_string(),
                locked: 0,
                max_duration: 3600,
                max_participants: 100,
                expiration_time: None,
            })))
        });

    let app = build_app_with_room(
        default_app_state(),
        room_service_with_meeting_api(meeting_api),
    )
    .await;

    let info = app.get_meeting_info("LINK123").await.unwrap();
    assert_eq!(info.meeting_link_name, "LINK123");
}

#[tokio::test]
async fn update_meeting_schedule_success() {
    let mut meeting_api = MockMeetingApi::new();
    meeting_api
        .expect_update_meeting_schedule()
        .once()
        .returning(|_, _| {
            Box::pin(ready(Ok(Meeting {
                id: "meeting-id".to_string(),
                meeting_link_name: "LINK123".to_string(),
                ..Default::default()
            })))
        });

    let app = build_app_with_room(
        state_with_authenticated_user(),
        room_service_with_meeting_api(meeting_api),
    )
    .await;

    let updated = app
        .update_meeting_schedule(
            "meeting-id".to_string(),
            "name".to_string(),
            "password".to_string(),
            None,
            None,
            None,
            None,
        )
        .await
        .unwrap();
    assert_eq!(updated.id, "meeting-id");
}

#[tokio::test]
async fn edit_meeting_name_success() {
    let meeting = Meeting {
        id: "meeting-id".to_string(),
        meeting_link_name: "LINK123".to_string(),
        salt: "salt".to_string(),
        session_key: "session_key".to_string(),
        ..Default::default()
    };

    let mut meeting_api = MockMeetingApi::new();
    meeting_api
        .expect_fetch_meeting()
        .with(eq("meeting-id"))
        .once()
        .returning({
            let meeting = meeting.clone();
            move |_| Box::pin(ready(Ok(meeting.clone())))
        });
    meeting_api
        .expect_edit_meeting_name()
        .once()
        .returning(|_, _| {
            Box::pin(ready(Ok(Meeting {
                id: "meeting-id".to_string(),
                meeting_link_name: "LINK123".to_string(),
                ..Default::default()
            })))
        });

    let mut crypto = MockCryptoClient::new();
    crypto
        .expect_compute_key_password()
        .once()
        .returning(|_, _| Box::pin(ready(Ok("password_hash".to_string()))));
    crypto
        .expect_decrypt_session_key()
        .once()
        .returning(|_, _| Box::pin(ready(Ok("session_key_plain".to_string()))));
    crypto
        .expect_encrypt_message()
        .with(
            eq("new name"),
            eq("session_key_plain"),
            eq(MEET_METADATA_AAD),
        )
        .once()
        .returning(|_, _, _| Box::pin(ready(Ok("encrypted_name".to_string()))));

    let app = build_app_with_room(
        state_with_authenticated_user(),
        room_service_with_meeting_api_and_crypto(meeting_api, crypto),
    )
    .await;

    let updated = app
        .edit_meeting_name(
            "meeting-id".to_string(),
            "new name".to_string(),
            "password".to_string(),
        )
        .await
        .unwrap();
    assert_eq!(updated.meeting_name, "new name");
}

#[tokio::test]
async fn get_upcoming_meetings_success_with_empty_list() {
    let mut meeting_api = MockMeetingApi::new();
    meeting_api
        .expect_get_upcoming_meetings()
        .once()
        .returning(|| Box::pin(ready(Ok(vec![]))));

    let mut provider = MockUserKeyProvider::new();
    provider
        .expect_get_user_key_passphrase()
        .once()
        .returning(|_| Box::pin(ready(Ok("passphrase".to_string()))));

    let app = build_app_with_room_and_user_key_provider(
        state_with_authenticated_user(),
        room_service_with_meeting_api(meeting_api),
        Arc::new(provider),
    )
    .await;

    assert!(app.get_upcoming_meetings().await.unwrap().is_empty());
}

#[tokio::test]
async fn send_meeting_feedback_propagates_http_error() {
    let app = build_app_with_http(
        default_app_state(),
        unreachable_test_proton_http_client().await,
    )
    .await;
    let err = app
        .send_meeting_feedback("link", 3, vec!["audio".to_string()])
        .await;
    assert!(err.is_err());
}

#[tokio::test]
async fn authenticate_meeting_link_stores_session_key() {
    const LINK: &str = "LINK123";
    const PASSWORD: &str = "password";
    const DISPLAY: &str = "Alice";

    let meet_link_info = MeetLinkInfo {
        modulus: "modulus".to_string(),
        server_ephemeral: "server_ephemeral".to_string(),
        srp_session: "srp_session".to_string(),
        salt: "salt".to_string(),
    };
    let auth_info = MeetLinkAuthInfo {
        server_proof: "server_proof".to_string(),
        uid: "uid".to_string(),
        access_token: Some("access-token".to_string()),
    };
    let meeting_info = MeetingInfo {
        meeting_link_name: LINK.to_string(),
        meeting_name: "encrypted_name".to_string(),
        salt: "salt".to_string(),
        session_key: "session_key".to_string(),
        locked: 0,
        max_duration: 3600,
        max_participants: 100,
        expiration_time: None,
    };

    let mut http = MockHttpClient::new();
    http.expect_get_meet_link_info()
        .with(eq(LINK))
        .once()
        .returning({
            let meet_link_info = meet_link_info.clone();
            move |_| Box::pin(ready(Ok(meet_link_info.clone())))
        });
    http.expect_auth_meet_link().once().returning({
        let auth_info = auth_info.clone();
        move |_, _, _, _| Box::pin(ready(Ok(auth_info.clone())))
    });
    http.expect_get_meet_info()
        .with(eq(LINK))
        .once()
        .returning({
            let meeting_info = meeting_info.clone();
            move |_| Box::pin(ready(Ok(meeting_info.clone())))
        });
    http.expect_fetch_access_token()
        .once()
        .returning(|_, _, _| {
            Box::pin(ready(Ok(AccessTokenInfo {
                access_token: "access-token".to_string(),
                websocket_url: "wss://livekit.example".to_string(),
            })))
        });

    let mut crypto = MockCryptoClient::new();
    crypto
        .expect_generate_srp_proof()
        .once()
        .returning(|_, _, _, _| {
            Box::pin(ready(Ok(proton_meet_crypto::SRPProof {
                client_ephemeral: "client_ephemeral".to_string(),
                client_proof: "client_proof".to_string(),
                expected_server_proof: "server_proof".to_string(),
            })))
        });
    crypto
        .expect_compute_key_password()
        .once()
        .returning(|_, _| Box::pin(ready(Ok("key_password".to_string()))));
    crypto
        .expect_decrypt_session_key()
        .once()
        .returning(|_, _| Box::pin(ready(Ok("decrypted_session_key".to_string()))));
    crypto
        .expect_decrypt_message()
        .once()
        .returning(|_, _, _| Box::pin(ready(Ok("Meeting Name".to_string()))));
    crypto
        .expect_encrypt_message()
        .with(
            eq(DISPLAY),
            eq("decrypted_session_key"),
            eq(MEET_DISPLAY_NAME_AAD),
        )
        .once()
        .returning(|_, _, _| Box::pin(ready(Ok("enc_display".to_string()))));

    let app = build_app_with_room(
        default_app_state(),
        room_service_with_http_and_crypto(http, crypto),
    )
    .await;

    let meet_info = app
        .authenticate_meeting_link(LINK.to_string(), PASSWORD.to_string(), DISPLAY.to_string())
        .await
        .unwrap();
    assert_eq!(meet_info.access_token, "access-token");
    assert_eq!(meet_info.meet_link_name, LINK);
}

// --- Manual integration (real backend). Run: cargo test -p proton-meet-core create_meeting -- --ignored ---

#[cfg(all(test, not(target_family = "wasm")))]
mod manual {
    use super::*;
    use crate::app::test_support::manual;
    use tempfile::tempdir;

    #[tokio::test]
    #[ignore = "requires anning atlas and bart/bart credentials"]
    async fn create_meeting_and_join() -> Result<(), anyhow::Error> {
        let temp_dir = tempdir()?;
        let db_path = temp_dir
            .path()
            .to_str()
            .ok_or_else(|| anyhow::anyhow!("temp path"))?
            .to_string();

        let app = manual::app_for_custom_api(
            "https://anning.proton.black/api",
            "anning.proton.black/api",
            db_path,
            "mls.anning.proton.black",
            "macos-meet@0.0.9",
        )
        .await?;

        let user_data = app.login("bart".to_string(), "bart".to_string()).await?;
        assert!(!user_data.user.id.is_empty());
        assert!(!user_data.user.email.is_empty());

        let meeting = app
            .create_meeting(
                "test".to_string(),
                false,
                MeetingType::Instant,
                None,
                None,
                None,
                None,
                None,
            )
            .await?;

        let meet_info = app
            .authenticate_meeting_link(
                meeting.meeting_link_name,
                meeting.meeting_password.clone(),
                "new joiner".to_string(),
            )
            .await?;

        app.join_meeting_with_access_token(
            meet_info.access_token,
            meet_info.meet_link_name,
            meeting.meeting_password,
            None,
        )
        .await?;

        Ok(())
    }
}
