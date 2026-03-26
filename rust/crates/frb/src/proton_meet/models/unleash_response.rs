use flutter_rust_bridge::frb;
pub use proton_meet_core::domain::user::models::UnleashResponse;

#[frb(mirror(UnleashResponse))]
pub struct _UnleashResponse {
    pub status_code: u16,
    pub body: Vec<u8>,
}
