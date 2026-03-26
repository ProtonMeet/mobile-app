use flutter_rust_bridge::frb;
pub use proton_meet_core::service::service_state::MlsSyncState;

#[frb(mirror(MlsSyncState))]
#[repr(u8)]
pub enum _MlsSyncState {
    Success = 0,
    Checking = 1,
    Retrying = 2,
    Failed = 3,
}
