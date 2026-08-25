use serde::Serialize;

/// Request body for `POST /meet/v1/meetings/links/{meetingLinkName}/agents`.
/// Matches the web client's payload (PascalCase keys).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct AddAgentRequest {
    pub agent_type: u8,
}

/// Request body for `PUT /meet/v1/meetings/links/{meetingLinkName}/agents/{agentType}/available`.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct SetAgentAvailabilityRequest {
    pub available: u8,
}
