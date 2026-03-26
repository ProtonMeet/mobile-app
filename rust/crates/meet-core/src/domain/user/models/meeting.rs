use std::sync::Arc;

use chrono::{DateTime, Utc};
use proton_meet_crypto::{SessionKeyAlgorithm, MEET_METADATA_AAD};
use tracing::info;

use crate::domain::user::{models::login::Modulus, ports::CryptoClient};

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum MeetingType {
    #[default]
    Instant = 0,
    Personal = 1,
    Scheduled = 2,
    Recurring = 3,
    Permanent = 4,
}

#[derive(Debug, Clone)]
pub enum MeetingState {
    Active = 0,
    Archived = 1,
}

/// Custom password setting for meetings
#[derive(Debug, Clone, PartialEq, Copy, Default)]
pub enum CustomPasswordSetting {
    /// No password required (0)
    #[default]
    NoPassword = 0,
    /// Password is set (1)
    PasswordSet = 1,
}

/// Meeting information containing meeting details
#[derive(Debug, Clone)]
pub struct MeetingInfo {
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
    pub expiration_time: Option<DateTime<Utc>>,
}

/// Domain object representing a meeting
#[derive(Debug, Clone, Default)]
pub struct Meeting {
    /// Unique meeting identifier
    pub id: String,
    /// Address ID associated with the meeting
    pub address_id: Option<String>,
    /// Meeting link identifier/name
    pub meeting_link_name: String,
    /// Encrypted meeting name
    pub meeting_name: String,
    /// Encrypted password
    pub password: Option<String>,
    /// Custom password setting
    pub custom_password: CustomPasswordSetting,
    /// 1 if meeting was created from Proton Calendar
    pub proton_calendar: u8,
    /// BCrypt salt
    pub salt: String,
    /// Encrypted session key
    pub session_key: String,
    /// SRP modulus ID
    pub srp_modulus_id: String,
    /// SRP salt
    pub srp_salt: String,
    /// SRP verifier
    pub srp_verifier: String,
    /// Meeting start time
    pub start_time: Option<DateTime<Utc>>,
    /// Meeting end time
    pub end_time: Option<DateTime<Utc>>,
    /// Recurrence rule (ignored for now)
    pub r_rule: Option<String>,
    /// Timezone string
    pub time_zone: Option<String>,
    /// Meeting type
    pub meeting_type: MeetingType,
    /// When the meeting was created
    pub create_time: Option<DateTime<Utc>>,
    /// When the meeting was started for the last time
    pub last_used_time: Option<DateTime<Utc>>,
    /// Calendar ID associated with the meeting
    pub calendar_id: Option<String>,
    /// Linked CalendarEventID
    pub calendar_event_id: Option<String>,
}

#[derive(Debug, Clone)]
pub struct UpcomingMeeting {
    pub id: String,
    pub address_id: Option<String>,
    pub meeting_link_name: String,
    pub meeting_name: String,
    pub meeting_password: String,
    pub meeting_type: MeetingType,
    pub start_time: Option<DateTime<Utc>>,
    pub end_time: Option<DateTime<Utc>>,
    pub r_rule: Option<String>,
    pub time_zone: Option<String>,
    pub calendar_id: Option<String>,
    pub proton_calendar: u8,
    pub create_time: Option<DateTime<Utc>>,
    pub last_used_time: Option<DateTime<Utc>>,
    pub calendar_event_id: Option<String>,
}

/// Domain object for creating a new meeting
#[derive(Debug, Clone)]
pub struct CreateMeeting {
    /// Plain text meeting name (will be encrypted)
    pub meeting_name: String,
    /// Plain text password (will be encrypted)
    pub password: String,
    /// User address ID
    pub address_id: Option<String>,
    /// Meeting start time
    pub start_time: Option<DateTime<Utc>>,
    /// Meeting end time
    pub end_time: Option<DateTime<Utc>>,
    /// Timezone for the meeting
    pub time_zone: Option<String>,
    /// Recurrence rule
    pub r_rule: Option<String>,
    /// Custom password setting
    pub custom_password: CustomPasswordSetting,
    /// Type of meeting
    pub meeting_type: MeetingType,
}

