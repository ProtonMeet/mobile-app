use std::sync::Arc;

use crate::app::test_support::{
    build_app, build_app_with_test_http, default_app_state, state_with_active_participant,
    state_with_join_metrics_full, state_with_join_metrics_prereqs,
};
use crate::domain::user::ports::MockHttpClient;
use crate::errors::core::MeetCoreError;
use crate::infra::dto::realtime::RejoinReason;
use crate::utils::instant;

#[tokio::test]
async fn log_start_to_join_room_records_timestamp() {
    let app = build_app(default_app_state()).await;

    app.log_start_to_join_room().await.unwrap();

    let err = app.log_joined_room(None, None).await.unwrap_err();
    assert!(matches!(
        err,
        MeetCoreError::InternalError { message, .. } if message.contains("join_start_time")
    ));
}

#[tokio::test]
async fn log_joined_room_errors_when_join_start_time_missing() {
    let mut state = default_app_state();
    state.total_join_start_time = Some(instant::now());

    let app = build_app(state).await;
    let err = app.log_joined_room(None, None).await.unwrap_err();
    assert!(matches!(
        err,
        MeetCoreError::InternalError { message, .. } if message.contains("join_start_time")
    ));
}

#[tokio::test]
async fn log_joined_room_errors_when_total_join_start_time_missing() {
    let mut state = default_app_state();
    state.join_start_time = Some(instant::now());

    let app = build_app(state).await;
    let err = app.log_joined_room(None, None).await.unwrap_err();
    assert!(matches!(
        err,
        MeetCoreError::InternalError { message, .. } if message.contains("total_join_start_time")
    ));
}

#[tokio::test]
async fn log_joined_room_errors_when_participant_missing() {
    let mut state = default_app_state();
    state.join_start_time = Some(instant::now());
    state.total_join_start_time = Some(instant::now());

    let app = build_app(state).await;
    let err = app.log_joined_room(None, None).await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn log_joined_room_failed_errors_when_join_start_time_missing() {
    let app = build_app(default_app_state()).await;
    let err = app
        .log_joined_room_failed(Some("ERR".to_string()))
        .await
        .unwrap_err();
    assert!(matches!(
        err,
        MeetCoreError::InternalError { message, .. } if message.contains("join_start_time")
    ));
}

#[tokio::test]
async fn log_joined_room_failed_errors_when_total_join_start_time_missing() {
    let mut state = default_app_state();
    state.join_start_time = Some(instant::now());

    let app = build_app(state).await;
    let err = app
        .log_joined_room_failed(Some("ERR".to_string()))
        .await
        .unwrap_err();
    assert!(matches!(
        err,
        MeetCoreError::InternalError { message, .. } if message.contains("total_join_start_time")
    ));
}

#[tokio::test]
async fn log_joined_room_failed_errors_when_participant_missing() {
    let mut state = default_app_state();
    state.join_start_time = Some(instant::now());
    state.total_join_start_time = Some(instant::now());

    let app = build_app(state).await;
    let err = app
        .log_joined_room_failed(Some("ERR".to_string()))
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn log_connection_lost_errors_when_participant_missing() {
    let app = build_app(default_app_state()).await;
    let err = app.log_connection_lost().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn log_connection_lost_errors_before_metrics_available() {
    let app = build_app(state_with_active_participant("user-1")).await;
    assert!(app.log_connection_lost().await.is_err());
}

#[tokio::test]
async fn log_user_epoch_health_errors_when_participant_missing() {
    let app = build_app(default_app_state()).await;
    let err = app
        .log_user_epoch_health(1, "code".to_string())
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn try_log_designated_committer_is_noop_without_metrics() {
    let app = build_app(state_with_active_participant("user-1")).await;
    app.try_log_designated_committer(1).await.unwrap();
}

#[tokio::test]
async fn log_user_rejoin_errors_when_participant_missing() {
    let app = build_app(default_app_state()).await;
    let err = app
        .log_user_rejoin(100, 1, RejoinReason::WebsocketDisconnected, true)
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn log_joined_room_errors_when_app_version_missing() {
    let mut state = state_with_join_metrics_prereqs("user-1");
    state.app_version = None;

    let app = build_app(state).await;
    assert!(app.log_joined_room(Some(true), Some(false)).await.is_err());
}

#[tokio::test]
async fn log_joined_room_errors_when_user_agent_missing() {
    let mut state = state_with_join_metrics_prereqs("user-1");
    state.user_agent = None;

    let app = build_app(state).await;
    assert!(app.log_joined_room(Some(true), Some(false)).await.is_err());
}

#[tokio::test]
async fn log_joined_room_with_join_mls_time_fails_before_send_metrics() {
    let mut http = MockHttpClient::new();
    http.expect_send_metrics().times(0);

    let app =
        build_app_with_test_http(state_with_join_metrics_full("user-1"), Arc::new(http)).await;
    let err = app
        .log_joined_room(Some(true), Some(false))
        .await
        .unwrap_err();
    assert!(
        matches!(err, MeetCoreError::HttpClientError { message, .. } if message.contains("sd_kbt"))
    );
}

#[tokio::test]
async fn log_joined_room_failed_errors_when_user_agent_missing() {
    let mut state = state_with_join_metrics_prereqs("user-1");
    state.user_agent = None;

    let app = build_app(state).await;
    let err = app
        .log_joined_room_failed(Some("ERR".to_string()))
        .await
        .unwrap_err();
    assert!(matches!(
        err,
        MeetCoreError::InternalError { message, .. } if message.contains("user_agent")
    ));
}

#[tokio::test]
async fn log_user_epoch_health_fails_when_sd_kbt_unavailable() {
    let app = build_app(state_with_active_participant("user-1")).await;
    let err = app
        .log_user_epoch_health(1, "code".to_string())
        .await
        .unwrap_err();
    assert!(
        matches!(err, MeetCoreError::HttpClientError { message, .. } if message.contains("sd_kbt"))
    );
}

#[tokio::test]
async fn log_user_epoch_health_errors_when_user_agent_missing() {
    let mut state = state_with_active_participant("user-1");
    state.user_agent = None;

    let app = build_app(state).await;
    let err = app
        .log_user_epoch_health(1, "code".to_string())
        .await
        .unwrap_err();
    assert!(matches!(
        err,
        MeetCoreError::InternalError { message, .. } if message.contains("user_agent")
    ));
}

#[tokio::test]
async fn log_connection_lost_fails_when_sd_kbt_unavailable() {
    let app = build_app(state_with_active_participant("user-1")).await;
    let err = app.log_connection_lost().await.unwrap_err();
    assert!(
        matches!(err, MeetCoreError::HttpClientError { message, .. } if message.contains("sd_kbt"))
    );
}

#[tokio::test]
async fn log_user_rejoin_fails_when_sd_kbt_unavailable() {
    let app = build_app(state_with_active_participant("user-1")).await;
    let err = app
        .log_user_rejoin(100, 1, RejoinReason::WebsocketDisconnected, true)
        .await
        .unwrap_err();
    assert!(
        matches!(err, MeetCoreError::HttpClientError { message, .. } if message.contains("sd_kbt"))
    );
}

#[tokio::test]
async fn send_metrics_mock_not_called_when_sd_kbt_missing() {
    let mut http = MockHttpClient::new();
    http.expect_send_metrics().times(0);

    let app =
        build_app_with_test_http(state_with_join_metrics_full("user-1"), Arc::new(http)).await;
    assert!(app.log_joined_room(None, None).await.is_err());
}
