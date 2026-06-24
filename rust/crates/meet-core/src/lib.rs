/// Participant / MLS member count at or above which external-proposal join is used when
/// join-type switching is enabled. Must stay aligned with [`app::App::get_join_type`].
pub(crate) const JOIN_TYPE_SWITCH_THRESHOLD: u32 = 20;

pub mod app;
pub mod app_state;
pub mod chat;
pub mod domain;
pub mod errors;
pub mod infra;
pub mod service;
pub mod utils;
pub mod version;

pub mod muon {
    pub use muon::{
        client::{Auth, Tokens},
        env::EnvId,
        store::{Store, StoreError},
    };
}
pub use proton_meet_common::models::{ProtonUser, ProtonUserKey};

#[cfg(all(test, target_family = "wasm"))]
use wasm_bindgen_test::wasm_bindgen_test_configure;
#[cfg(all(test, target_family = "wasm"))]
wasm_bindgen_test_configure!(run_in_browser);
