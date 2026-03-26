pub struct FrbParticipantTrackSettings {
    pub audio: u8,
    pub video: u8,
}

impl From<proton_meet_core::domain::user::models::participant_track_settings::ParticipantTrackSettings> for FrbParticipantTrackSettings {
    fn from(participant_track_settings: proton_meet_core::domain::user::models::participant_track_settings::ParticipantTrackSettings) -> Self {
        Self {
            audio: participant_track_settings.audio,
            video: participant_track_settings.video,
        }
    }
}