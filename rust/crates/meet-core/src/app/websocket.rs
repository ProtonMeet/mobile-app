use super::App;
use crate::domain::user::ports::ConnectionState;
use crate::errors::core::MeetCoreError;

impl App {
    pub async fn disconnect_wss_intentional(&self) -> Result<(), anyhow::Error> {
        self.ws_client.disconnect(Some(true)).await
    }

    pub async fn disconnect_wss_unintentional(&self) -> Result<(), anyhow::Error> {
        self.ws_client.disconnect(Some(false)).await
    }

    pub async fn get_ws_state(&self) -> Result<ConnectionState, MeetCoreError> {
        let ws_state = self.ws_client.get_connection_state().await;
        Ok(ws_state)
    }

    /// Set WebSocket ping interval in seconds (None to use default)
    pub async fn set_websocket_ping_interval(
        &self,
        seconds: Option<u64>,
    ) -> Result<(), MeetCoreError> {
        self.ws_client.set_ping_interval_seconds(seconds).await;
        Ok(())
    }

    /// Set WebSocket max ping failures (None to use default)
    pub async fn set_websocket_max_ping_failures(
        &self,
        failures: Option<u32>,
    ) -> Result<(), MeetCoreError> {
        self.ws_client.set_max_ping_failures(failures).await;
        Ok(())
    }

    /// Set WebSocket pong timeout in seconds (None to use default)
    pub async fn set_websocket_pong_timeout(
        &self,
        seconds: Option<u64>,
    ) -> Result<(), MeetCoreError> {
        self.ws_client.set_pong_timeout_seconds(seconds).await;
        Ok(())
    }

    pub async fn is_websocket_has_reconnected(&self) -> Result<bool, MeetCoreError> {
        let has_reconnected = self
            .services
            .user_service
            .read()
            .await
            .is_websocket_has_reconnected()
            .await;
        Ok(has_reconnected)
    }
}
