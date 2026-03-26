use serde::{Deserialize, Serialize};

#[cfg(all(target_family = "wasm", feature = "wasm"))]
use wasm_bindgen::prelude::wasm_bindgen;

/// Proton User Key model
#[cfg_attr(
    all(target_family = "wasm", feature = "wasm"),
    wasm_bindgen(getter_with_clone)
)]
#[derive(Debug, Serialize, Deserialize, Clone, PartialEq)]
#[serde(rename_all = "PascalCase")]
pub struct ProtonUserKey {
    #[serde(rename = "ID")]
    pub id: String,
    pub version: u32,
    pub private_key: String,
    pub recovery_secret: Option<String>,
    pub recovery_secret_signature: Option<String>,
    pub token: Option<String>,
    pub fingerprint: String,
    pub signature: Option<String>,
    pub primary: u32,
    pub active: u32,
}
