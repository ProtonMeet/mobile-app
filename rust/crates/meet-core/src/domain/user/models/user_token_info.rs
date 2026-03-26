use serde::{Deserialize, Serialize};

use super::user_id::UserId;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UserTokenInfo {
    pub user_identifier: meet_identifiers::UserId,
    pub device_id: String,
}

impl UserTokenInfo {
    pub fn user_id(&self) -> UserId {
        UserId::new(self.user_identifier.to_string())
    }
}
