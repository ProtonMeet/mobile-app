use flutter_rust_bridge::frb;
pub use proton_meet_core::domain::room::JoinRequestChange;
use proton_meet_core::domain::room::SubmitJoinRequestResponse;

/// Waiting-room join request lifecycle event delivered to host callbacks.
#[frb(mirror(JoinRequestChange))]
#[repr(u8)]
pub enum _JoinRequestChange {
    Added = 0,
    Removed = 1,
}

/// Response from submitting a waiting-room join request to meet-server.
#[derive(Debug, Clone)]
pub struct FrbSubmitJoinRequestResponse {
    pub request_id: String,
}

impl From<SubmitJoinRequestResponse> for FrbSubmitJoinRequestResponse {
    fn from(response: SubmitJoinRequestResponse) -> Self {
        Self {
            request_id: response.request_id,
        }
    }
}
