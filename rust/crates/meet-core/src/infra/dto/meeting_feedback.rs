use serde::Serialize;

/// Request body for `POST /meet/v1/meetings/links/{meetingLinkName}/feedback`.
/// Matches the web client's `sendFeedback` payload (PascalCase keys).
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct MeetingFeedbackRequest {
    pub score: u8,
    pub feedback: String,
}
