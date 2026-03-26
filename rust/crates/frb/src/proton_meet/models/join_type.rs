use flutter_rust_bridge::frb;
pub use proton_meet_core::infra::dto::realtime::JoinType;

#[frb(mirror(JoinType))]
#[repr(u8)]
pub enum _JoinType {
    ExternalCommit = 0,
    ExternalProposal = 1,
}
