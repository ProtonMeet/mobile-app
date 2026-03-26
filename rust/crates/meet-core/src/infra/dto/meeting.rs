use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::domain::user::models::meeting::{
    CreateMeetingParams, CustomPasswordSetting, Meeting, MeetingInfo, MeetingType,
    UpdateMeetingScheduleParams,
};
use crate::utils::serde::deserialize_timestamp;

/// Request payload for creating a new meeting
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct CreateMeetingRequest {
    /// Base64 encrypted meeting name
    pub name: String,
    /// Armored encrypted password
    pub password: Option<String>,
    /// BCrypt salt used for password hashing
    pub salt: String,
    /// Base64 encrypted session key
    pub session_key: String,
    /// SRP modulus ID for secure remote password protocol
    #[serde(rename = "SRPModulusID")]
    pub srp_modulus_id: String,
    /// SRP salt for secure remote password protocol
    #[serde(rename = "SRPSalt")]
    pub srp_salt: String,
    /// SRP verifier for secure remote password protocol
    #[serde(rename = "SRPVerifier")]
    pub srp_verifier: String,
    /// User address ID
    #[serde(rename = "AddressID")]
    pub address_id: Option<String>,
    /// Meeting start time in ISO format (e.g., "2024-01-01T10:00:00Z") or null
    pub start_time: Option<String>,
    /// Meeting end time in ISO format (e.g., "2024-01-01T11:00:00Z") or null
    pub end_time: Option<String>,
    /// Recurrence rule: "recurring", "scheduled", or null
    #[serde(rename = "RRule")]
    pub r_rule: Option<String>,
    /// Timezone string (e.g., "America/New_York") or null
    pub timezone: Option<String>,
    /// Custom password setting: 0 = NO_PASSWORD, 1 = PASSWORD_SET
    pub custom_password: u8,
    /// Meeting type enum value
    #[serde(rename = "Type")]
    pub meeting_type: u8,
}

impl From<CreateMeetingParams> for CreateMeetingRequest {
    fn from(params: CreateMeetingParams) -> Self {
        CreateMeetingRequest {
            name: params.name,
            password: params.password,
            salt: params.salt,
            session_key: params.session_key,
            srp_modulus_id: params.srp_modulus_id,
            srp_salt: params.srp_salt,
            srp_verifier: params.srp_verifier,
            address_id: params.address_id,
            start_time: params.start_time,
            end_time: params.end_time,
            r_rule: params.r_rule,
            timezone: params.time_zone,
            custom_password: params.custom_password,
            meeting_type: params.meeting_type,
        }
    }
}

impl From<UpdateMeetingScheduleParams> for UpdateMeetingScheduleRequest {
    fn from(params: UpdateMeetingScheduleParams) -> Self {
        UpdateMeetingScheduleRequest {
            start_time: params.start_time,
            end_time: params.end_time,
            timezone: params.time_zone,
            r_rule: params.r_rule,
        }
    }
}

/// Request payload for updating a meeting
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct EditMeetingNameRequest {
    /// Base64 encoded encrypted meeting name
    pub name: String,
}

/// Request payload for updating meeting schedule
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct UpdateMeetingScheduleRequest {
    /// Meeting start time in ISO format (e.g., "2024-01-01T10:00:00Z") or null
    pub start_time: Option<String>,
    /// Meeting end time in ISO format (e.g., "2024-01-01T11:00:00Z") or null
    pub end_time: Option<String>,
    /// Timezone string (e.g., "America/New_York") or null
    pub timezone: Option<String>,
    /// Recurrence rule or null
    #[serde(rename = "RRule")]
    pub r_rule: Option<String>,
}

/// Response payload for active meetings
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ActiveMeetingsResponse {
    /// The active meetings
    pub meetings: Vec<MeetingDto>,
    /// Response code (e.g., 1000 for success)
    pub code: u32,
}

/// Response payload for meeting creation
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct CreateMeetingResponse {
    /// The created meeting object
    pub meeting: MeetingDto,
    /// Response code (e.g., 1000 for success)
    pub code: u32,
}
pub type FetchMeetingResponse = CreateMeetingResponse;
pub type UpdateMeetingResponse = CreateMeetingResponse;

