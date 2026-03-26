use serde::{Deserialize, Serialize};
use crate::domain::user::models::participant_track_settings::ParticipantTrackSettings;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct ParticipantTrackSettingsRequest {
    pub access_token: String,
    #[serde(rename = "Audio")]
    pub audio: Option<u8>,
    #[serde(rename = "Video")]
    pub video: Option<u8>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ParticipantTrackSettingsResponse {
    pub audio: u8,
    pub video: u8,
    pub code: u32,
}

impl From<ParticipantTrackSettingsResponse> for ParticipantTrackSettings {
    fn from(response: ParticipantTrackSettingsResponse) -> Self {
        ParticipantTrackSettings {
            audio: response.audio,
            video: response.video,
        }
    }
}