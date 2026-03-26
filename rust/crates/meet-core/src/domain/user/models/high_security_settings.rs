use serde::{Deserialize, Serialize};

/// High Security Settings
#[derive(Debug, Serialize, Deserialize, Default, Clone, PartialEq)]
#[serde(rename_all = "PascalCase")]
pub struct HighSecuritySettings {
    pub eligible: u32,
    pub value: u32,
}
