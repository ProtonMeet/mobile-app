use std::sync::Arc;

use crate::{errors::service::ServiceError, utils::instant};
use tracing::info;

use crate::domain::user::{
    models::{
        meet_link_info::MeetInfo,
        meeting::{
            CreateMeeting, CustomPasswordSetting, Meeting, MeetingType, UpcomingMeeting,
            UpdateMeetingScheduleParams,
        },
        participant_track_settings::ParticipantTrackSettings,
    },
    ports::{crypto_client::CryptoClient, http_client::HttpClient, meeting_api::MeetingApi},
};
use chrono::{DateTime, Utc};
use proton_meet_common::models::ProtonUserKey;
use proton_meet_crypto::{MEET_DISPLAY_NAME_AAD, MEET_METADATA_AAD};

/// Domain service for room/meeting operations
///
/// This service contains pure business logic for meeting/room management,
/// including creating meetings, joining meetings, decrypting meeting data,
/// and managing participants. It depends only on ports (traits), not concrete
/// infrastructure implementations.
pub struct RoomService {
    http_client: Arc<dyn HttpClient>,
    meeting_api: Arc<dyn MeetingApi>,
    crypto_client: Arc<dyn CryptoClient>,
}

impl RoomService {
    /// Creates a new RoomService instance
    ///
    /// # Arguments
    /// * `http_client` - HTTP client port for making API calls
    /// * `meeting_api` - Meeting API port for meeting operations
    /// * `crypto_client` - Crypto client port for encryption/decryption operations
    pub fn new(
        http_client: Arc<dyn HttpClient>,
        meeting_api: Arc<dyn MeetingApi>,
        crypto_client: Arc<dyn CryptoClient>,
    ) -> Self {
        Self {
            http_client,
            meeting_api,
            crypto_client,
        }
    }

