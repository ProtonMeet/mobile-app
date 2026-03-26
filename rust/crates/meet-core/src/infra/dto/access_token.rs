use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct AccessTokenRequest {
    pub display_name: String,
    pub encrypted_display_name: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct AccessTokenResponse {
    pub access_token: String,
    pub websocket_url: String,
    pub code: u32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct GetSdCwtRequest {
    pub meet_link_name: String,
    pub holder_confirmation_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct GetSdCwtResponse {
    pub token: String,
}
