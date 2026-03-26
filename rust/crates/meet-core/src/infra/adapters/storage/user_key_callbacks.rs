use futures::Future;
use proton_meet_common::models::ProtonUserKey;
use std::pin::Pin;

/// Type alias for the callback that fetches a user key from Dart/Flutter
///
/// This callback bridges the Rust layer to the Dart layer, which has access
/// to secure storage. It takes a user_id and returns a Key wrapped in a pinned Future.
pub type UserKeyFetcher =
    dyn Fn(String) -> Pin<Box<dyn Future<Output = ProtonUserKey> + Send>> + Send + Sync;

/// Type alias for the callback that fetches a user key passphrase from Dart/Flutter
///
/// This callback bridges the Rust layer to the Dart layer, which has access
/// to secure storage. It takes a user_id and returns the passphrase as a String
/// wrapped in a pinned Future.
pub type UserKeyPassphraseFetcher =
    dyn Fn(String) -> Pin<Box<dyn Future<Output = String> + Send>> + Send + Sync;

/// Type alias for Dart function futures
///
/// This represents a pinned future returned from Dart/Flutter function calls.
/// Used for both WASM and native platforms.
pub type DartFnFuture<T> = Pin<Box<dyn Future<Output = T> + Send>>;
