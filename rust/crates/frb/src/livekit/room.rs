use std::sync::Arc;

use flutter_rust_bridge::frb;
use livekit::{
    options::TrackPublishOptions,
    track::{LocalAudioTrack, LocalTrack, TrackSource},
    webrtc::{
        audio_source::native::NativeAudioSource,
        prelude::{AudioFrame, AudioSourceOptions, RtcAudioSource},
    },
    Room, RoomOptions,
};

pub struct FrbRoom {
    inner: Arc<Room>,
}

impl FrbRoom {
    pub async fn new(url: String, token: String) -> Result<Self, BridgeError> {
        let (room, mut rx) = Room::connect(&url, &token, RoomOptions::default()).await?;

        let arc_room = Arc::new(room);
        Self { inner: arc_room }
    }
}
