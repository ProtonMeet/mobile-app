use crate::errors::BridgeError;
use flutter_rust_bridge::frb;
pub use proton_meet_app::user_config::user_config::{
    ConfigStorage, UserConfig, VideoMaxBitrate, VideoResolution,
};

// save_config
pub fn save_config(user_config: UserConfig) -> Result<(), BridgeError> {
    user_config.save();
    Ok(())
}

// load_config
pub fn load_config() -> Result<UserConfig, BridgeError> {
    Ok(UserConfig::load())
}

#[frb(mirror(VideoResolution))]
pub enum _VideoResolution {
    P360,
    P720,
    P1080,
    P4k,
}

#[frb(mirror(VideoMaxBitrate))]
pub enum _VideoMaxBitrate {
    Kbps2000,
    Kbps1900,
    Kbps1800,
    Kbps1700,
    Kbps1600,
    Kbps1500,
    Kbps1400,
    Kbps1300,
    Kbps1200,
    Kbps1100,
    Kbps1000,
    Kbps900,
    Kbps800,
    Kbps700,
    Kbps600,
    Kbps500,
    Kbps400,
    Kbps300,
    Kbps200,
    Kbps100,
}

#[frb(mirror(UserConfig))]
pub struct _UserConfig {
    pub display_name: String,
    pub show_self_tile: bool,
    pub dark_mode: bool,
    pub camera_resolution: VideoResolution,
    pub camera_max_bitrate: VideoMaxBitrate,
    pub screensharing_resolution: VideoResolution,
    pub screensharing_max_bitrate: VideoMaxBitrate,
}
