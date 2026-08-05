use super::App;
use crate::app_state::PrejoinSrpAuth;
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

    /// Clears the guest MLS client and cached LiveKit tokens before a new waiting-room request.
    pub(crate) async fn clear_prejoin_waiting_room_mls_session(&self) -> Result<(), MeetCoreError> {
        if self.is_mls_group_joined().await {
            return Ok(());
        }

        self.user_service
            .read()
            .await
            .reset_waiting_room_guest_join_state()
            .await;

        let participant_id = self
            .state
            .read()
            .await
            .active_user_info
            .as_ref()
            .map(|info| info.user_id().to_string());

        let mut state = self.state.write().await;
        state.active_user_info = None;
        state.active_livekit_access_token = None;
        state.active_livekit_websocket_url = None;
        if let Some(participant_id) = participant_id {
            state
                .mls_store
                .write()
                .await
                .clients
                .remove(&participant_id);
        }

        Ok(())
    }

    /// Disconnects and clears guest MLS state before rebuilding for a new join request.
    /// Returns `Ok(false)` when MLS is already joined (no refresh needed).
    ///
    /// When `disconnect_ws` is false (WASM access-token refresh), WS lifecycle is left to
    /// `cancelWaitingRoomJoinRequest` (teardown) and `createJoinRequest` (connect).
    async fn refresh_waiting_room_guest_session(
        &self,
        meet_link_name: &str,
        disconnect_ws: bool,
    ) -> Result<bool, MeetCoreError> {
        if self.is_mls_group_joined().await {
            return Ok(false);
        }

        tracing::debug!(
            meet_link_name = %meet_link_name,
            disconnect_ws = disconnect_ws,
            "refresh_waiting_room_guest_session"
        );
        if (disconnect_ws) {
            if let Err(error) = self.disconnect_from_ws().await {
                tracing::debug!(
                    meet_link_name,
                    error = %error,
                    "disconnect before waiting-room join request refresh (best effort)"
                );
            }
        }

        self.clear_prejoin_waiting_room_mls_session().await?;
        Ok(true)
    }

    /// Clears guest MLS state and rebuilds the session from a JS-supplied access token (WASM).
    pub async fn refresh_waiting_room_guest_session_for_join_request_with_access_token(
        &self,
        access_token: String,
        meet_link_name: String,
        meet_link_password: String,
        session_id: Option<String>,
    ) -> Result<(), MeetCoreError> {
        if !self
            .refresh_waiting_room_guest_session(&meet_link_name, false)
            .await?
        {
            return Ok(());
        }

        {
            let mut state = self.state.write().await;
            state.active_livekit_access_token = Some(access_token.clone());
        }

        self.prepare_mls_session_for_waiting_room_with_access_token(
            access_token,
            meet_link_name,
            meet_link_password,
            session_id,
        )
        .await
    }

    /// Re-authenticates via SRP and rebuilds the MLS session (Flutter pre-join flow).
    pub(crate) async fn refresh_waiting_room_guest_session_for_join_request(
        &self,
        meet_link_name: &str,
    ) -> Result<(), MeetCoreError> {
        if !self
            .refresh_waiting_room_guest_session(meet_link_name, true)
            .await?
        {
            return Ok(());
        }

        let cached_auth = self
            .state
            .read()
            .await
            .prejoin_srp_auth
            .clone()
            .filter(|auth| auth.meet_link_name == meet_link_name);

        let PrejoinSrpAuth {
            meet_link_name,
            meet_link_password,
            display_name,
            ..
        } = cached_auth.ok_or(MeetCoreError::InternalError {
            message: "No pre-join auth cached for waiting room join request".to_string(),
            details: None,
        })?;

        self.authenticate_meeting_link(
            meet_link_name.clone(),
            meet_link_password.clone(),
            display_name,
        )
        .await?;

        self.prepare_mls_session_for_waiting_room(meet_link_name, meet_link_password)
            .await
    }

    pub(crate) async fn has_prejoin_srp_auth_for(&self, meet_link_name: &str) -> bool {
        self.state
            .read()
            .await
            .prejoin_srp_auth
            .as_ref()
            .is_some_and(|auth| auth.meet_link_name == meet_link_name)
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
