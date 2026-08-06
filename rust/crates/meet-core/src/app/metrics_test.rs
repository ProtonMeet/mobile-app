use std::sync::Arc;

use crate::app::test_support::{
    app_state_with_mls_participant, build_app, build_app_with_service_and_mls_api,
    build_app_with_test_mls_api, default_app_state, join_test_service_with_mls_client,
    state_with_active_participant, state_with_join_metrics_full, state_with_join_metrics_prereqs,
};
use crate::domain::user::ports::MockMlsApi;
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
async fn log_joined_room_sends_metrics_through_mls_api() {
    let (service, user_info, mls_store) =
        join_test_service_with_mls_client("user-1", "LINK123").await;
    let mut mls = MockMlsApi::new();
    mls.expect_send_metrics()
        .withf(|sd_kbt, app_version, user_agent, request| {
            !sd_kbt.is_empty()
                && app_version == "macos-meet@1.0.0"
                && user_agent == "Mac OS X 10.15.7"
                && request.user_join_time.is_some()
        })
        .once()
        .returning(|_, _, _, _| Box::pin(async { Ok(()) }));

    let state = app_state_with_mls_participant(
        state_with_join_metrics_full("user-1"),
        mls_store,
        user_info,
        None,
    );
    let app = build_app_with_service_and_mls_api(state, service, Arc::new(mls)).await;

    app.log_joined_room(Some(true), Some(false)).await.unwrap();
}

#[tokio::test]
async fn log_joined_room_with_join_mls_time_fails_before_send_metrics() {
    let mut mls = MockMlsApi::new();
    mls.expect_send_metrics().times(0);

    let app =
        build_app_with_test_mls_api(state_with_join_metrics_full("user-1"), Arc::new(mls)).await;
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
    let mut mls = MockMlsApi::new();
    mls.expect_send_metrics().times(0);

    let app =
        build_app_with_test_mls_api(state_with_join_metrics_full("user-1"), Arc::new(mls)).await;
    assert!(app.log_joined_room(None, None).await.is_err());
}
