use super::App;
use crate::domain::user::models::MeetInfo;
use crate::domain::user::models::{
    UserId, access_token::AccessToken, meet_link_info::MeetParticipant,
    meeting_link_name::MeetingLinkName, meeting_password::MeetingPassword,
};
use crate::domain::user::ports::{UserService, new_user_service::NewUserService};
use crate::errors::core::MeetCoreError;
use crate::infra::dto::realtime::JoinType;
use crate::utils::{instant, try_join};
use backon::{ExponentialBuilder, Retryable};
use std::time::Duration;
use tracing::{debug, error, info, warn};

#[cfg(not(target_family = "wasm"))]
use tokio::time::sleep;
#[cfg(target_family = "wasm")]
use wasmtimer::tokio::sleep;

impl App {
    pub(crate) async fn current_user_id(&self) -> Result<UserId, MeetCoreError> {
        let state = self.state.read().await;
        state
            .active_user_info
            .as_ref()
            .map(|info| info.user_id())
            .ok_or(MeetCoreError::NoActiveUser)
    }

    pub async fn leave_meeting(&self) -> Result<(), MeetCoreError> {
        // Step 1: clone necessary data first
        let (participant_id, meeting_id) = {
            let app_state = self.state.read().await;
            let user_info = app_state
                .active_user_info
                .as_ref()
                .ok_or(MeetCoreError::ParticipantNotFound)?;
            let user_id = user_info.user_id();
            let meeting_id = self
                .services
                .user_service
                .read()
                .await
                .get_meeting_id(&user_id)
                .await?;
            (user_id, meeting_id)
        };
        // Step 2: Leave room
        self.services
            .user_service
            .read()
            .await
            .leave_room(&participant_id, &meeting_id)
            .await?;
        // Step 3: Disconnect from WebSocket
        self.disconnect_from_ws().await?;

        // Step 4: Modify state (no overlapping locks)
        {
            let mut state = self.state.write().await;
            state.meeting_display_name_session_key = None;
            let mut store = state.mls_store.write().await;
            store.clients.remove(&participant_id.to_string());
        }

        Ok(())
    }

    pub async fn end_meeting(&self) -> Result<(), MeetCoreError> {
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        let meeting_id = self
            .services
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;
        let livekit_access_token = app_state
            .active_livekit_access_token
            .as_ref()
            .ok_or(MeetCoreError::LivekitAccessTokenNotFound)?;
        self.services
            .room_service
            .end_meeting(&meeting_id, livekit_access_token)
            .await?;

        self.disconnect_from_ws().await?;

        Ok(())
    }

