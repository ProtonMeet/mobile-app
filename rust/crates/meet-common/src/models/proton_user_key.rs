use serde::{Deserialize, Serialize};

#[cfg(all(target_family = "wasm", feature = "wasm"))]
use wasm_bindgen::prelude::wasm_bindgen;

/// Proton User Key model
#[cfg_attr(
    all(target_family = "wasm", feature = "wasm"),
    wasm_bindgen(getter_with_clone)
)]
#[derive(Serialize, Deserialize, Clone, PartialEq)]
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

impl std::fmt::Debug for ProtonUserKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ProtonUserKey")
            .field("id", &self.id)
            .field("version", &self.version)
            .field("private_key", &"<redacted>")
            .field(
                "recovery_secret",
                &self.recovery_secret.as_ref().map(|_| "<redacted>"),
            )
            .field(
                "recovery_secret_signature",
                &self
                    .recovery_secret_signature
                    .as_ref()
                    .map(|_| "<redacted>"),
            )
            .field("token", &self.token.as_ref().map(|_| "<redacted>"))
            .field("fingerprint", &self.fingerprint)
            .field("signature", &self.signature.as_ref().map(|_| "<redacted>"))
            .field("primary", &self.primary)
            .field("active", &self.active)
            .finish()
    }
}
