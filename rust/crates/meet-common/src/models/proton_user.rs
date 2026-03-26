use crate::models::ProtonUserKey;
use serde::{Deserialize, Deserializer, Serialize};
use std::collections::HashMap;

#[cfg(all(target_family = "wasm", feature = "wasm"))]
use wasm_bindgen::prelude::wasm_bindgen;

/// Proton User model
#[cfg_attr(
    all(target_family = "wasm", feature = "wasm"),
    wasm_bindgen(getter_with_clone)
)]
#[derive(Debug, Serialize, Deserialize, Default, Clone, PartialEq)]
#[serde(rename_all = "PascalCase")]
pub struct ProtonUser {
    #[serde(rename = "ID")]
    pub id: String,
    #[serde(default, deserialize_with = "deserialize_string_or_default")]
    pub name: String,
    pub used_space: u64,
    pub currency: String,
    pub credit: u32,
    pub create_time: u64,
    pub max_space: u64,
    pub max_upload: u64,
    pub role: u32,
    pub private: u32,
    pub subscribed: u32,
    pub services: u32,
    pub delinquent: u32,
    pub organization_private_key: Option<String>,
    pub email: String,
    pub display_name: Option<String>,
    pub keys: Option<Vec<ProtonUserKey>>,
    pub mnemonic_status: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub flags: Option<HashMap<String, bool>>,
}

fn deserialize_string_or_default<'de, D>(deserializer: D) -> Result<String, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<String>::deserialize(deserializer)?.unwrap_or_default();
    let trimmed = value.trim();
    if trimmed.eq_ignore_ascii_case("null") {
        return Ok(String::new());
    }
    Ok(trimmed.to_string())
}
