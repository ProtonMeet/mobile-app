use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct EndMeetingRequest {
    pub access_token: String,
}