    /// Joins a meeting by authenticating and decrypting meeting information
    ///
    /// # Arguments
    /// * `meet_link_name` - The meeting link identifier
    /// * `meet_link_password` - The password for the meeting
    /// * `display_name` - The display name for the participant
    ///
    /// # Returns
    /// * `Ok((MeetInfo, Option<String>))` - Meeting information and base64 decrypted session key
    ///   (native only; used to decrypt participant display names). `None` on wasm.
    /// * `Err(anyhow::Error)` - Error during authentication or decryption
    pub async fn join_meeting(
        &self,
        meet_link_name: &str,
        meet_link_password: &str,
        display_name: &str,
    ) -> Result<(MeetInfo, Option<String>), anyhow::Error> {
        let total_start = instant::now();

        let link_info_start = instant::now();
        let meet_link_info = self.http_client.get_meet_link_info(meet_link_name).await?;
        info!(
            "join_meeting step=get_meet_link_info ms={}",
            link_info_start.elapsed().as_millis()
        );

        let srp_start = instant::now();
        let srp_proof = self
            .crypto_client
            .generate_srp_proof(
                meet_link_password,
                &meet_link_info.modulus,
                &meet_link_info.server_ephemeral,
                &meet_link_info.salt,
            )
            .await?;
        info!(
            "join_meeting step=generate_srp_proof ms={} modulus_len={} salt_len={}",
            srp_start.elapsed().as_millis(),
            meet_link_info.modulus.len(),
            meet_link_info.salt.len()
        );

        let auth_start = instant::now();
        let auth_meet_link_info = self
            .http_client
            .auth_meet_link(
                meet_link_name,
                &srp_proof.client_ephemeral,
                &srp_proof.client_proof,
                &meet_link_info.srp_session,
            )
            .await?;
        info!(
            "join_meeting step=auth_meet_link ms={} srp_session_len={}",
            auth_start.elapsed().as_millis(),
            meet_link_info.srp_session.len()
        );

        if srp_proof.expected_server_proof != auth_meet_link_info.server_proof {
            return Err(anyhow::anyhow!("SRP proof mismatch"));
        }

        let meet_info_start = instant::now();
        let meet_info = self.http_client.get_meet_info(meet_link_name).await?;
        info!(
            "join_meeting step=get_meet_info ms={} enc_name_len={} salt_len={}",
            meet_info_start.elapsed().as_millis(),
            meet_info.meeting_name.len(),
            meet_info.salt.len()
        );

        let passphrase_start = instant::now();
        let session_key_passphrase = self
            .crypto_client
            .compute_key_password(meet_link_password, &meet_info.salt)
            .await?;
        info!(
            "join_meeting step=compute_key_password ms={}",
            passphrase_start.elapsed().as_millis()
        );

        #[cfg(not(target_family = "wasm"))]
        let dec_key_start = instant::now();
        #[cfg(not(target_family = "wasm"))]
        let decrypted_session_key = self
            .crypto_client
            .decrypt_session_key(&meet_info.session_key, &session_key_passphrase)
            .await?;

        #[cfg(not(target_family = "wasm"))]
        info!(
            "join_meeting step=decrypt_session_key ms={} session_key_len={}",
            dec_key_start.elapsed().as_millis(),
            meet_info.session_key.len()
        );

        #[cfg(not(target_family = "wasm"))]
        let dec_name_start = instant::now();
        #[cfg(not(target_family = "wasm"))]
        let decrypted_meet_name = self
            .crypto_client
            .decrypt_message(
                &meet_info.meeting_name,
                &decrypted_session_key,
                MEET_METADATA_AAD,
            )
            .await?;
        #[cfg(not(target_family = "wasm"))]
        info!(
            "join_meeting step=decrypt_meeting_name ms={} enc_name_len={}",
            dec_name_start.elapsed().as_millis(),
            meet_info.meeting_name.len()
        );

        #[cfg(target_family = "wasm")]
        let decrypted_meet_name = self
            .crypto_client
            .decrypt_message(
                &meet_info.session_key,
                &session_key_passphrase,
                MEET_METADATA_AAD,
            )
            .await?;

        #[cfg(debug_assertions)]
        tracing::debug!("decrypted_meet_name: {:?}", &decrypted_meet_name);

        #[cfg(not(target_family = "wasm"))]
        let display_name_session_key = Some(decrypted_session_key.clone());
        #[cfg(not(target_family = "wasm"))]
        let encrypted_display_name = match self
            .crypto_client
            .encrypt_message(display_name, &decrypted_session_key, MEET_DISPLAY_NAME_AAD)
            .await
        {
            Ok(cipher) => {
                #[cfg(debug_assertions)]
                tracing::info!(
                    "join_meeting: encrypted local display name for EncryptedDisplayName on access token",
                );
                cipher
            }
            Err(e) => {
                #[cfg(debug_assertions)]
                tracing::info!(
                    "join_meeting: encrypt display name failed; sending empty ciphertext error={:?}", e,
                );
                String::new()
            }
        };

        #[cfg(target_family = "wasm")]
        let display_name_session_key: Option<String> = None;
        #[cfg(target_family = "wasm")]
        let encrypted_display_name = String::new();

        let token_start = instant::now();
        let access_token_info = self
            .http_client
            .fetch_access_token(meet_link_name, display_name, &encrypted_display_name)
            .await?;
        info!(
            "join_meeting step=fetch_access_token ms={} token_len={}",
            token_start.elapsed().as_millis(),
            access_token_info.access_token.len()
        );

        #[cfg(debug_assertions)]
        tracing::debug!("access_token: {:?}", &access_token_info.access_token);

        info!(
            "join_meeting step=done total_ms={}",
            total_start.elapsed().as_millis()
        );

        Ok((
            MeetInfo {
                meet_name: decrypted_meet_name,
                meet_link_name: meet_link_name.to_string(),
                access_token: access_token_info.access_token,
                websocket_url: access_token_info.websocket_url,
                participants_count: 0, // Will be updated separately
                is_locked: meet_info.locked != 0,
                max_duration: meet_info.max_duration,
                max_participants: meet_info.max_participants,
                expiration_time: meet_info.expiration_time.map(|dt| dt.timestamp()),
            },
            display_name_session_key,
        ))
    }