    pub async fn join_meeting(
        &self,
        access_token: AccessToken,
        meet_link_name: MeetingLinkName,
        meeting_password: MeetingPassword,
        session_id: Option<String>,
        switch_join_type: bool,
        is_waiting_room: bool,
    ) -> Result<(), MeetCoreError> {
        if is_waiting_room && self.is_mls_group_joined().await {
            tracing::info!(
                "join_meeting: waiting room flow with MLS already joined, skipping MLS join"
            );
            let now = crate::utils::instant::now();
            {
                let mut state = self.state.write().await;
                state.join_start_time = state.join_start_time.or(Some(now));
                state.join_mls_time = Some(now);
                state.active_livekit_access_token = Some(access_token.expose_secret().to_string());
                state.used_waiting_room_for_join = Some(true);
            }
            return Ok(());
        }

        // Record join start time
        {
            let mut state = self.state.write().await;
            state.join_start_time = Some(crate::utils::instant::now());
            state.join_mls_time = None;
            if is_waiting_room {
                state.used_waiting_room_for_join = Some(true);
            } else if state.used_waiting_room_for_join != Some(true) {
                state.used_waiting_room_for_join = Some(false);
            }
        }
        let mls_start = instant::now();
        let user_info = self
            .services
            .user_service
            .read()
            .await
            .create_mls_client(
                access_token.expose_secret(),
                meet_link_name.as_str(),
                meeting_password.expose_secret(),
                session_id.as_deref(),
            )
            .await?;
        debug!(
            "join_meeting_with_access_token step=create_mls_client ms={} user={:?} device_id={}",
            mls_start.elapsed().as_millis(),
            &user_info.user_identifier,
            &user_info.device_id,
        );
        debug!(
            "MLS client created for user: {:?}, device_id: {}",
            &user_info.user_identifier, &user_info.device_id,
        );

        let state_start = instant::now();
        {
            let mut state = self.state.write().await;
            state.active_user_info = Some(user_info.clone());
            state.active_livekit_access_token = Some(access_token.expose_secret().to_string());
        }
        debug!(
            "join_meeting_with_access_token step=store_state ms={}",
            state_start.elapsed().as_millis()
        );

        let join_and_connect_start = instant::now();

        let connect_ws_fut = Box::pin(self.connect_to_ws());
        let join_room_fut =
            Box::pin(self.join_room_with_switch_join_type(switch_join_type, is_waiting_room));

        let result = try_join(connect_ws_fut, join_room_fut).await;

        if let Err(e) = result {
            error!(
                "Error connecting to WebSocket or joining room: {:?}, ms={}",
                &e,
                join_and_connect_start.elapsed().as_millis()
            );

            self.services.reset().await;
            if let Err(disconnect_err) = self.disconnect_from_ws().await {
                warn!("Failed to disconnect from websocket: {:?}", disconnect_err);
            }
            return Err(e);
        }

        info!(
            "Connected to WebSocket and joined room ms={}",
            join_and_connect_start.elapsed().as_millis()
        );

        // Check if user is host and update role if needed
        let user_id = user_info.user_id();
        let user_service = self.services.user_service.read().await;
        if let Ok(meeting_id) = user_service.get_meeting_id(&user_id).await
            && let Err(e) = user_service.check_and_update_host_role(&meeting_id).await
        {
            warn!(
                "Failed to check and update host role after proposal join: {:?}",
                e
            );
            // Don't fail the join if role update fails
        }

        Ok(())
    }

    pub async fn join_meeting2(
        &self,
        access_token: AccessToken,
        meet_link_name: MeetingLinkName,
        meeting_password: MeetingPassword,
        session_id: Option<String>,
        is_waiting_room: bool,
    ) -> Result<(), MeetCoreError> {
        if is_waiting_room && self.is_mls_group_joined().await {
            tracing::info!(
                "join_meeting: waiting room flow with MLS already joined, skipping MLS join"
            );
            let now = crate::utils::instant::now();
            {
                let mut state = self.state.write().await;
                state.join_start_time = state.join_start_time.or(Some(now));
                state.join_mls_time = Some(now);
                state.active_livekit_access_token = Some(access_token.expose_secret().to_string());
                state.used_waiting_room_for_join = Some(true);
            }
            return Ok(());
        }

        // Record join start time
        {
            let mut state = self.state.write().await;
            state.join_start_time = Some(crate::utils::instant::now());
            state.join_mls_time = None;
            if is_waiting_room {
                state.used_waiting_room_for_join = Some(true);
            } else if state.used_waiting_room_for_join != Some(true) {
                state.used_waiting_room_for_join = Some(false);
            }
        }
        let mls_start = instant::now();
        let user_info = self
            .services
            .user_service
            .read()
            .await
            .create_mls_client(
                access_token.expose_secret(),
                meet_link_name.as_str(),
                meeting_password.expose_secret(),
                session_id.as_deref(),
            )
            .await?;
        debug!(
            "join_meeting_with_access_token step=create_mls_client ms={} user={:?} device_id={}",
            mls_start.elapsed().as_millis(),
            &user_info.user_identifier,
            &user_info.device_id,
        );
        debug!(
            "MLS client created for user: {:?}, device_id: {}",
            &user_info.user_identifier, &user_info.device_id,
        );

        let state_start = instant::now();
        {
            let mut state = self.state.write().await;
            state.active_user_info = Some(user_info.clone());
            state.active_livekit_access_token = Some(access_token.expose_secret().to_string());
        }
        debug!(
            "join_meeting_with_access_token step=store_state ms={}",
            state_start.elapsed().as_millis()
        );

        let join_and_connect_start = instant::now();

        let connect_ws_fut = Box::pin(self.connect_to_ws());
        let join_room_fut = Box::pin(self.join_room_with_switch_join_type2(is_waiting_room));

        let result = try_join(connect_ws_fut, join_room_fut).await;

        if let Err(e) = result {
            error!(
                "Error connecting to WebSocket or joining room: {:?}, ms={}",
                &e,
                join_and_connect_start.elapsed().as_millis()
            );

            self.services.reset().await;
            if let Err(disconnect_err) = self.disconnect_from_ws().await {
                warn!("Failed to disconnect from websocket: {:?}", disconnect_err);
            }
            return Err(e);
        }

        info!(
            "Connected to WebSocket and joined room ms={}",
            join_and_connect_start.elapsed().as_millis()
        );

        // Check if user is host and update role if needed
        let user_id = user_info.user_id();
        let lock = self.services.user_service.read().await;
        if let Ok(meeting_id) = lock.get_meeting_id(&user_id).await
            && let Err(e) = lock.check_and_update_host_role(&meeting_id).await
        {
            warn!(
                "Failed to check and update host role after proposal join: {:?}",
                e
            );
            // Don't fail the join if role update fails
        }

        Ok(())
    }

