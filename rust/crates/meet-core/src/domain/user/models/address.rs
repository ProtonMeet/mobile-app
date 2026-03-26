use serde::{Deserialize, Serialize};

use proton_meet_common::models::ProtonUserKey;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct Address {
    /// The address's ID.
    pub id: String,

    /// The address itself.
    pub email: String,

    /// The address's keys.
    pub keys: Vec<ProtonUserKey>,
}

impl From<&muon::rest::core::v4::addresses::Address> for Address {
    fn from(address: &muon::rest::core::v4::addresses::Address) -> Self {
        Self {
            id: address.id.clone(),
            email: address.email.clone(),
            keys: address
                .keys
                .iter()
                .map(|key| ProtonUserKey {
                    id: key.id.clone(),
                    version: 0,
                    private_key: key.private_key.clone(),
                    recovery_secret: None,
                    recovery_secret_signature: None,
                    token: key.token.clone(),
                    fingerprint: String::new(),
                    signature: key.signature.clone(),
                    primary: if key.primary.into() { 1 } else { 0 },
                    active: if key.active.into() { 1 } else { 0 },
                })
                .collect(),
        }
    }
}
