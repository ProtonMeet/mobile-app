use flutter_rust_bridge::frb;
pub use proton_meet_core::ProtonUserKey;

#[frb(mirror(ProtonUserKey))]
pub struct _ProtonUserKey {
    pub id: String,
    pub version: u32,
    pub private_key: String,
    pub recovery_secret: Option<String>,
    pub recovery_secret_signature: Option<String>,
    pub token: Option<String>,
    pub fingerprint: String,
    pub signature: Option<String>,
    pub primary: u32,
    pub active: u32,
}
