use serde::{Deserialize, Serialize};

use proton_meet_common::models::ProtonUserKey;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct Login {
    pub user_id: String,
    pub user_mail: String,
    pub user_name: String,
    pub mailbox_password: String,
    pub user_keys: Vec<ProtonUserKey>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct Modulus {
    pub modulus_id: String,
    pub modulus: String,
}
