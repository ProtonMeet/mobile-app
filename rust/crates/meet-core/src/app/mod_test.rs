use std::future::ready;
use std::sync::Arc;

use crate::app::test_support::{
    build_app, build_app_with_http, build_app_with_service, default_app_state,
    state_with_participant_only, test_mls_store, test_server_time_tracker,
    unreachable_test_proton_http_client,
};
use crate::domain::user::ports::meeting_api::MockMeetingApi;
use crate::domain::user::ports::{MockHttpClient, MockMlsApi};
use crate::errors::{core::MeetCoreError, http_client::HttpClientError};
use crate::service::user_service::Service;

#[tokio::test]
async fn ping_propagates_http_error_without_network() {
    let app = build_app_with_http(
        default_app_state(),
        unreachable_test_proton_http_client().await,
    )
    .await;
    assert!(app.ping().await.is_err());
}

#[tokio::test]
async fn fetch_toggles_propagates_http_error() {
    let app = build_app_with_http(
        default_app_state(),
        unreachable_test_proton_http_client().await,
    )
    .await;
    assert!(app.fetch_toggles().await.is_err());
}

#[tokio::test]
async fn set_livekit_active_uuids_errors_without_participant() {
    let app = build_app(default_app_state()).await;
    let err = app
        .set_livekit_active_uuids(vec!["uuid".to_string()], false)
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn is_mls_up_to_date_errors_without_participant() {
    let app = build_app(default_app_state()).await;
    let err = app.is_mls_up_to_date().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn get_group_key_errors_without_participant() {
    let app = build_app(default_app_state()).await;
    let err = app.get_group_key().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn get_group_len_errors_without_participant() {
    let app = build_app(default_app_state()).await;
    let err = app.get_group_len().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn get_group_display_code_errors_without_participant() {
    let app = build_app(default_app_state()).await;
    let err = app.get_group_display_code().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn encrypt_message_errors_without_participant() {
    let app = build_app(default_app_state()).await;
    let err = app.encrypt_message("hello").await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn decrypt_message_errors_without_participant() {
    let app = build_app(default_app_state()).await;
    let err = app.decrypt_message(vec![1, 2, 3]).await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn update_participant_track_settings_errors_without_participant() {
    let app = build_app(default_app_state()).await;
    let err = app
        .update_participant_track_settings("uuid".to_string(), Some(1), Some(0))
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn update_participant_track_settings_errors_without_livekit_token() {
    let app = build_app(state_with_participant_only("user-1")).await;
    let err = app
        .update_participant_track_settings("uuid".to_string(), Some(1), None)
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::LivekitAccessTokenNotFound));
}

#[tokio::test]
async fn remove_participant_errors_without_livekit_token() {
    let app = build_app(state_with_participant_only("user-1")).await;
    let err = app
        .remove_participant("uuid".to_string())
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::LivekitAccessTokenNotFound));
}

#[tokio::test]
async fn get_user_settings_propagates_service_error() {
    use crate::domain::user::ports::{user_api::MockUserApi, MockUserRepository};

    let mut http = MockHttpClient::new();
    http.expect_get_user_settings().once().returning(|| {
        Box::pin(ready(Err(HttpClientError::Deserialize(
            "offline".to_string(),
        ))))
    });

    let service = Service::new(
        Arc::new(http),
        Arc::new(MockMlsApi::new()),
        Arc::new(MockMeetingApi::new()),
        Arc::new(MockUserApi::new()),
        Arc::new(MockUserRepository::new()),
        Arc::new(crate::app::test_support::minimal_ws_mock()),
        test_mls_store(),
        test_server_time_tracker(),
    );

    let app = build_app_with_service(default_app_state(), service).await;
    assert!(app.get_user_settings().await.is_err());
}

#[tokio::test]
async fn set_mls_group_update_handler_registers_on_service() {
    use crate::app::test_support::auth_service;
    use crate::domain::user::ports::{user_api::MockUserApi, MockUserRepository};

    let service = auth_service(MockUserApi::new(), MockUserRepository::new());
    let app = build_app_with_service(default_app_state(), service).await;

    app.set_mls_group_update_handler(|_meeting_id, _reason| Box::pin(async {}))
        .await;
}

#[tokio::test]
async fn set_mls_sync_state_update_handler_registers_on_service() {
    use crate::app::test_support::auth_service;
    use crate::domain::user::ports::{user_api::MockUserApi, MockUserRepository};

    let service = auth_service(MockUserApi::new(), MockUserRepository::new());
    let app = build_app_with_service(default_app_state(), service).await;

    app.set_mls_sync_state_update_handler(|_state, _reason| Box::pin(async {}))
        .await;
}

#[tokio::test]
async fn set_livekit_admin_change_handler_registers_on_service() {
    use crate::app::test_support::auth_service;
    use crate::domain::user::ports::{user_api::MockUserApi, MockUserRepository};

    let service = auth_service(MockUserApi::new(), MockUserRepository::new());
    let app = build_app_with_service(default_app_state(), service).await;

    app.set_livekit_admin_change_handler(|_room, _uid, _role| Box::pin(async {}))
        .await;
}

// --- Manual integration (real backend). Run: cargo test -p proton-meet-core app_creation -- --ignored ---

#[cfg(all(test, not(target_family = "wasm")))]
mod manual {
    use crate::app::test_support::manual;

    #[tokio::test]
    #[ignore = "requires popper atlas and local websocket on localhost:8090"]
    async fn app_creation() {
        let result = manual::app_for_atlas(
            "popper",
            "test/db_path",
            "localhost:8090",
            "macos-meet@0.0.1",
        )
        .await;
        assert!(result.is_ok(), "App creation should succeed");
    }
}
