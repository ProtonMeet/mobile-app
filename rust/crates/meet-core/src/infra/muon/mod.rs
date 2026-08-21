//! Muon 2.x client construction, persistence, and session helpers for Meet.
//!
//! - [`support`]: client builder, environment parsing, platform transport
//! - [`auth_store`]: native-only persistence (`Store`); WASM uses `without_persistence`

#[cfg(not(target_arch = "wasm32"))]
pub mod auth_store;
#[cfg(all(test, not(target_arch = "wasm32")))]
mod auth_store_test;
pub mod support;

#[cfg(not(target_arch = "wasm32"))]
pub use auth_store::{set_auth_persist_callback, AuthPersistCallback, AuthStore, SharedAuth};
pub use support::{
    build_meet_client, environment_from_str, is_prod_environment, meet_sdk_from_app,
    parse_environment, MeetClient, MeetClientExt, MeetContext, MeetSession,
    MUON_DEFAULT_SESSION_KEY,
};
