use serde::{Deserialize, Serialize};

/// Referral Settings (empty struct for API compatibility)
#[derive(Debug, Serialize, Deserialize, Default, Clone, PartialEq)]
#[serde(rename_all = "PascalCase")]
pub struct ReferralSettings {
    // ReferralSettings is empty here we need it in the parser but we don't use it yet in our implementation
}
