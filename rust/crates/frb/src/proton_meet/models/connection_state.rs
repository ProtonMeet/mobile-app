use flutter_rust_bridge::frb;
pub use proton_meet_core::domain::user::ports::websocket_client::ConnectionState;

#[frb(mirror(ConnectionState))]
pub enum _ConnectionState {
    Disconnected = 0,
    Connecting = 1,
    Connected = 2,
    Reconnecting = 3,
}

