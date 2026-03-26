/*
   Module `ports` specifies the API by which external modules interact with the user domain.

   All traits are bounded by `Send + Sync + 'static`, since their implementations must be shareable
   between request-handling threads.

   Trait methods are explicitly asynchronous, including `Send` bounds on response types,
   since the application is expected to always run in a multithreaded environment.
*/

pub mod crypto_client;
pub mod event_api;
pub mod http_client;
pub mod meeting_api;
pub mod unleash_api;
pub mod user_api;
pub mod user_repository;
pub mod user_service;
mod websocket_callbacks;
pub mod websocket_client;

// Re-export all traits and types for convenient access
pub use crypto_client::*;
pub use event_api::*;
pub use http_client::*;
pub use unleash_api::*;
pub use user_repository::*;
pub use user_service::*;
pub use websocket_callbacks::*;
pub use websocket_client::*;
