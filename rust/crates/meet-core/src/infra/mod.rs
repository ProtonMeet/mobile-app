pub mod adapters;
pub mod crypto_client;
#[cfg(not(target_arch = "wasm32"))]
pub mod desktop_web_login;
#[cfg(not(target_arch = "wasm32"))]
pub mod desktop_web_login_manager;
pub mod dto;
pub mod event_api;
pub mod group_info_payload;
pub mod http_client;
pub mod http_client_util;
pub mod meeting_api;
pub mod message_cache;
pub mod mimi_subject_parser;
pub mod mls_response_ext;
pub mod muon;
pub mod ports;
pub mod proton_response_ext;
pub mod storage;
pub mod tls_pinning;
pub mod unleash_api;
pub mod user_api;
pub mod ws_client;
#[cfg(not(target_family = "wasm"))]
pub mod ws_connect;

// Backward-compatible re-exports for external crates (frb, meet-cli, e2e tests).
#[cfg(not(target_arch = "wasm32"))]
pub use muon::auth_store;
pub use muon::support as muon_support;

// Re-export ports and adapters for convenient access
pub use adapters::storage::{InMemorySecureStoreAdapter, UserKeyProviderAdapter};
pub use ports::{DbClient, SecureStore, SecureStoreResult, UserKeyProvider, UserKeyProviderResult};