    /// Creates a new meeting
    ///
    /// # Arguments
    /// * `meeting_name` - The name of the meeting
    /// * `address_id` - The address ID for the meeting
    /// * `custom_password` - Optional custom password
    /// * `user_private_key` - User's private key for encryption
    /// * `private_key_passphrase` - Passphrase for the private key
    /// * `meeting_type` - Type of meeting (Personal or Instant)
    /// * `is_rotate` - Whether to rotate an existing personal meeting
    ///
    /// # Returns
    /// * `Ok((Meeting, String))` - Created meeting and combined password
    /// * `Err(anyhow::Error)` - Error during meeting creation
    #[allow(clippy::too_many_arguments)]
    pub async fn create_meeting(
        &self,
        meeting_name: &str,
        custom_password: Option<String>,
        address_id: Option<&str>,
        user_private_key: Option<&str>,
        private_key_passphrase: Option<&str>,
        meeting_type: MeetingType,
        is_rotate: bool,
        start_time: Option<DateTime<Utc>>,
        end_time: Option<DateTime<Utc>>,
        time_zone: Option<String>,
        r_rule: Option<String>,
    ) -> Result<UpcomingMeeting, ServiceError> {
        let total_start = instant::now();
        let password_base = self
            .crypto_client
            .generate_random_meeting_password()
            .await?;

        let combined_password = {
            match custom_password {
                Some(password) => format!("{password}_{password_base}"),
                None => password_base,
            }
        };
        info!(
            "create_meeting step=generated_password ms={}",
            total_start.elapsed().as_millis()
        );

        let modulus_start = instant::now();
        info!("create_meeting get get_modulus");

        let modulus = self.http_client.get_modulus().await?;
        info!(
            "create_meeting step=get_modulus ms={} ",
            modulus_start.elapsed().as_millis(),
        );

        let params_start = instant::now();
        let create_meeting_params = match meeting_type {
            MeetingType::Personal => {
                let user_private_key =
                    user_private_key.ok_or(ServiceError::UserPrivateKeysNotFound)?;
                let private_key_passphrase =
                    private_key_passphrase.ok_or(ServiceError::PrivateKeyPassphraseNotFound)?;
                let address_id = address_id.ok_or(ServiceError::AddressIdRequired)?;

                CreateMeeting::personal(
                    meeting_name.to_string(),
                    combined_password.clone(),
                    address_id.to_string(),
                    CustomPasswordSetting::NoPassword,
                )
                .generate_params(
                    &modulus,
                    user_private_key.to_string(),
                    private_key_passphrase.to_string(),
                    &self.crypto_client,
                )
                .await?
            }
            MeetingType::Scheduled => {
                let user_private_key =
                    user_private_key.ok_or(ServiceError::UserPrivateKeysNotFound)?;
                let private_key_passphrase =
                    private_key_passphrase.ok_or(ServiceError::PrivateKeyPassphraseNotFound)?;
                let address_id = address_id.ok_or(ServiceError::AddressIdRequired)?;

                CreateMeeting::scheduled(
                    meeting_name.to_string(),
                    combined_password.clone(),
                    address_id.to_string(),
                    start_time,
                    end_time,
                    time_zone,
                    CustomPasswordSetting::NoPassword,
                )
                .generate_params(
                    &modulus,
                    user_private_key.to_string(),
                    private_key_passphrase.to_string(),
                    &self.crypto_client,
                )
                .await?
            }
            MeetingType::Recurring => {
                let user_private_key =
                    user_private_key.ok_or(ServiceError::UserPrivateKeysNotFound)?;
                let private_key_passphrase =
                    private_key_passphrase.ok_or(ServiceError::PrivateKeyPassphraseNotFound)?;
                let address_id = address_id.ok_or(ServiceError::AddressIdRequired)?;
                let start_time = start_time.ok_or(ServiceError::StartTimeRequired)?;
                CreateMeeting::recurring(
                    meeting_name.to_string(),
                    combined_password.clone(),
                    address_id.to_string(),
                    start_time,
                    end_time,
                    time_zone,
                    r_rule,
                    CustomPasswordSetting::NoPassword,
                )
                .generate_params(
                    &modulus,
                    user_private_key.to_string(),
                    private_key_passphrase.to_string(),
                    &self.crypto_client,
                )
                .await?
            }
            MeetingType::Permanent => {
                let user_private_key =
                    user_private_key.ok_or(ServiceError::UserPrivateKeysNotFound)?;
                let private_key_passphrase =
                    private_key_passphrase.ok_or(ServiceError::PrivateKeyPassphraseNotFound)?;
                let address_id = address_id.ok_or(ServiceError::AddressIdRequired)?;

                CreateMeeting::permanent(
                    meeting_name.to_string(),
                    combined_password.clone(),
                    address_id.to_string(),
                    None,
                    None,
                    None,
                    CustomPasswordSetting::NoPassword,
                )
                .generate_params(
                    &modulus,
                    user_private_key.to_string(),
                    private_key_passphrase.to_string(),
                    &self.crypto_client,
                )
                .await?
            }
            _ => match (user_private_key, private_key_passphrase, address_id) {
                (Some(key), Some(passphrase), Some(addr_id)) => {
                    CreateMeeting::instant(
                        meeting_name.to_string(),
                        combined_password.clone(),
                        Some(addr_id.to_string()),
                        CustomPasswordSetting::NoPassword,
                    )
                    .generate_params(
                        &modulus,
                        key.to_string(),
                        passphrase.to_string(),
                        &self.crypto_client,
                    )
                    .await?
                }
                _ => {
                    CreateMeeting::instant(
                        meeting_name.to_string(),
                        combined_password.clone(),
                        None,
                        CustomPasswordSetting::NoPassword,
                    )
                    .generate_params_unauth(&modulus, &self.crypto_client)
                    .await?
                }
            },
        };
        info!(
            "create_meeting step=generate_params ms={} meeting_type={:?}",
            params_start.elapsed().as_millis(),
            meeting_type
        );

        let api_start = instant::now();
        let meeting = if is_rotate && meeting_type == MeetingType::Personal {
            self.meeting_api
                .rotate_personal_meeting(create_meeting_params)
                .await?
        } else {
            self.meeting_api
                .create_meeting(create_meeting_params)
                .await?
        };
        info!(
            "create_meeting step=api_call ms={} is_rotate={} id={} link={}",
            api_start.elapsed().as_millis(),
            is_rotate,
            meeting.id,
            meeting.meeting_link_name
        );

        #[cfg(debug_assertions)]
        tracing::info!("meeting created: {:?}", &meeting);

        info!(
            "create_meeting step=done total_ms={} pwd_len={}",
            total_start.elapsed().as_millis(),
            combined_password.len()
        );

        // Decrypt the meeting name using the plain text password we have
        // Compute password hash from the plain text password and salt
        let password_hash = self
            .crypto_client
            .compute_key_password(&combined_password, &meeting.salt)
            .await?;

        // Decrypt session key using password hash
        let session_key = self
            .crypto_client
            .decrypt_session_key(&meeting.session_key, &password_hash)
            .await?;

        // Decrypt meeting name using session key
        #[cfg(not(target_family = "wasm"))]
        let meeting_name_plain = self
            .crypto_client
            .decrypt_message(&meeting.meeting_name, &session_key, MEET_METADATA_AAD)
            .await?;

        #[cfg(target_family = "wasm")]
        let meeting_name_plain: String = unimplemented!();

        // Convert Meeting to UpcomingMeeting with decrypted name
        let upcoming_meeting = UpcomingMeeting {
            id: meeting.id,
            address_id: meeting.address_id,
            meeting_link_name: meeting.meeting_link_name,
            meeting_name: meeting_name_plain,
            meeting_password: combined_password,
            meeting_type: meeting.meeting_type,
            start_time: meeting.start_time,
            end_time: meeting.end_time,
            r_rule: meeting.r_rule,
            time_zone: meeting.time_zone,
            calendar_id: meeting.calendar_id,
            proton_calendar: meeting.proton_calendar,
            create_time: meeting.create_time,
            last_used_time: meeting.last_used_time,
            calendar_event_id: meeting.calendar_event_id,
        };

        Ok(upcoming_meeting)
    }

