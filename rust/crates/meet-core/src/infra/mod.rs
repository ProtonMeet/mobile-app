pub mod adapters;
pub mod auth_store;
pub mod crypto_client;
pub mod dto;
pub mod event_api;
pub mod http_client;
pub mod http_client_util;
pub mod meeting_api;
pub mod message_cache;
pub mod mimi_subject_parser;
pub mod mls_response_ext;
pub mod ports;
pub mod proton_response_ext;
pub mod storage;
pub mod unleash_api;
pub mod user_api;
pub mod ws_client;
pub mod tls_pinning;

// Re-export ports and adapters for convenient access
pub use adapters::storage::{InMemorySecureStoreAdapter, UserKeyProviderAdapter};
pub use ports::{DbClient, SecureStore, SecureStoreResult, UserKeyProvider, UserKeyProviderResult};
