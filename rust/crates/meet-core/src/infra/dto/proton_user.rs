use serde::{Deserialize, Serialize};

use muon::rest::core::v4::keys::salts::KeySalt;
use proton_meet_common::models::ProtonUser;

/// API Response wrapper for ProtonUser
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ApiProtonUserResponse {
    pub code: u32,
    pub user: ProtonUser,
}

/// User data containing user info and key salts
#[derive(Debug, Default)]
pub struct UserData {
    pub user: ProtonUser,
    pub key_salts: Vec<KeySalt>,
}