    /// Updates an existing meeting name
    ///
    /// # Arguments
    /// * `meeting_id` - The meeting ID to update
    /// * `meeting_name` - The new meeting name
    /// * `meeting_password` - Existing combined meeting password
    pub async fn edit_meeting_name(
        &self,
        meeting_id: &str,
        meeting_name: &str,
        meeting_password: &str,
    ) -> Result<UpcomingMeeting, ServiceError> {
        let total_start = instant::now();
        let meeting = self.meeting_api.fetch_meeting(meeting_id).await?;

        // Compute password hash from the plain text password and salt
        let password_hash = self
            .crypto_client
            .compute_key_password(meeting_password, &meeting.salt)
            .await?;

        // Decrypt session key using password hash
        let session_key = self
            .crypto_client
            .decrypt_session_key(&meeting.session_key, &password_hash)
            .await?;

        // Decrypt meeting name using session key
        #[cfg(not(target_family = "wasm"))]
        let encoded_encrypted_meeting_name = self
            .crypto_client
            .encrypt_message(meeting_name, &session_key, MEET_METADATA_AAD)
            .await?;
        #[cfg(target_family = "wasm")]
        let encoded_encrypted_meeting_name: String = unimplemented!();

        let meeting = self
            .meeting_api
            .edit_meeting_name(meeting_id, &encoded_encrypted_meeting_name)
            .await?;

        let upcoming_meeting = UpcomingMeeting {
            id: meeting.id,
            address_id: meeting.address_id,
            meeting_link_name: meeting.meeting_link_name,
            meeting_name: meeting_name.to_string(),
            meeting_password: meeting_password.to_string(),
            meeting_type: meeting.meeting_type,
            start_time: meeting.start_time,
            end_time: meeting.end_time,
            r_rule: meeting.r_rule,
            time_zone: meeting.time_zone,
            calendar_id: meeting.calendar_id,
            proton_calendar: meeting.proton_calendar,
            create_time: meeting.create_time,
            last_used_time: meeting.last_used_time,
            calendar_event_id: meeting.calendar_event_id,
        };

        info!(
            "update_meeting step=done total_ms={} id={}",
            total_start.elapsed().as_millis(),
            upcoming_meeting.id
        );

        Ok(upcoming_meeting)
    }

