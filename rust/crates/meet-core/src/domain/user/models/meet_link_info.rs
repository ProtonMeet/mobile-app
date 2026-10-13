use serde::{Deserialize, Serialize};
#[cfg(target_family = "wasm")]
use wasm_bindgen::prelude::wasm_bindgen;

#[derive(Debug, Clone)]
pub struct MeetLinkInfo {
    pub modulus: String,
    pub salt: String,
    pub server_ephemeral: String,
    pub srp_session: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MeetParticipant {
    #[serde(rename = "ParticipantUUID")]
    pub participant_uuid: String,
    #[serde(default)]
    pub display_name: Option<String>,
    #[serde(default)]
    pub encrypted_display_name: Option<String>,
    pub can_subscribe: Option<u8>,
    pub can_publish: Option<u8>,
    pub can_publish_data: Option<u8>,
    pub is_admin: Option<u8>,
    pub is_host: Option<u8>,
}

#[derive(Debug, Clone)]
pub struct MeetLinkAuthInfo {
    pub server_proof: String,
    pub uid: String,
    pub access_token: Option<String>,
}

#[derive(Debug, Clone)]
pub struct AccessTokenInfo {
    pub access_token: String,
    pub websocket_url: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct MeetInfo {
    pub meet_name: String,
    pub meet_link_name: String,
    pub access_token: String,
    pub websocket_url: String,
    // participants count when join the meeting, used for display in loading page
    pub participants_count: u32,
    pub is_locked: bool,
    pub has_waiting_room: bool,
    pub max_duration: u32,
    pub max_participants: u32,
    /// Unix timestamp in seconds (`Option<i64>`)
    pub expiration_time: Option<i64>,
    /// Salt of the password. Carried from the meeting-info response fetched during
    /// SRP auth so callers (pre-join) don't need a second `get_meeting_info` round trip.
    pub salt: String,
    /// Encrypted session key of the meeting. See [`Self::salt`].
    pub session_key: String,
    /// 1 if the current session can manage the waiting room (host). See [`Self::salt`].
    pub manage_waiting_room: u8,
    /// 1 if the meeting is personal. See [`Self::salt`].
    pub personal_meeting: u8,
}