    pub async fn join_meeting_from_info2(
        &self,
        meeting_info: &MeetInfo,
        password: String,
        session_id: Option<String>,
        is_waiting_room: bool,
    ) -> Result<(), MeetCoreError> {
        self.join_meeting2(
            meeting_info.access_token.clone().into(),
            meeting_info.meet_link_name.clone().into(),
            password.into(),
            session_id,
            is_waiting_room,
        )
        .await
    }

    pub async fn join_meeting_with_access_token(
        &self,
        access_token: String,
        meet_link_name: String,
        meeting_password: String,
        session_id: Option<String>,
    ) -> Result<(), MeetCoreError> {
        // Record join start time
        {
            let mut state = self.state.write().await;
            state.join_start_time = Some(crate::utils::instant::now());
            state.join_mls_time = None;
        }

        let mls_start = instant::now();
        let user_info = self
            .services
            .user_service
            .read()
            .await
            .create_mls_client(
                &access_token,
                &meet_link_name,
                &meeting_password,
                session_id.as_deref(),
            )
            .await?;
        debug!(
            "join_meeting_with_access_token step=create_mls_client ms={} user={:?} device_id={}",
            mls_start.elapsed().as_millis(),
            &user_info.user_identifier,
            &user_info.device_id,
        );
        debug!(
            "MLS client created for user: {:?}, device_id: {}",
            &user_info.user_identifier, &user_info.device_id,
        );

        let state_start = instant::now();
        {
            let mut state = self.state.write().await;
            state.active_user_info = Some(user_info.clone());
            state.active_livekit_access_token = Some(access_token.clone());
        }
        debug!(
            "join_meeting_with_access_token step=store_state ms={}",
            state_start.elapsed().as_millis()
        );

        let join_and_connect_start = instant::now();

        let connect_ws_fut = Box::pin(self.connect_to_ws());
        let join_room_fut = Box::pin(self.join_room());

        let result = try_join(connect_ws_fut, join_room_fut).await;

        if let Err(e) = result {
            error!(
                "Error connecting to WebSocket or joining room: {:?}, ms={}",
                &e,
                join_and_connect_start.elapsed().as_millis()
            );

            self.services.reset().await;
            if let Err(disconnect_err) = self.disconnect_from_ws().await {
                warn!("Failed to disconnect from websocket: {:?}", disconnect_err);
            }
            return Err(e);
        }

        info!(
            "Connected to WebSocket and joined room ms={}",
            join_and_connect_start.elapsed().as_millis()
        );
        Ok(())
    }