    /// Updates an existing meeting schedule
    ///
    /// # Arguments
    /// * `meeting_id` - The meeting ID to update
    /// * `meeting_name` - Existing decrypted meeting name
    /// * `meeting_password` - Existing combined meeting password
    /// * `params` - New schedule fields
    pub async fn update_meeting_schedule(
        &self,
        meeting_id: &str,
        meeting_name: &str,
        meeting_password: &str,
        params: UpdateMeetingScheduleParams,
    ) -> Result<UpcomingMeeting, ServiceError> {
        let total_start = instant::now();
        let meeting = self
            .meeting_api
            .update_meeting_schedule(meeting_id, params)
            .await?;

        let upcoming_meeting = UpcomingMeeting {
            id: meeting.id,
            address_id: meeting.address_id,
            meeting_link_name: meeting.meeting_link_name,
            meeting_name: meeting_name.to_string(),
            meeting_password: meeting_password.to_string(),
            meeting_type: meeting.meeting_type,
            start_time: meeting.start_time,
            end_time: meeting.end_time,
            r_rule: meeting.r_rule,
            time_zone: meeting.time_zone,
            calendar_id: meeting.calendar_id,
            proton_calendar: meeting.proton_calendar,
            create_time: meeting.create_time,
            last_used_time: meeting.last_used_time,
            calendar_event_id: meeting.calendar_event_id,
        };

        info!(
            "update_meeting_schedule step=done total_ms={} id={}",
            total_start.elapsed().as_millis(),
            upcoming_meeting.id
        );

        Ok(upcoming_meeting)
    }