impl CreateMeeting {
    /// Creates a personal meeting
    pub fn personal(
        meeting_name: String,
        password: String,
        address_id: String,
        custom_password: CustomPasswordSetting,
    ) -> Self {
        Self {
            meeting_name,
            password,
            address_id: Some(address_id),
            start_time: None,
            end_time: None,
            time_zone: None,
            r_rule: None,
            custom_password,
            meeting_type: MeetingType::Personal,
        }
    }

    /// Creates a new instant meeting
    pub fn instant(
        meeting_name: String,
        password: String,
        address_id: Option<String>,
        custom_password: CustomPasswordSetting,
    ) -> Self {
        Self {
            meeting_name,
            password,
            address_id,
            start_time: None,
            end_time: None,
            time_zone: None,
            r_rule: None,
            custom_password,
            meeting_type: MeetingType::Instant,
        }
    }

    /// Creates a new scheduled meeting
    pub fn scheduled(
        meeting_name: String,
        password: String,
        address_id: String,
        start_time: Option<DateTime<Utc>>,
        end_time: Option<DateTime<Utc>>,
        time_zone: Option<String>,
        custom_password: CustomPasswordSetting,
    ) -> Self {
        Self {
            meeting_name,
            password,
            address_id: Some(address_id),
            start_time,
            end_time,
            time_zone,
            r_rule: None,
            custom_password,
            meeting_type: MeetingType::Scheduled,
        }
    }

    /// Creates a new permanent meeting
    pub fn permanent(
        meeting_name: String,
        password: String,
        address_id: String,
        start_time: Option<DateTime<Utc>>,
        end_time: Option<DateTime<Utc>>,
        time_zone: Option<String>,
        custom_password: CustomPasswordSetting,
    ) -> Self {
        Self {
            meeting_name,
            password,
            address_id: Some(address_id),
            start_time,
            end_time,
            time_zone,
            r_rule: None,
            custom_password,
            meeting_type: MeetingType::Permanent,
        }
    }

    /// Creates a new recurring meeting
    #[allow(clippy::too_many_arguments)]
    pub fn recurring(
        meeting_name: String,
        password: String,
        address_id: String,
        start_time: DateTime<Utc>,
        end_time: Option<DateTime<Utc>>,
        time_zone: Option<String>,
        r_rule: Option<String>,
        custom_password: CustomPasswordSetting,
    ) -> Self {
        Self {
            meeting_name,
            password,
            address_id: Some(address_id),
            start_time: Some(start_time),
            end_time,
            time_zone,
            r_rule,
            custom_password,
            meeting_type: MeetingType::Recurring,
        }
    }

    pub async fn generate_params_unauth(
        &self,
        modulus: &Modulus,
        crypto_client: &Arc<dyn CryptoClient>,
    ) -> Result<CreateMeetingParams, proton_meet_crypto::CryptoError> {
        info!("generate_params_unauth start");
        let salt = crypto_client.generate_salt().await?;

        let password_hash = crypto_client
            .compute_key_password(&self.password, &salt)
            .await?;

        let session_key = crypto_client
            .generate_session_key(SessionKeyAlgorithm::Aes256)
            .await?;

        let encrypted_session_key = crypto_client
            .encrypt_session_key_with_passphrase(&session_key, &password_hash)
            .await?;

        let srp_verifier = crypto_client
            .get_srp_verifier(&modulus.modulus, &self.password)
            .await?;

        let encrypted_meeting_name = crypto_client
            .encrypt_message(&self.meeting_name, &session_key, MEET_METADATA_AAD)
            .await?;

        Ok(CreateMeetingParams {
            name: encrypted_meeting_name,
            password: None,
            salt,
            session_key: encrypted_session_key,
            srp_modulus_id: modulus.modulus_id.clone(),
            srp_salt: srp_verifier.salt,
            srp_verifier: srp_verifier.verifier,
            address_id: None,
            start_time: self.start_time.map(|dt| dt.to_rfc3339()),
            end_time: self.end_time.map(|dt| dt.to_rfc3339()),
            r_rule: None,
            time_zone: self.time_zone.clone(),
            custom_password: self.custom_password as u8,
            meeting_type: self.meeting_type as u8,
        })
    }

