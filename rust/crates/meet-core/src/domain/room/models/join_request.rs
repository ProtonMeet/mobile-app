use crate::domain::user::models::meeting_link_name::MeetingLinkName;

/// Waiting-room join request lifecycle event delivered to host callbacks.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JoinRequestChange {
    Added,
    Removed,
}

/// Join request body sent to meet-server (`application/octet-stream`).
#[derive(Debug, Clone)]
pub struct JoinRequest {
    pub encrypted_key_package: Vec<u8>,
    pub meeting_link_name: MeetingLinkName,
}

impl JoinRequest {
    pub fn new(encrypted_key_package: Vec<u8>, meeting_link_name: MeetingLinkName) -> Self {
        Self {
            encrypted_key_package,
            meeting_link_name,
        }
    }
}

/// Response from `POST /v1/joinRequest/{meeting_link_name}` (HTTP 202).
#[derive(Debug, Clone)]
pub struct SubmitJoinRequestResponse {
    pub request_id: String,
}
