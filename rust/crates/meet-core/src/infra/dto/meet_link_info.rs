use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::domain::user::models::meet_link_info::{
    MeetLinkAuthInfo, MeetLinkInfo, MeetParticipant,
};
use crate::domain::user::models::meeting::MeetingInfo;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MeetLinkInfoResponse {
    pub modulus: String,
    pub salt: String,
    pub server_ephemeral: String,
    #[serde(rename = "SRPSession")]
    pub srp_session: String,
    pub version: u32,
    pub code: u32,
}

impl From<MeetLinkInfoResponse> for MeetLinkInfo {
    fn from(response: MeetLinkInfoResponse) -> Self {
        MeetLinkInfo {
            modulus: response.modulus,
            salt: response.salt,
            server_ephemeral: response.server_ephemeral,
            srp_session: response.srp_session,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MeetParticipantsResponse {
    pub participants: Vec<MeetParticipant>,
    pub code: u32,
}

impl From<MeetParticipantsResponse> for Vec<MeetParticipant> {
    fn from(response: MeetParticipantsResponse) -> Self {
        response.participants
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MeetParticipantsCountResponse {
    pub current: u32,
    pub code: u32,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct AuthMeetLinkRequest {
    pub client_ephemeral: String,
    pub client_proof: String,
    #[serde(rename = "SRPSession")]
    pub srp_session: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct AuthMeetLinkResponse {
    pub server_proof: String,
    #[serde(rename = "UID")]
    pub uid: String,
    pub access_token: Option<String>,
    pub token_type: Option<String>,
    pub code: u32,
}

impl From<AuthMeetLinkResponse> for MeetLinkAuthInfo {
    fn from(response: AuthMeetLinkResponse) -> Self {
        MeetLinkAuthInfo {
            server_proof: response.server_proof,
            uid: response.uid,
            access_token: response.access_token,
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MeetInfoResponse {
    pub meeting_info: MeetingInfoDto,
    pub code: u32,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MeetingInfoDto {
    pub meeting_link_name: String,
    pub meeting_name: String,
    pub salt: String,
    pub session_key: String,
    pub locked: u8,
    pub max_duration: u32,
    pub max_participants: u32,
    pub expiration_time: Option<i64>,
}

impl From<MeetInfoResponse> for MeetingInfo {
    fn from(response: MeetInfoResponse) -> Self {
        MeetingInfo {
            meeting_link_name: response.meeting_info.meeting_link_name,
            meeting_name: response.meeting_info.meeting_name,
            salt: response.meeting_info.salt,
            session_key: response.meeting_info.session_key,
            locked: response.meeting_info.locked,
            max_duration: response.meeting_info.max_duration,
            max_participants: response.meeting_info.max_participants,
            expiration_time: response
                .meeting_info
                .expiration_time
                .and_then(|timestamp| DateTime::from_timestamp(timestamp, 0))
                .map(|dt| dt.with_timezone(&Utc)),
        }
    }
}