    /// Gets upcoming meetings and decrypts them
    ///
    /// # Arguments
    /// * `user_private_keys` - User's private keys for decryption
    /// * `all_address_keys` - All address keys for decryption
    /// * `private_key_passphrase` - Passphrase for the private keys
    ///
    /// # Returns
    /// * `Ok(Vec<UpcomingMeeting>)` - List of decrypted upcoming meetings
    /// * `Err(anyhow::Error)` - Error during decryption
    pub async fn get_upcoming_meetings(
        &self,
        user_private_keys: &[ProtonUserKey],
        all_address_keys: &[ProtonUserKey],
        private_key_passphrase: &str,
    ) -> Result<Vec<UpcomingMeeting>, anyhow::Error> {
        let upcoming_meetings = self.meeting_api.get_upcoming_meetings().await?;
        let mut decrypted_upcomming_meetings = Vec::new();

        for meeting in upcoming_meetings {
            let Some(password) = meeting.password else {
                continue;
            };

            // Try to decrypt the meeting, but continue if it fails
            match self
                .crypto_client
                .openpgp_decrypt_message(
                    &password,
                    user_private_keys,
                    all_address_keys,
                    private_key_passphrase,
                )
                .await
            {
                Ok(encrypted_password) => {
                    // Continue with password hash computation
                    match self
                        .crypto_client
                        .compute_key_password(&encrypted_password, &meeting.salt)
                        .await
                    {
                        Ok(password_hash) => {
                            // Decrypt session key
                            match self
                                .crypto_client
                                .decrypt_session_key(&meeting.session_key, &password_hash)
                                .await
                            {
                                Ok(session_key) => {
                                    // Decrypt meeting name
                                    #[cfg(not(target_family = "wasm"))]
                                    match self
                                        .crypto_client
                                        .decrypt_message(
                                            &meeting.meeting_name,
                                            &session_key,
                                            MEET_METADATA_AAD,
                                        )
                                        .await
                                    {
                                        Ok(meeting_name_plain) => {
                                            // Build a decrypted view
                                            let decrypted = UpcomingMeeting {
                                                id: meeting.id.clone(),
                                                address_id: meeting.address_id.clone(),
                                                meeting_link_name: meeting
                                                    .meeting_link_name
                                                    .clone(),
                                                meeting_name: meeting_name_plain,
                                                meeting_password: encrypted_password.clone(),
                                                start_time: meeting.start_time,
                                                end_time: meeting.end_time,
                                                meeting_type: meeting.meeting_type,
                                                r_rule: meeting.r_rule.clone(),
                                                time_zone: meeting.time_zone.clone(),
                                                calendar_id: meeting.calendar_id.clone(),
                                                proton_calendar: meeting.proton_calendar,
                                                create_time: meeting.create_time,
                                                last_used_time: meeting.last_used_time,
                                                calendar_event_id: meeting.calendar_event_id,
                                            };
                                            decrypted_upcomming_meetings.push(decrypted);
                                        }
                                        Err(e) => {
                                            tracing::warn!(
                                                "Failed to decrypt meeting name for meeting {} (link: {}): {}. Meeting data: id={:?}, address_id={:?}, start_time={:?}, end_time={:?}, type={:?}",
                                                meeting.id,
                                                meeting.meeting_link_name,
                                                e,
                                                meeting.id,
                                                meeting.address_id,
                                                meeting.start_time,
                                                meeting.end_time,
                                                meeting.meeting_type
                                            );
                                        }
                                    }

                                    #[cfg(target_family = "wasm")]
                                    {
                                        let meeting_name_plain: String = unimplemented!();
                                        let decrypted = UpcomingMeeting {
                                            id: meeting.id.clone(),
                                            address_id: meeting.address_id.clone(),
                                            meeting_link_name: meeting.meeting_link_name.clone(),
                                            meeting_name: meeting_name_plain,
                                            meeting_password: encrypted_password.clone(),
                                            start_time: meeting.start_time,
                                            end_time: meeting.end_time,
                                            meeting_type: meeting.meeting_type,
                                            r_rule: meeting.r_rule.clone(),
                                            time_zone: meeting.time_zone.clone(),
                                            calendar_id: meeting.calendar_id.clone(),
                                            proton_calendar: meeting.proton_calendar,
                                            create_time: meeting.create_time,
                                            last_used_time: meeting.last_used_time,
                                            calendar_event_id: meeting.calendar_event_id,
                                        };
                                        decrypted_upcomming_meetings.push(decrypted);
                                    }
                                }
                                Err(e) => {
                                    tracing::warn!(
                                        "Failed to decrypt session key for meeting {} (link: {}): {}. Meeting data: id={:?}, address_id={:?}, start_time={:?}, end_time={:?}, type={:?}",
                                        meeting.id,
                                        meeting.meeting_link_name,
                                        e,
                                        meeting.id,
                                        meeting.address_id,
                                        meeting.start_time,
                                        meeting.end_time,
                                        meeting.meeting_type
                                    );
                                }
                            }
                        }
                        Err(e) => {
                            tracing::warn!(
                                "Failed to compute password hash for meeting {} (link: {}): {}. Meeting data: id={:?}, address_id={:?}, start_time={:?}, end_time={:?}, type={:?}",
                                meeting.id,
                                meeting.meeting_link_name,
                                e,
                                meeting.id,
                                meeting.address_id,
                                meeting.start_time,
                                meeting.end_time,
                                meeting.meeting_type
                            );
                        }
                    }
                }
                Err(e) => {
                    tracing::warn!(
                        "Failed to decrypt password for meeting {} (link: {}): {}. Meeting data: id={:?}, address_id={:?}, start_time={:?}, end_time={:?}, type={:?}, salt={:?}, session_key_length={}",
                        meeting.id,
                        meeting.meeting_link_name,
                        e,
                        meeting.id,
                        meeting.address_id,
                        meeting.start_time,
                        meeting.end_time,
                        meeting.meeting_type,
                        meeting.salt,
                        meeting.session_key.len()
                    );
                }
            }
        }

        Ok(decrypted_upcomming_meetings)
    }

