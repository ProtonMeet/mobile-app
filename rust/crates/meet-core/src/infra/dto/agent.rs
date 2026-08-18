use serde::Serialize;

/// Request body for `POST /meet/v1/meetings/links/{meetingLinkName}/agents`.
/// Matches the web client's payload (PascalCase keys).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct AddAgentRequest {
    pub agent_type: u8,
}
