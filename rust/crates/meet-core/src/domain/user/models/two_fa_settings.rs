use serde::{Deserialize, Serialize};

/// Two Factor Authentication Settings
#[derive(Debug, Serialize, Deserialize, Default, Clone, PartialEq)]
#[serde(rename_all = "PascalCase")]
pub struct TwoFASettings {
    pub enabled: u32,
    pub allowed: u32,
}