    /// Ends a meeting
    ///
    /// # Arguments
    /// * `meeting_name` - The name of the meeting to end
    /// * `access_token` - Access token for authentication
    ///
    /// # Returns
    /// * `Ok(())` - Meeting ended successfully
    /// * `Err(anyhow::Error)` - Error ending the meeting
    pub async fn end_meeting(
        &self,
        meeting_name: &str,
        access_token: &str,
    ) -> Result<(), anyhow::Error> {
        self.meeting_api
            .end_meeting(meeting_name, access_token)
            .await?;

        #[cfg(debug_assertions)]
        tracing::info!("meeting ended: {:?}", &meeting_name);

        Ok(())
    }

    /// Gets active meetings
    ///
    /// # Returns
    /// * `Ok(Vec<Meeting>)` - List of active meetings
    /// * `Err(anyhow::Error)` - Error fetching active meetings
    pub async fn get_active_meetings(&self) -> Result<Vec<Meeting>, anyhow::Error> {
        let active_meetings = self.http_client.get_active_meetings().await?;
        Ok(active_meetings)
    }

    /// Gets meeting information
    ///
    /// # Arguments
    /// * `meeting_link_name` - The meeting link identifier
    ///
    /// # Returns
    /// * `Ok(MeetingInfo)` - Meeting information
    /// * `Err(anyhow::Error)` - Error fetching meeting information
    pub async fn get_meeting_info(
        &self,
        meeting_link_name: &str,
    ) -> Result<crate::domain::user::models::MeetingInfo, anyhow::Error> {
        let meeting_info = self.meeting_api.get_meeting_info(meeting_link_name).await?;
        Ok(meeting_info)
    }

    /// Gets participants for a meeting
    ///
    /// # Arguments
    /// * `meet_link_name` - The meeting link identifier
    ///
    /// # Returns
    /// * `Ok(Vec<MeetParticipant>)` - List of participants
    /// * `Err(anyhow::Error)` - Error fetching participants
    pub async fn get_participants(
        &self,
        meet_link_name: &str,
    ) -> Result<Vec<crate::domain::user::models::meet_link_info::MeetParticipant>, anyhow::Error>
    {
        let participants = self.http_client.get_participants(meet_link_name).await?;
        Ok(participants)
    }

    /// Replaces `display_name` with decrypted values when `EncryptedDisplayName` is present.
    pub async fn decrypt_participant_display_names(
        &self,
        mut participants: Vec<crate::domain::user::models::meet_link_info::MeetParticipant>,
        session_key: Option<&str>,
    ) -> Vec<crate::domain::user::models::meet_link_info::MeetParticipant> {
        let Some(key) = session_key else {
            #[cfg(debug_assertions)]
            tracing::debug!(
                participant_count = participants.len(),
                "get_participants: no display-name session key cached; leaving API display_name as-is",
            );
            return participants;
        };

        #[cfg(debug_assertions)]
        let mut decrypted_count = 0u32;
        #[cfg(debug_assertions)]
        let mut skipped_no_cipher = 0u32;
        #[cfg(debug_assertions)]
        let mut decrypt_failed = 0u32;

        for p in participants.iter_mut() {
            let enc = match &p.encrypted_display_name {
                Some(e) if !e.is_empty() => e.as_str(),
                _ => {
                    #[cfg(debug_assertions)]
                    {
                        skipped_no_cipher += 1;
                    }
                    continue;
                }
            };

            #[cfg(debug_assertions)]
            let api_display_len = p.display_name.len();

            match self
                .crypto_client
                .decrypt_message(enc, key, MEET_DISPLAY_NAME_AAD)
                .await
            {
                Ok(name) => {
                    #[cfg(debug_assertions)]
                    {
                        decrypted_count += 1;
                        tracing::debug!(
                            participant_uuid = %p.participant_uuid,
                            cipher_len = enc.len(),
                            api_display_len,
                            decrypted_len = name.len(),
                            decrypted = %name,
                            aad = MEET_DISPLAY_NAME_AAD,
                            "get_participants: decrypted EncryptedDisplayName into display_name",
                        );
                    }
                    p.display_name = name;
                }
                Err(e) => {
                    #[cfg(debug_assertions)]
                    {
                        decrypt_failed += 1;
                        tracing::debug!(
                            participant_uuid = %p.participant_uuid,
                            cipher_len = enc.len(),
                            api_display_len,
                            error = %e,
                            aad = MEET_DISPLAY_NAME_AAD,
                            "get_participants: decrypt EncryptedDisplayName failed; keeping API display_name",
                        );
                    }
                    #[cfg(not(debug_assertions))]
                    let _ = e;
                }
            }
        }

        #[cfg(debug_assertions)]
        tracing::debug!(
            participant_count = participants.len(),
            decrypted_count,
            skipped_no_cipher,
            decrypt_failed,
            session_key_len = key.len(),
            aad = MEET_DISPLAY_NAME_AAD,
            "get_participants: decrypt_participant_display_names summary",
        );

        participants
    }