    pub async fn join_meeting_with_access_token_with_proposal(
        &self,
        access_token: String,
        meet_link_name: String,
        meeting_password: String,
        session_id: Option<String>,
    ) -> Result<(), MeetCoreError> {
        // Record join start time
        {
            let mut state = self.state.write().await;
            state.join_start_time = Some(crate::utils::instant::now());
            state.join_mls_time = None;
        }

        let user_info = self
            .services
            .user_service
            .read()
            .await
            .create_mls_client(
                &access_token,
                &meet_link_name,
                &meeting_password,
                session_id.as_deref(),
            )
            .await?;
        debug!(
            "MLS client created for user: {:?}, device_id: {}",
            &user_info.user_identifier, &user_info.device_id,
        );

        {
            let mut state = self.state.write().await;
            state.active_user_info = Some(user_info.clone());
            state.active_livekit_access_token = Some(access_token.clone());
        } // lock released here

        let join_and_connect_start = instant::now();
        let connect_ws_fut = Box::pin(self.connect_to_ws());
        let join_room_fut = Box::pin(self.join_room_with_proposal());
        let result = try_join(connect_ws_fut, join_room_fut).await;

        if let Err(e) = result {
            error!(
                "Error connecting to WebSocket or joining room with proposal: {:?}, ms={}",
                &e,
                join_and_connect_start.elapsed().as_millis()
            );
            self.services.reset().await;
            if let Err(disconnect_err) = self.disconnect_from_ws().await {
                warn!("Failed to disconnect from websocket: {:?}", disconnect_err);
            }
            return Err(e);
        }

        info!(
            "Joined room with proposal ms={}",
            join_and_connect_start.elapsed().as_millis()
        );

        // Check if user is host and update role if needed
        let user_id = user_info.user_id();

        let meeting_id_res = self
            .services
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await;

        if let Ok(meeting_id) = meeting_id_res
            && let Err(e) = self
                .services
                .user_service
                .read()
                .await
                .check_and_update_host_role(&meeting_id)
                .await
        {
            warn!(
                "Failed to check and update host role after proposal join: {:?}",
                e
            );
            // Don't fail the join if role update fails
        }

        Ok(())
    }

    pub async fn update_livekit_access_token(
        &self,
        access_token: String,
    ) -> Result<(), MeetCoreError> {
        self.state.write().await.active_livekit_access_token = Some(access_token);
        debug!("Updated livekit access token");
        Ok(())
    }

    pub async fn update_livekit_access_token_and_websocket_url(
        &self,
        access_token: String,
        websocket_url: String,
    ) -> Result<(), MeetCoreError> {
        self.state.write().await.active_livekit_access_token = Some(access_token);
        self.state.write().await.active_livekit_websocket_url = Some(websocket_url);
        debug!("Updated livekit access token and websocket url");
        Ok(())
    }
    pub async fn get_active_livekit_access_token(&self) -> Result<String, MeetCoreError> {
        self.state
            .read()
            .await
            .active_livekit_access_token
            .clone()
            .ok_or(MeetCoreError::LivekitAccessTokenNotFound)
    }

    pub async fn get_active_livekit_websocket_url(&self) -> Result<String, MeetCoreError> {
        self.state
            .read()
            .await
            .active_livekit_websocket_url
            .clone()
            .ok_or(MeetCoreError::InternalError {
                message: "Livekit websocket url not found".to_string(),
                details: None,
            })
    }

    pub(crate) async fn connect_to_ws(&self) -> Result<(), MeetCoreError> {
        let total_start = instant::now();
        let app_state = self.state.read().await;

        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?
            .clone();
        let user_id = user_info.user_id();
        let sd_start = instant::now();
        let sd_kbt = self
            .services
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_id)
            .await?;
        debug!(
            "connect_to_ws step=get_sd_kbt ms={}",
            sd_start.elapsed().as_millis()
        );

        // need to clone the client to avoid borrow checker error
        let client = self.ws_client.clone();

