use super::mls_sync_state::MlsSyncState;
use super::rejoin_reason::RejoinReason;
use proton_meet_core::app_state::UserState;

#[derive(Clone, Debug)]
pub enum AppEvent {
    UserStateChanged(Box<UserState>),
    ConnectionChanged {
        connected: bool,
    },
    Error {
        message: String,
    },
    MlsGroupUpdated {
        room_id: String,
        key: String,
        epoch: u64,
    },
    MlsSyncStateChanged {
        state: MlsSyncState,
        reason: Option<RejoinReason>,
    },
}