    /// Gets participants count for a meeting
    ///
    /// # Arguments
    /// * `meet_link_name` - The meeting link identifier
    ///
    /// # Returns
    /// * `Ok(u32)` - Number of participants
    /// * `Err(anyhow::Error)` - Error fetching participants count
    pub async fn get_participants_count(&self, meet_link_name: &str) -> Result<u32, anyhow::Error> {
        let count = self
            .http_client
            .get_participants_count(meet_link_name)
            .await?;
        Ok(count)
    }

    /// Updates participant track settings (audio/video)
    ///
    /// # Arguments
    /// * `meet_link_name` - The meeting link identifier
    /// * `access_token` - Access token for authentication
    /// * `participant_uuid` - UUID of the participant
    /// * `audio_enabled` - Optional audio enabled flag
    /// * `video_enabled` - Optional video enabled flag
    ///
    /// # Returns
    /// * `Ok(ParticipantTrackSettings)` - Updated participant track settings
    /// * `Err(anyhow::Error)` - Error updating settings
    pub async fn update_participant_track_settings(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
        audio_enabled: Option<u8>,
        video_enabled: Option<u8>,
    ) -> Result<ParticipantTrackSettings, anyhow::Error> {
        // todo: check with access token for mute permission
        let participant_track_settings = self
            .http_client
            .update_participant_track_settings(
                meet_link_name,
                access_token,
                participant_uuid,
                audio_enabled,
                video_enabled,
            )
            .await?;

        Ok(participant_track_settings)
    }

    /// Removes a participant from a meeting
    ///
    /// # Arguments
    /// * `meet_link_name` - The meeting link identifier
    /// * `access_token` - Access token for authentication
    /// * `participant_uuid` - UUID of the participant to remove
    ///
    /// # Returns
    /// * `Ok(())` - Participant removed successfully
    /// * `Err(anyhow::Error)` - Error removing participant
    pub async fn remove_participant(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
    ) -> Result<(), anyhow::Error> {
        self.http_client
            .remove_participant(meet_link_name, access_token, participant_uuid)
            .await?;

        Ok(())
    }

    /// Locks a meeting to prevent new participants from joining (meeting host only)
    ///
    /// # Arguments
    /// * `meet_link_name` - The meeting link identifier
    ///
    /// # Returns
    /// * `Ok(())` - Meeting locked successfully
    /// * `Err(anyhow::Error)` - Error locking the meeting
    pub async fn lock_meeting(&self, meet_link_name: &str) -> Result<(), anyhow::Error> {
        self.meeting_api.lock_meeting(meet_link_name).await?;
        Ok(())
    }

    /// Unlocks a meeting to allow new participants to join (meeting host only)
    ///
    /// # Arguments
    /// * `meet_link_name` - The meeting link identifier
    ///
    /// # Returns
    /// * `Ok(())` - Meeting unlocked successfully
    /// * `Err(anyhow::Error)` - Error unlocking the meeting
    pub async fn unlock_meeting(&self, meet_link_name: &str) -> Result<(), anyhow::Error> {
        self.meeting_api.unlock_meeting(meet_link_name).await?;
        Ok(())
    }
}