        // Retry mechanism: retry up to 3 times on HTTP/WebSocket errors
        const MAX_RETRIES: u32 = 3;
        const RETRY_DELAY_MS: u64 = 200;
        let mut last_error = None;

        for attempt in 1..=MAX_RETRIES {
            let attempt_start = instant::now();
            match client.connect(&sd_kbt).await {
                Ok(_) => {
                    if attempt > 1 {
                        warn!(
                            "WebSocket connection succeeded on attempt {} ms={}",
                            attempt,
                            attempt_start.elapsed().as_millis()
                        );
                    } else {
                        debug!(
                            "WebSocket connection succeeded on attempt {} ms={}",
                            attempt,
                            attempt_start.elapsed().as_millis()
                        );
                    }
                    let _ = client.start_listening_task();
                    debug!(
                        "connect_to_ws step=done total_ms={}",
                        total_start.elapsed().as_millis()
                    );
                    return Ok(());
                }
                Err(e) => {
                    let error_msg = e.to_string();
                    last_error = Some(e);

                    if attempt < MAX_RETRIES {
                        warn!(
                            "WebSocket connection failed on attempt {}/{}: {}. attempt_ms={} Retrying...",
                            attempt,
                            MAX_RETRIES,
                            error_msg,
                            attempt_start.elapsed().as_millis()
                        );
                        // Wait 1 second before retrying
                        sleep(Duration::from_millis(RETRY_DELAY_MS)).await;
                    } else {
                        error!(
                            "WebSocket connection failed after {} attempts: {} total_ms={}",
                            MAX_RETRIES,
                            error_msg,
                            total_start.elapsed().as_millis()
                        );
                    }
                }
            }
        }