/// Meeting data transfer object containing all meeting details
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MeetingDto {
    /// Unique meeting UUID
    #[serde(rename = "ID")]
    pub id: String,
    /// Address ID associated with the meeting
    #[serde(rename = "AddressID")]
    pub address_id: Option<String>,
    /// Meeting link identifier/name
    pub meeting_link_name: String,
    /// Encrypted meeting name
    pub meeting_name: String,
    /// Encrypted password (null for unauth meetings)
    pub password: Option<String>,
    /// Custom password setting: 0 = NO_PASSWORD, 1 = PASSWORD_SET
    pub custom_password: u8,
    /// 1 if meeting was created from Proton Calendar
    pub proton_calendar: Option<u8>,
    /// BCrypt salt
    pub salt: String,
    /// Encrypted session key
    pub session_key: String,
    /// SRP modulus ID
    #[serde(rename = "SRPModulusID")]
    pub srp_modulus_id: String,
    /// SRP salt
    #[serde(rename = "SRPSalt")]
    pub srp_salt: String,
    /// SRP verifier
    #[serde(rename = "SRPVerifier")]
    pub srp_verifier: String,
    /// Meeting start time in ISO format (handles both integer Unix timestamp and string RFC3339)
    #[serde(default, deserialize_with = "deserialize_timestamp")]
    pub start_time: Option<String>,
    /// Meeting end time in ISO format (handles both integer Unix timestamp and string RFC3339)
    #[serde(default, deserialize_with = "deserialize_timestamp")]
    pub end_time: Option<String>,
    /// Recurrence rule
    #[serde(rename = "RRule")]
    pub r_rule: Option<String>,
    /// Timezone string
    #[serde(rename = "Timezone")]
    pub time_zone: Option<String>,
    /// Meeting type enum value
    #[serde(rename = "Type")]
    pub meeting_type: u8,
    /// When the meeting was created
    #[serde(default, deserialize_with = "deserialize_timestamp")]
    pub create_time: Option<String>,
    /// When the meeting was started for the last time
    #[serde(default, deserialize_with = "deserialize_timestamp")]
    pub last_used_time: Option<String>,
    /// Calendar ID associated with the meeting
    #[serde(rename = "CalendarID")]
    pub calendar_id: Option<String>,
    /// Linked CalendarEventID
    #[serde(rename = "CalendarEventID")]
    pub calendar_event_id: Option<String>,
}

impl TryFrom<MeetingDto> for Meeting {
    type Error = chrono::ParseError;

    fn try_from(dto: MeetingDto) -> Result<Self, Self::Error> {
        let start_time = dto
            .start_time
            .map(|time_str| DateTime::parse_from_rfc3339(&time_str))
            .transpose()?
            .map(|dt| dt.with_timezone(&Utc));

        let end_time = dto
            .end_time
            .map(|time_str| DateTime::parse_from_rfc3339(&time_str))
            .transpose()?
            .map(|dt| dt.with_timezone(&Utc));

        let create_time = dto
            .create_time
            .map(|time_str| DateTime::parse_from_rfc3339(&time_str))
            .transpose()?
            .map(|dt| dt.with_timezone(&Utc));

        let last_used_time = dto
            .last_used_time
            .map(|time_str| DateTime::parse_from_rfc3339(&time_str))
            .transpose()?
            .map(|dt| dt.with_timezone(&Utc));

        let meeting_type = match dto.meeting_type {
            0 => MeetingType::Instant,
            1 => MeetingType::Personal,
            2 => MeetingType::Scheduled,
            3 => MeetingType::Recurring,
            4 => MeetingType::Permanent,
            _ => MeetingType::Instant, // Default fallback
        };

        let custom_password = match dto.custom_password {
            0 => CustomPasswordSetting::NoPassword,
            1 => CustomPasswordSetting::PasswordSet,
            _ => CustomPasswordSetting::NoPassword, // Default fallback
        };

        Ok(Meeting {
            id: dto.id,
            address_id: dto.address_id,
            meeting_link_name: dto.meeting_link_name,
            meeting_name: dto.meeting_name,
            password: dto.password,
            salt: dto.salt,
            session_key: dto.session_key,
            srp_modulus_id: dto.srp_modulus_id,
            srp_salt: dto.srp_salt,
            srp_verifier: dto.srp_verifier,
            start_time,
            end_time,
            r_rule: dto.r_rule,
            time_zone: dto.time_zone,
            meeting_type,
            calendar_id: dto.calendar_id,
            custom_password,
            proton_calendar: dto.proton_calendar.unwrap_or(0),
            create_time,
            last_used_time,
            calendar_event_id: dto.calendar_event_id,
        })
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct UpcomingMeetingsResponse {
    pub meetings: Vec<MeetingDto>,
    pub code: u32,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MeetingInfoResponse {
    pub meeting_info: MeetingInfoDto,
    pub code: u32,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MeetingInfoDto {
    /// Unique meeting link name
    pub meeting_link_name: String,
    /// Encrypted meeting name with session key
    pub meeting_name: String,
    /// Salt of the password
    pub salt: String,
    /// Encrypted session key of the meeting
    pub session_key: String,
    /// 1 if meeting is locked
    pub locked: u8,
    /// Maximum duration of this meeting in seconds
    pub max_duration: u32,
    /// Maximum number of participants allowed in this meeting
    pub max_participants: u32,
    /// The datetime when the meeting room will be forcefully terminated
    #[serde(default, deserialize_with = "deserialize_timestamp")]
    pub expiration_time: Option<String>,
}

impl TryFrom<MeetingInfoDto> for MeetingInfo {
    type Error = chrono::ParseError;

    fn try_from(dto: MeetingInfoDto) -> Result<Self, Self::Error> {
        let expiration_time = dto
            .expiration_time
            .map(|time_str| DateTime::parse_from_rfc3339(&time_str))
            .transpose()?
            .map(|dt| dt.with_timezone(&Utc));

        Ok(MeetingInfo {
            meeting_link_name: dto.meeting_link_name,
            meeting_name: dto.meeting_name,
            salt: dto.salt,
            session_key: dto.session_key,
            locked: dto.locked,
            max_duration: dto.max_duration,
            max_participants: dto.max_participants,
            expiration_time,
        })
    }
}
