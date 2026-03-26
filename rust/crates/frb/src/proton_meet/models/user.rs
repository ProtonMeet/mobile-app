use flutter_rust_bridge::frb;
pub use proton_meet_core::domain::user::models::UserId;
pub use proton_meet_core::ProtonUser;
use proton_meet_core::ProtonUserKey;
use std::collections::HashMap;

#[frb(mirror(UserId))]
pub struct _UserId {
    pub id: String,
}

#[frb(mirror(ProtonUser))]
pub struct _ProtonUser {
    pub id: String,
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
    pub flags: Option<HashMap<String, bool>>,
}
