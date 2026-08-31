use proton_meet_macro::unified_test;
use std::future::ready;

use crate::app::test_support::{build_app_with_ws, default_app_state, test_server_time_tracker};
use crate::domain::user::ports::{ConnectionState, MockWebSocketClient};

#[unified_test]
async fn get_ws_state_returns_mock_connection_state() {
    let mut ws = MockWebSocketClient::new();
    ws.expect_get_connection_state()
        .once()
        .returning(|| Box::pin(ready(ConnectionState::Connected)));

    let app = build_app_with_ws(ws, default_app_state()).await;
    let state = app.get_ws_state().await.unwrap();
    assert_eq!(state, ConnectionState::Connected);
}

#[unified_test]
async fn set_websocket_ping_interval_delegates_to_client() {
    let mut ws = MockWebSocketClient::new();
    ws.expect_set_ping_interval_seconds()
        .once()
        .withf(|seconds| *seconds == Some(30))
        .returning(|_| Box::pin(async {}));

    let app = build_app_with_ws(ws, default_app_state()).await;
    app.set_websocket_ping_interval(Some(30)).await.unwrap();
}

#[unified_test]
async fn set_websocket_max_ping_failures_delegates_to_client() {
    let mut ws = MockWebSocketClient::new();
    ws.expect_set_max_ping_failures()
        .once()
        .withf(|failures| *failures == Some(3))
        .returning(|_| Box::pin(async {}));

    let app = build_app_with_ws(ws, default_app_state()).await;
    app.set_websocket_max_ping_failures(Some(3)).await.unwrap();
}

#[unified_test]
async fn set_websocket_pong_timeout_delegates_to_client() {
    let mut ws = MockWebSocketClient::new();
    ws.expect_set_pong_timeout_seconds()
        .once()
        .withf(|seconds| *seconds == Some(10))
        .returning(|_| Box::pin(async {}));

    let app = build_app_with_ws(ws, default_app_state()).await;
    app.set_websocket_pong_timeout(Some(10)).await.unwrap();
}

#[unified_test]
async fn disconnect_wss_intentional_delegates_to_client() {
    let mut ws = MockWebSocketClient::new();
    ws.expect_disconnect()
        .once()
        .withf(|intentional| *intentional == Some(true))
        .returning(|_| Box::pin(ready(Ok(()))));

    let app = build_app_with_ws(ws, default_app_state()).await;
    app.disconnect_wss_intentional().await.unwrap();
}

#[unified_test]
async fn disconnect_wss_unintentional_delegates_to_client() {
    let mut ws = MockWebSocketClient::new();
    ws.expect_disconnect()
        .once()
        .withf(|intentional| *intentional == Some(false))
        .returning(|_| Box::pin(ready(Ok(()))));

    let app = build_app_with_ws(ws, default_app_state()).await;
    app.disconnect_wss_unintentional().await.unwrap();
}

#[unified_test]
async fn is_websocket_has_reconnected_delegates_to_service() {
    use std::sync::Arc;

    use crate::app::test_support::{build_app_with_ws_and_service, test_mls_store};
    use crate::domain::user::ports::{meeting_api::MockMeetingApi, MockHttpClient, MockMlsApi};
    use crate::service::user_service::Service;

    let mut ws = MockWebSocketClient::new();
    ws.expect_get_has_reconnected()
        .once()
        .returning(|| Box::pin(ready(true)));

    let ws = Arc::new(ws);
    let service = Service::new(
        Arc::new(MockHttpClient::new()),
        Arc::new(MockMlsApi::new()),
        Arc::new(MockMeetingApi::new()),
        ws.clone(),
        test_mls_store(),
        test_server_time_tracker(),
    );

    let app = build_app_with_ws_and_service(ws, default_app_state(), service).await;
    assert!(app.is_websocket_has_reconnected().await.unwrap());
}
