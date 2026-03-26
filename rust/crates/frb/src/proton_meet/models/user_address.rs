use flutter_rust_bridge::frb;

pub use proton_meet_core::domain::user::models::Address;
use proton_meet_core::ProtonUserKey;
#[frb(mirror(Address))]
pub struct _Address {
    /// The address's ID.
    pub id: String,

    /// The address itself.
    pub email: String,

    /// The address's keys.
    pub keys: Vec<ProtonUserKey>,
}
