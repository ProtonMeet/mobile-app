// don't add mod user_config { }  in this file

use serde::{Deserialize, Serialize};

#[cfg(not(target_family = "wasm"))]
use confy;

#[cfg(target_family = "wasm")]
use web_sys;

#[cfg(not(target_family = "wasm"))]
const APP_NAME: &str = "proton_meet";

const USER_CONFIG_FILENAME: &str = "user_config";

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum VideoResolution {
    P360,
    P720,
    P1080,
    P4k,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub enum VideoMaxBitrate {
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

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct UserConfig {
    pub display_name: String,
    pub show_self_tile: bool,
    pub dark_mode: bool,
    pub camera_resolution: VideoResolution,
    pub camera_max_bitrate: VideoMaxBitrate,
    pub screensharing_resolution: VideoResolution,
    pub screensharing_max_bitrate: VideoMaxBitrate,
}

impl UserConfig {
    pub fn update_display_name(&self, display_name: String) -> Self {
        Self {
            display_name,
            ..self.clone()
        }
    }

    pub fn update_show_self_tile(&self, show_self_tile: bool) -> Self {
        Self {
            show_self_tile,
            ..self.clone()
        }
    }

    pub fn update_dark_mode(&self, dark_mode: bool) -> Self {
        Self {
            dark_mode,
            ..self.clone()
        }
    }

    pub fn update_camera_resolution(&self, camera_resolution: VideoResolution) -> Self {
        Self {
            camera_resolution,
            ..self.clone()
        }
    }

    pub fn update_camera_max_bitrate(&self, camera_max_bitrate: VideoMaxBitrate) -> Self {
        Self {
            camera_max_bitrate,
            ..self.clone()
        }
    }

    pub fn update_screensharing_resolution(
        &self,
        screensharing_resolution: VideoResolution,
    ) -> Self {
        Self {
            screensharing_resolution,
            ..self.clone()
        }
    }

    pub fn update_screensharing_max_bitrate(
        &self,
        screensharing_max_bitrate: VideoMaxBitrate,
    ) -> Self {
        Self {
            screensharing_max_bitrate,
            ..self.clone()
        }
    }
}

impl Default for UserConfig {
    fn default() -> Self {
        UserConfig {
            display_name: "".to_string(),
            show_self_tile: true,
            dark_mode: false,
            camera_resolution: VideoResolution::P720,
            camera_max_bitrate: VideoMaxBitrate::Kbps500,
            screensharing_resolution: VideoResolution::P1080,
            screensharing_max_bitrate: VideoMaxBitrate::Kbps1000,
        }
    }
}

pub trait ConfigStorage {
    fn load() -> Self
    where
        Self: Sized;
    fn save(&self);
}

#[cfg(not(target_family = "wasm"))]
impl ConfigStorage for UserConfig {
    fn load() -> Self {
        confy::load(APP_NAME, USER_CONFIG_FILENAME).unwrap_or_default()
    }

    fn save(&self) {
        let _ = confy::store(APP_NAME, USER_CONFIG_FILENAME, self);
    }
}

#[cfg(target_family = "wasm")]
impl ConfigStorage for UserConfig {
    fn load() -> Self {
        let storage = web_sys::window().unwrap().local_storage().unwrap().unwrap();
        storage
            .get_item(USER_CONFIG_FILENAME)
            .ok()
            .flatten()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    fn save(&self) {
        let storage = web_sys::window().unwrap().local_storage().unwrap().unwrap();
        let _ = storage.set_item(USER_CONFIG_FILENAME, &serde_json::to_string(self).unwrap());
    }
}
