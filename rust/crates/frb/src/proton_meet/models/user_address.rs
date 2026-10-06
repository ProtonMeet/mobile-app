use flutter_rust_bridge::frb;

use proton_meet_core::ProtonUserKey;
pub use proton_meet_core::domain::user::models::Address;
#[frb(mirror(Address))]
pub struct _Address {
    /// The address's ID.
    pub id: String,

    /// The address itself.
    pub email: String,

    /// The address's keys.
    pub keys: Vec<ProtonUserKey>,
}
