use serde::{Deserialize, Serialize};

/// Email Settings
#[derive(Debug, Serialize, Deserialize, Default, Clone, PartialEq)]
#[serde(rename_all = "PascalCase")]
pub struct EmailSettings {
    pub value: Option<String>,
    pub status: u32,
    pub notify: u32,
    pub reset: u32,
}
