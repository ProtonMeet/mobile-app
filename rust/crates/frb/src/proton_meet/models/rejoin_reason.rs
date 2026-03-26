use flutter_rust_bridge::frb;
pub use proton_meet_core::infra::dto::realtime::RejoinReason;

#[frb(mirror(RejoinReason))]
#[repr(i32)]
pub enum _RejoinReason {
    EpochMismatch = 0,
    WebsocketDisconnected = 1,
    MemberNotFoundInMLS = 2,
    FetchTimeout = 3,
    LivekitStateMismatch = 4,
    LivekitConnectionTimeout = 5,
    Other = 6,
}
