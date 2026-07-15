use super::App;
use crate::domain::user::models::meet_link_info::MeetInfo;
use crate::domain::user::ports::UserService;
use crate::errors::core::MeetCoreError;

impl App {
    pub async fn get_meeting_display_name_session_key(&self) -> Result<String, MeetCoreError> {
        self.state
            .read()
            .await
            .meeting_display_name_session_key
            .as_ref()
            .map(|key| key.expose_secret().to_string())
            .ok_or(MeetCoreError::InternalError {
                message: "Meeting session key not available".to_string(),
                details: None,
            })
    }

    /// Returns cached pre-join SRP auth when link + display name match; clears the cache.
    pub async fn try_take_prejoin_srp_auth(
        &self,
        meet_link_name: &str,
        display_name: &str,
    ) -> Option<MeetInfo> {
        let mut state = self.state.write().await;
        let cached = state.prejoin_srp_auth.take()?;
        if cached.meet_link_name == meet_link_name && cached.display_name == display_name {
            state.active_livekit_access_token = Some(cached.meet_info.access_token.clone());
            state.active_livekit_websocket_url = Some(cached.meet_info.websocket_url.clone());
            Some(cached.meet_info)
        } else {
            None
        }
    }

    pub async fn clear_prejoin_srp_auth(&self) {
        let mut state = self.state.write().await;
        state.prejoin_srp_auth = None;
    }

    /// Creates an MLS client from the cached pre-join access token so group info can be polled.
    #[tracing::instrument(err, skip_all)]
    pub async fn prepare_mls_session_for_waiting_room(
        &self,
        meet_link_name: String,
        meet_link_password: String,
    ) -> Result<(), MeetCoreError> {
        self.ensure_mls_session_for_group_info(
            None,
            Some(meet_link_name),
            Some(meet_link_password),
            None,
        )
        .await
    }

    /// Same as [`Self::prepare_mls_session_for_waiting_room`] but accepts an explicit access token
    /// (for web flows that already have SRP credentials before join).
    #[tracing::instrument(err, skip_all)]
    pub async fn prepare_mls_session_for_waiting_room_with_access_token(
        &self,
        access_token: String,
        meet_link_name: String,
        meet_link_password: String,
        session_id: Option<String>,
    ) -> Result<(), MeetCoreError> {
        self.ensure_mls_session_for_group_info(
            Some(access_token),
            Some(meet_link_name),
            Some(meet_link_password),
            session_id.as_deref(),
        )
        .await
    }

    pub(crate) async fn ensure_mls_session_for_group_info(
        &self,
        access_token: Option<String>,
        meet_link_name: Option<String>,
        meet_link_password: Option<String>,
        session_id: Option<&str>,
    ) -> Result<(), MeetCoreError> {
        {
            let state = self.state.read().await;
            if let Some(user_info) = &state.active_user_info {
                let store = state.mls_store.read().await;
                let cs = store.config.ciphersuite;
                if store
                    .clients
                    .get(&user_info.user_id().to_string())
                    .and_then(|clients| clients.get(&cs))
                    .is_some()
                {
                    return Ok(());
                }
            }
        }

        let (access_token, meet_link_name, meet_link_password) =
            match (access_token, meet_link_name, meet_link_password) {
                (Some(token), Some(name), Some(password)) => (token, name, password),
                (None, Some(name), Some(password)) => {
                    let token = self
                        .state
                        .read()
                        .await
                        .active_livekit_access_token
                        .clone()
                        .ok_or(MeetCoreError::InternalError {
                            message: "No cached access token for waiting room".to_string(),
                            details: None,
                        })?;
                    (token, name, password)
                }
                (None, None, None) => {
                    let state = self.state.read().await;
                    let cached =
                        state
                            .prejoin_srp_auth
                            .as_ref()
                            .ok_or(MeetCoreError::InternalError {
                                message: "No active MLS session".to_string(),
                                details: None,
                            })?;
                    let token = state.active_livekit_access_token.clone().ok_or(
                        MeetCoreError::InternalError {
                            message: "No cached access token for waiting room".to_string(),
                            details: None,
                        },
                    )?;
                    (
                        token,
                        cached.meet_link_name.clone(),
                        cached.meet_link_password.clone(),
                    )
                }
                _ => {
                    return Err(MeetCoreError::InternalError {
                        message: "Missing meeting credentials for MLS session".to_string(),
                        details: None,
                    });
                }
            };

        let user_info = self
            .user_service
            .read()
            .await
            .create_mls_client(
                &access_token,
                &meet_link_name,
                &meet_link_password,
                session_id,
            )
            .await?;

        let mut state = self.state.write().await;
        state.active_user_info = Some(user_info);
        state.active_livekit_access_token = Some(access_token);
        Ok(())
    }

    pub(crate) async fn has_mls_group_info_after_session(&self) -> Result<bool, MeetCoreError> {
        let user_info = self.state.read().await.active_user_info.clone().ok_or(
            MeetCoreError::InternalError {
                message: "No active MLS session".to_string(),
                details: None,
            },
        )?;

        self.user_service
            .read()
            .await
            .has_mls_group_info(&user_info.user_id())
            .await
    }

    /// Returns whether MLS group info exists (host has started the meeting).
    ///
    /// Checks via group info summary (`?summary=true`), not the full group info payload.
    #[tracing::instrument(err, skip_all)]
    pub async fn has_mls_group_info(&self) -> Result<bool, MeetCoreError> {
        self.ensure_mls_session_for_group_info(None, None, None, None)
            .await?;
        self.has_mls_group_info_after_session().await
    }
}
