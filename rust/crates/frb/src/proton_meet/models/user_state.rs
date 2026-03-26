use flutter_rust_bridge::frb;

pub use proton_meet_core::app_state::UserState;
use proton_meet_core::{domain::user::models::Address, ProtonUser, ProtonUserKey};

#[allow(dead_code)]
#[frb(mirror(UserState))]
pub struct _UserState {
    user_data: ProtonUser,
    user_keys: Vec<ProtonUserKey>,
    user_addresses: Vec<Address>,
}
