pub mod app;
pub mod app_state;
pub mod domain;
pub mod errors;
pub mod infra;
pub mod service;
pub mod utils;
pub mod version;

#[cfg(test)]
mod app_test;

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
