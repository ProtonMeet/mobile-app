use crate::app::test_support::{
    build_app_with_http, default_app_state, unreachable_test_proton_http_client,
};
use crate::errors::core::MeetCoreError;

#[tokio::test]
async fn get_latest_event_id_propagates_http_error() {
    let app = build_app_with_http(
        default_app_state(),
        unreachable_test_proton_http_client().await,
    )
    .await;
    let err = app.get_latest_event_id().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::HttpClientError { .. }));
}

#[tokio::test]
async fn get_events_propagates_http_error() {
    let app = build_app_with_http(
        default_app_state(),
        unreachable_test_proton_http_client().await,
    )
    .await;
    assert!(app.get_events("event-1".to_string()).await.is_err());
}

#[tokio::test]
async fn get_core_events_propagates_http_error() {
    let app = build_app_with_http(
        default_app_state(),
        unreachable_test_proton_http_client().await,
    )
    .await;
    assert!(app.get_core_events("event-1".to_string()).await.is_err());
}