        // Convert anyhow::Error to MeetCoreError
        // This should never be None since we only reach here if all retries failed
        match last_error {
            Some(error) => Err(MeetCoreError::WebSocketError {
                message: error.to_string(),
            }),
            None => Err(MeetCoreError::WebSocketError {
                message: "WebSocket connection failed: unknown error".to_string(),
            }),
        }
    }

    pub(crate) async fn disconnect_from_ws(&self) -> Result<(), MeetCoreError> {
        Ok(self.ws_client.disconnect(Some(true)).await?)
    }

    /// Manually trigger WebSocket reconnection, typically called when network connectivity changes.
    /// This is useful for mobile apps to proactively reconnect when switching networks.
    pub async fn trigger_websocket_reconnect(&self) -> Result<(), MeetCoreError> {
        self.ws_client
            .trigger_reconnect()
            .await
            .map_err(|e| MeetCoreError::WebSocketError {
                message: e.to_string(),
            })
    }

    pub async fn get_participants(
        &self,
        meet_link_name: String,
    ) -> Result<Vec<MeetParticipant>, MeetCoreError> {
        let session_key = self
            .state
            .read()
            .await
            .meeting_display_name_session_key
            .clone();
        let participants = self
            .services
            .room_service
            .get_participants(&meet_link_name)
            .await?;
        let participants = self
            .services
            .room_service
            .decrypt_participant_display_names(participants, session_key.as_ref())
            .await;
        Ok(participants)
    }

    pub async fn get_participants_count(
        &self,
        meet_link_name: String,
    ) -> Result<u32, MeetCoreError> {
        let count = self
            .services
            .room_service
            .get_participants_count(&meet_link_name)
            .await?;
        Ok(count)
    }

    pub async fn lock_meeting(&self, meet_link_name: String) -> Result<(), MeetCoreError> {
        self.services
            .room_service
            .lock_meeting(&meet_link_name)
            .await?;
        Ok(())
    }

    pub async fn unlock_meeting(&self, meet_link_name: String) -> Result<(), MeetCoreError> {
        self.services
            .room_service
            .unlock_meeting(&meet_link_name)
            .await?;
        Ok(())
    }

    pub fn get_join_type(
        &self,
        is_new_join_type: bool,
        enable_join_type_switch: bool,
        current_participant_count: u32,
    ) -> JoinType {
        debug!(
            "get_join_type(), is_new_join_type={}, enable_join_type_switch={}, current_participant_count={}, threshold={}",
            is_new_join_type,
            enable_join_type_switch,
            current_participant_count,
            crate::JOIN_TYPE_SWITCH_THRESHOLD
        );
        if is_new_join_type && enable_join_type_switch {
            if current_participant_count >= crate::JOIN_TYPE_SWITCH_THRESHOLD {
                debug!("get_join_type() switching to ExternalProposal for large meeting room");
                JoinType::ExternalProposal
            } else {
                debug!("get_join_type() staying on ExternalCommit for small meeting room");
                JoinType::ExternalCommit
            }
        } else if is_new_join_type {
            debug!("get_join_type() switching to ExternalProposal");
            JoinType::ExternalProposal
        } else {
            debug!("get_join_type() staying on ExternalCommit");
            JoinType::ExternalCommit
        }
    }

    pub async fn join_room_with_switch_join_type(
        &self,
        switch_join_type: bool,
        is_waiting_room: bool,
    ) -> Result<(), MeetCoreError> {
        let total_start = instant::now();
        let user_token_info = {
            let app_state = self.state.read().await;
            app_state
                .active_user_info
                .as_ref()
                .ok_or(MeetCoreError::ParticipantNotFound)?
                .clone()
        };
        let user_id = user_token_info.user_id();
        let meeting_start = instant::now();
        let meeting_id = self
            .services
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;
        debug!(
            "join_room step=get_meeting_id ms={}",
            meeting_start.elapsed().as_millis()
        );

        let join_call_start = instant::now();
        let meeting_link_name = MeetingLinkName::from(meeting_id);

        let join_result = (|| async {
            self.services
                .user_service
                .read()
                .await
                .join_room_with_switch_join_type(
                    &user_token_info,
                    &meeting_link_name,
                    switch_join_type,
                    is_waiting_room,
                )
                .await
        })
        .retry(
            ExponentialBuilder::default()
                .with_max_times(5)
                .with_min_delay(Duration::from_millis(500))
                .with_max_delay(Duration::from_secs(10)),
        )
        .when(|e| e.is_retryable_switch_join())
        .await;

        if let Err(e) = join_result {
            if e.is_retryable_switch_join() {
                debug!(
                    "Error joining room with switch join type: {:?}, retrying with switch_join_type=false",
                    &e
                );
                self.services
                    .user_service
                    .read()
                    .await
                    .join_room_with_switch_join_type(
                        &user_token_info,
                        &meeting_link_name,
                        false,
                        is_waiting_room,
                    )
                    .await?;
            } else {
                return Err(e);
            }
        }

        {
            let mut app_state = self.state.write().await;
            app_state.join_mls_time = Some(crate::utils::instant::now());
        }
        debug!(
            "join_room step=join_room_call ms={} total_ms={}",
            join_call_start.elapsed().as_millis(),
            total_start.elapsed().as_millis()
        );
        Ok(())
    }

    pub async fn join_room_with_switch_join_type2(
        &self,
        is_waiting_room: bool,
    ) -> Result<(), MeetCoreError> {
        let total_start = instant::now();
        let user_token_info = {
            let app_state = self.state.read().await;
            app_state
                .active_user_info
                .as_ref()
                .ok_or(MeetCoreError::ParticipantNotFound)?
                .clone()
        };
        let user_id = user_token_info.user_id();
        let meeting_start = instant::now();
        let meeting_id = self
            .services
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;
        debug!(
            "join_room step=get_meeting_id ms={}",
            meeting_start.elapsed().as_millis()
        );

        let join_call_start = instant::now();
        let meeting_link_name = MeetingLinkName::from(meeting_id);

        let join_result = (|| async {
            self.services
                .user_service
                .read()
                .await
                .join_room_with_switch_join_type(
                    &user_token_info,
                    &meeting_link_name,
                    true,
                    is_waiting_room,
                )
                .await
        })
        .retry(
            ExponentialBuilder::default()
                .with_max_times(5)
                .with_min_delay(Duration::from_millis(500))
                .with_max_delay(Duration::from_secs(10)),
        )
        .when(|e| e.is_retryable_switch_join())
        .await;

        if let Err(e) = join_result {
            // Attempts one last time with External Commit, in case the join was using External Proposal but all users
            // were unavailable to process the proposal.
            if e.is_retryable_switch_join() {
                debug!(
                    "Error joining room with switch join type: {:?}, retrying with switch_join_type=false",
                    &e
                );
                self.services
                    .user_service
                    .read()
                    .await
                    .join_room_with_switch_join_type(
                        &user_token_info,
                        &meeting_link_name,
                        false,
                        is_waiting_room,
                    )
                    .await?;
            } else {
                return Err(e);
            }
        }

        {
            let mut app_state = self.state.write().await;
            app_state.join_mls_time = Some(crate::utils::instant::now());
        }
        debug!(
            "join_room step=join_room_call ms={} total_ms={}",
            join_call_start.elapsed().as_millis(),
            total_start.elapsed().as_millis()
        );
        Ok(())
    }

    async fn join_room(&self) -> Result<(), MeetCoreError> {
        let total_start = instant::now();
        let user_token_info = {
            let app_state = self.state.read().await;
            app_state
                .active_user_info
                .as_ref()
                .ok_or(MeetCoreError::ParticipantNotFound)?
                .clone()
        };
        let user_id = user_token_info.user_id();
        let meeting_start = instant::now();
        let meeting_id = self
            .services
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;
        debug!(
            "join_room step=get_meeting_id ms={}",
            meeting_start.elapsed().as_millis()
        );

        let join_call_start = instant::now();
        self.services
            .user_service
            .read()
            .await
            .join_room(&user_token_info, &meeting_id)
            .await?;

        {
            let mut app_state = self.state.write().await;
            app_state.join_mls_time = Some(crate::utils::instant::now());
            app_state.join_type = Some(JoinType::ExternalCommit);
        }
        debug!(
            "join_room step=join_room_call ms={} total_ms={}",
            join_call_start.elapsed().as_millis(),
            total_start.elapsed().as_millis()
        );
        Ok(())
    }

    async fn join_room_with_proposal(&self) -> Result<(), MeetCoreError> {
        let total_start = instant::now();
        let user_info = {
            let app_state = self.state.read().await;
            app_state
                .active_user_info
                .as_ref()
                .ok_or(MeetCoreError::ParticipantNotFound)?
                .clone()
        };
        let user_id = user_info.user_id();
        let meeting_start = instant::now();
        let meeting_id = self
            .services
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;
        debug!(
            "join_room_with_proposal step=get_meeting_id ms={}",
            meeting_start.elapsed().as_millis()
        );

        let join_call_start = instant::now();
        self.services
            .user_service
            .read()
            .await
            .join_room_with_proposal(&user_id, &meeting_id)
            .await?;

        {
            let mut app_state = self.state.write().await;
            app_state.join_mls_time = Some(crate::utils::instant::now());
            app_state.join_type = Some(JoinType::ExternalProposal);
        }
        debug!(
            "join_room_with_proposal step=join_room_call ms={} total_ms={}",
            join_call_start.elapsed().as_millis(),
            total_start.elapsed().as_millis()
        );
        Ok(())
    }

    pub async fn kick_participant(&self, participant_id: String) -> Result<(), MeetCoreError> {
        let user_token_info = {
            let app_state = self.state.read().await;
            app_state
                .active_user_info
                .as_ref()
                .ok_or(MeetCoreError::ParticipantNotFound)?
                .clone()
        };
        let user_id = user_token_info.user_id();
        let meeting_id = self
            .services
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await?;

        self.services
            .user_service
            .read()
            .await
            .kick_participant(&participant_id, &meeting_id)
            .await?;

        Ok(())
    }
}
