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
pub struct GetSdCwtRequest<'a> {
    pub meet_link_name: &'a str,
    pub holder_confirmation_key: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub session_id: Option<&'a str>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct GetSdCwtResponse {
    pub token: String,
}