    pub async fn generate_params(
        &self,
        modulus: &Modulus,
        user_private_key: String,
        private_key_passphrase: String,
        crypto_client: &Arc<dyn CryptoClient>,
    ) -> Result<CreateMeetingParams, proton_meet_crypto::CryptoError> {
        let salt = crypto_client.generate_salt().await?;

        let password_hash = crypto_client
            .compute_key_password(&self.password, &salt)
            .await?;

        let session_key = crypto_client
            .generate_session_key(SessionKeyAlgorithm::Aes256)
            .await?;

        let encrypted_session_key = crypto_client
            .encrypt_session_key_with_passphrase(&session_key, &password_hash)
            .await?;

        let encrypted_password = crypto_client
            .openpgp_encrypt_message(&self.password, &user_private_key, &private_key_passphrase)
            .await?;

        let srp_verifier = crypto_client
            .get_srp_verifier(&modulus.modulus, &self.password)
            .await?;

        let encrypted_meeting_name = crypto_client
            .encrypt_message(&self.meeting_name, &session_key, MEET_METADATA_AAD)
            .await?;

        Ok(CreateMeetingParams {
            name: encrypted_meeting_name,
            password: Some(encrypted_password),
            salt,
            session_key: encrypted_session_key,
            srp_modulus_id: modulus.modulus_id.clone(),
            srp_salt: srp_verifier.salt,
            srp_verifier: srp_verifier.verifier,
            address_id: self.address_id.clone(),
            start_time: self.start_time.map(|dt| dt.to_rfc3339()),
            end_time: self.end_time.map(|dt| dt.to_rfc3339()),
            r_rule: self.r_rule.clone(),
            time_zone: self.time_zone.clone(),
            custom_password: self.custom_password as u8,
            meeting_type: self.meeting_type as u8,
        })
    }
}

#[derive(Debug, Clone)]
pub struct CreateMeetingParams {
    /// Base64 encrypted meeting name
    pub name: String,
    /// Armored encrypted password
    pub password: Option<String>,
    /// BCrypt salt used for password hashing
    pub salt: String,
    /// Base64 encrypted session key
    pub session_key: String,
    /// SRP modulus ID for secure remote password protocol
    pub srp_modulus_id: String,
    /// SRP salt for secure remote password protocol
    pub srp_salt: String,
    /// SRP verifier for secure remote password protocol
    pub srp_verifier: String,
    /// User address ID
    pub address_id: Option<String>,
    /// Meeting start time in ISO format (e.g., "2024-01-01T10:00:00Z") or null
    pub start_time: Option<String>,
    /// Meeting end time in ISO format (e.g., "2024-01-01T11:00:00Z") or null
    pub end_time: Option<String>,
    /// Recurrence rule: "recurring", "scheduled", or null
    pub r_rule: Option<String>,
    /// Timezone string (e.g., "America/New_York") or null
    pub time_zone: Option<String>,
    /// Custom password setting: 0 = NO_PASSWORD, 1 = PASSWORD_SET
    pub custom_password: u8,
    /// Meeting type enum value
    pub meeting_type: u8,
}

#[derive(Debug, Clone)]
pub struct UpdateMeetingScheduleParams {
    /// Meeting start time in ISO format (e.g., "2024-01-01T10:00:00Z") or null
    pub start_time: Option<String>,
    /// Meeting end time in ISO format (e.g., "2024-01-01T11:00:00Z") or null
    pub end_time: Option<String>,
    /// Recurrence rule: "recurring", "scheduled", or null
    pub r_rule: Option<String>,
    /// Timezone string (e.g., "America/New_York") or null
    pub time_zone: Option<String>,
}
