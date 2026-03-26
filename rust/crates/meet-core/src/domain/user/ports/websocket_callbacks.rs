use crate::infra::ws_client::WebSocketMessage;
use futures::Future;
use std::pin::Pin;

/// Type alias for the callback that handles WebSocket messages
///
/// This callback bridges the Rust layer to external systems (e.g., Dart/Flutter, WASM)
/// to handle incoming WebSocket messages. It takes a WebSocketMessage and returns a pinned Future.
#[cfg(not(target_family = "wasm"))]
pub type WebSocketMessageHandler =
    dyn Fn(WebSocketMessage) -> Pin<Box<dyn Future<Output = ()> + Send>> + Send + Sync;

#[cfg(target_family = "wasm")]
pub type WebSocketMessageHandler = dyn Fn(WebSocketMessage) -> Pin<Box<dyn Future<Output = ()>>>;

/// Type alias for the callback that handles WebSocket disconnection events
///
/// This callback bridges the Rust layer to external systems (e.g., Dart/Flutter, WASM)
/// to notify when a WebSocket connection is disconnected.
#[cfg(not(target_family = "wasm"))]
pub type WebSocketDisconnectionHandler = dyn Fn(bool) + Send + Sync;

#[cfg(target_family = "wasm")]
pub type WebSocketDisconnectionHandler = dyn Fn(bool);
