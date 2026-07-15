use super::App;
use crate::domain::user::models::{
    meet_link_info::MeetInfo,
    meeting::{Meeting, MeetingType, UpcomingMeeting, UpdateMeetingScheduleParams},
    MeetingInfo,
};
use crate::errors::{
    core::MeetCoreError,
    create_meeting::{map_create_meeting_service_error, CreateMeetingErrorContext},
};
use chrono::{DateTime, Utc};
use proton_meet_common::models::ProtonUserKey;
use tracing::debug;

impl App {
    pub async fn delete_meeting(&self, meeting_name: String) -> Result<(), MeetCoreError> {
        self.meeting_api.delete_meeting(&meeting_name).await?;
        Ok(())
    }

    #[tracing::instrument(err, skip_all)]
    pub async fn authenticate_meeting_link(
        &self,
        meet_link_name: String,
        meet_link_password: String,
        display_name: String,
    ) -> Result<MeetInfo, MeetCoreError> {
        let (meet_info, session_key) = self
            .room_service
            .join_meeting(&meet_link_name, &meet_link_password, &display_name)
            .await?;

        {
            let mut state = self.state.write().await;
            state.meeting_display_name_session_key = session_key;
            state.active_livekit_access_token = Some(meet_info.access_token.clone());
            state.active_livekit_websocket_url = Some(meet_info.websocket_url.clone());
            state.prejoin_srp_auth = Some(crate::app_state::PrejoinSrpAuth {
                meet_link_name: meet_link_name.clone(),
                meet_link_password: meet_link_password.clone(),
                display_name: display_name.clone(),
                meet_info: meet_info.clone(),
            });
        }

        Ok(meet_info)
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn create_meeting(
        &self,
        meeting_name: String,
        has_session: bool,
        meeting_type: MeetingType,
        custom_password: Option<String>,
        start_time: Option<i64>,
        end_time: Option<i64>,
        time_zone: Option<String>,
        r_rule: Option<String>,
        waiting_room: bool,
    ) -> Result<UpcomingMeeting, MeetCoreError> {
        let start_time = start_time.and_then(Self::to_utc_datetime);
        let end_time = end_time.and_then(Self::to_utc_datetime);
        let meeting = if has_session {
            debug!("create_meeting with session");
            let auth_info = self.get_user_state_info().await?;

            let mailbox_password = self
                .user_key_provider
                .get_user_key_passphrase(auth_info.user_id)
                .await
                .map_err(|e| MeetCoreError::StorageError {
                    message: format!("Failed to get mailbox password: {e}"),
                    details: None,
                })?;
            let key = &auth_info.active_user_key;
            let create_ctx = CreateMeetingErrorContext {
                meeting_type,
                has_session: true,
                mailbox_password_empty: mailbox_password.is_empty(),
                signing_key_primary: key.primary != 0,
                signing_key_active: key.active != 0,
            };
            self.room_service
                .create_meeting(
                    &meeting_name,
                    custom_password,
                    Some(&auth_info.primary_address.id),
                    Some(&auth_info.active_user_key.private_key),
                    Some(&mailbox_password),
                    meeting_type,
                    false,
                    start_time,
                    end_time,
                    time_zone,
                    r_rule,
                    waiting_room,
                )
                .await
                .map_err(|e| map_create_meeting_service_error(e, &create_ctx))?
        } else {
            debug!("create_meeting without session");
            let create_ctx = CreateMeetingErrorContext {
                meeting_type: MeetingType::Instant,
                has_session: false,
                mailbox_password_empty: true,
                signing_key_primary: false,
                signing_key_active: false,
            };
            self.room_service
                .create_meeting(
                    &meeting_name,
                    custom_password,
                    None,
                    None,
                    None,
                    MeetingType::Instant,
                    false,
                    None,
                    None,
                    None,
                    None,
                    waiting_room,
                )
                .await
                .map_err(|e| map_create_meeting_service_error(e, &create_ctx))?
        };
        Ok(meeting)
    }

    pub(crate) fn to_utc_datetime(timestamp: i64) -> Option<DateTime<Utc>> {
        // Accept both seconds and milliseconds since epoch.
        if timestamp.abs() >= 1_000_000_000_000 {
            let secs = timestamp.div_euclid(1000);
            let millis = timestamp.rem_euclid(1000) as u32;
            DateTime::<Utc>::from_timestamp(secs, millis * 1_000_000)
        } else {
            DateTime::<Utc>::from_timestamp(timestamp, 0)
        }
    }

    pub async fn edit_meeting_name(
        &self,
        meeting_id: String,
        new_meeting_name: String,
        meeting_password: String,
    ) -> Result<UpcomingMeeting, MeetCoreError> {
        // check if the user is authenticated
        let _ = self.get_user_state_info().await?;
        let updated_meeting = self
            .room_service
            .edit_meeting_name(&meeting_id, &new_meeting_name, &meeting_password)
            .await?;
        Ok(updated_meeting)
    }

    #[allow(clippy::too_many_arguments)]
    pub async fn update_meeting_schedule(
        &self,
        meeting_id: String,
        meeting_name: String,
        meeting_password: String,
        start_time: Option<i64>,
        end_time: Option<i64>,
        time_zone: Option<String>,
        r_rule: Option<String>,
    ) -> Result<UpcomingMeeting, MeetCoreError> {
        // check if the user is authenticated
        let _ = self.get_user_state_info().await?;
        let start_time = start_time
            .and_then(Self::to_utc_datetime)
            .map(|dt| dt.to_rfc3339());
        let end_time = end_time
            .and_then(Self::to_utc_datetime)
            .map(|dt| dt.to_rfc3339());
        let params = UpdateMeetingScheduleParams {
            start_time,
            end_time,
            r_rule,
            time_zone,
        };
        let updated_meeting = self
            .room_service
            .update_meeting_schedule(&meeting_id, &meeting_name, &meeting_password, params)
            .await?;
        Ok(updated_meeting)
    }

    pub async fn get_upcoming_meetings(&self) -> Result<Vec<UpcomingMeeting>, MeetCoreError> {
        let app_state = self.state.read().await;
        let user_state = app_state
            .active_user
            .as_ref()
            .ok_or(MeetCoreError::NoActiveUser)?;
        let user_private_keys = user_state.user_keys.clone();
        let user_id = user_state.user_data.id.clone();
        let mailbox_password = self
            .user_key_provider
            .get_user_key_passphrase(user_id)
            .await
            .map_err(|e| MeetCoreError::StorageError {
                message: format!("Failed to get mailbox password: {e}"),
                details: None,
            })?;
        let all_address_keys: Vec<ProtonUserKey> = user_state
            .user_addresses
            .iter()
            .flat_map(|address| address.keys.clone())
            .collect();

        let upcoming_meetings = self
            .room_service
            .get_upcoming_meetings(&user_private_keys, &all_address_keys, &mailbox_password)
            .await?;
        Ok(upcoming_meetings)
    }

    pub async fn create_personal_meeting(
        &self,
        meeting_name: String,
        custom_password: Option<String>,
        is_rotate: bool,
        waiting_room: bool,
    ) -> Result<UpcomingMeeting, MeetCoreError> {
        let auth_info = self.get_user_state_info().await?;

        let mailbox_password = self
            .user_key_provider
            .get_user_key_passphrase(auth_info.user_id)
            .await
            .map_err(|e| MeetCoreError::StorageError {
                message: format!("Failed to get mailbox password: {e}"),
                details: None,
            })?;

        let key = &auth_info.active_user_key;
        let create_ctx = CreateMeetingErrorContext {
            meeting_type: MeetingType::Personal,
            has_session: true,
            mailbox_password_empty: mailbox_password.is_empty(),
            signing_key_primary: key.primary != 0,
            signing_key_active: key.active != 0,
        };
        let meeting = self
            .room_service
            .create_meeting(
                &meeting_name,
                custom_password,
                Some(&auth_info.primary_address.id),
                Some(&auth_info.active_user_key.private_key),
                Some(&mailbox_password),
                MeetingType::Personal,
                is_rotate,
                None,
                None,
                None,
                None,
                waiting_room,
            )
            .await
            .map_err(|e| map_create_meeting_service_error(e, &create_ctx))?;

        Ok(meeting)
    }

    pub async fn get_active_meetings(&self) -> Result<Vec<Meeting>, MeetCoreError> {
        let active_meetings = self.room_service.get_active_meetings().await?;
        Ok(active_meetings)
    }

    pub async fn get_meeting_info(
        &self,
        meeting_link_name: &str,
    ) -> Result<MeetingInfo, MeetCoreError> {
        let mut meeting_info = self
            .room_service
            .get_meeting_info(meeting_link_name)
            .await?;
        meeting_info.meeting_name = self
            .resolve_meeting_display_name(meeting_link_name, &meeting_info.meeting_name)
            .await?;
        Ok(meeting_info)
    }

    /// Resolves a human-readable meeting title from pre-join cache or session key.
    ///
    /// Meet-server returns encrypted metadata; callers with a cached SRP session (pre-join,
    /// waiting room, rejoin) can recover the plaintext without re-authenticating.
    pub(crate) async fn resolve_meeting_display_name(
        &self,
        meet_link_name: &str,
        encrypted_meeting_name: &str,
    ) -> Result<String, MeetCoreError> {
        {
            let state = self.state.read().await;
            if let Some(cached) = &state.prejoin_srp_auth {
                if cached.meet_link_name == meet_link_name {
                    return Ok(cached.meet_info.meet_name.clone());
                }
            }
        }

        let session_key = self
            .state
            .read()
            .await
            .meeting_display_name_session_key
            .clone();

        if let Some(session_key) = session_key {
            return self
                .room_service
                .decrypt_meeting_metadata_name(encrypted_meeting_name, &session_key)
                .await
                .map_err(|e| MeetCoreError::CryptographicError {
                    operation: format!("Failed to decrypt meeting name: {e}"),
                });
        }

        tracing::warn!(
            meet_link_name,
            "resolve_meeting_display_name: no pre-join cache or session key; returning encrypted name"
        );
        Ok(encrypted_meeting_name.to_string())
    }

    /// Submits call-quality feedback for the given meeting link (same contract as the web app).
    pub async fn send_meeting_feedback(
        &self,
        meeting_link_name: &str,
        score: u8,
        feedback_parts: Vec<String>,
    ) -> Result<(), MeetCoreError> {
        if !(1..=5).contains(&score) {
            return Err(MeetCoreError::InvalidInput {
                field: "score".to_string(),
                reason: "must be between 1 and 5".to_string(),
            });
        }
        let feedback = feedback_parts.join(", ");
        self.meeting_api
            .send_meeting_feedback(meeting_link_name, score, &feedback)
            .await?;
        Ok(())
    }
}
