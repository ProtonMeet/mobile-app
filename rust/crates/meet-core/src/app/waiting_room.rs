use std::future::Future;

use super::App;
use crate::domain::room::{JoinRequestChange, SubmitJoinRequestResponse};
use crate::domain::user::models::{
    meeting_link_name::MeetingLinkName, meeting_session_key::MeetingSessionKey,
};
use crate::domain::user::ports::UserService;
use crate::errors::core::MeetCoreError;
use crate::infra::dto::realtime::JoinType;
use crate::service::service::Service;
use crate::utils::spawn_detached;

impl App {
    pub async fn create_join_request(
        &self,
        meet_link_name: String,
        meeting_session_key: MeetingSessionKey,
    ) -> Result<SubmitJoinRequestResponse, MeetCoreError> {
        tracing::info!("create_join_request start");
        if self.has_prejoin_srp_auth_for(&meet_link_name).await {
            tracing::debug!("moile prejoin srp auth found, refreshing waiting room guest session");
            self.refresh_waiting_room_guest_session_for_join_request(&meet_link_name)
                .await?;
        }
        let user_id = self.current_user_id().await.map_err(|_| {
            MeetCoreError::InternalError {
                message: "No active MLS session for join request. Call prepareMlsSessionForWaitingRoom or refreshWaitingRoomGuestSessionForJoinRequest first.".to_string(),
                details: None,
            }
        })?;
        let join_request = self
            .waiting_room_service
            .create_join_request(&meet_link_name.into(), &user_id, &meeting_session_key)
            .await
            .map_err(MeetCoreError::from)?;
        let meet_link_name = join_request.meeting_link_name.as_str().to_string();
        let request_id = self
            .user_service
            .read()
            .await
            .submit_join_request(
                &user_id,
                &meet_link_name,
                &join_request.encrypted_key_package,
            )
            .await?;

        {
            let mut state = self.state.write().await;
            state.pending_waiting_room_join_request_id = Some(request_id.clone());
            state.used_waiting_room_for_join = Some(true);
        }

        self.connect_websocket_for_waiting_room().await?;

        tracing::info!("create_join_request success request_id={}", request_id);
        Ok(SubmitJoinRequestResponse { request_id })
    }

    /// Waits for host admit (Welcome) after [`Self::create_join_request`], then joins the MLS group.
    #[tracing::instrument(err, skip_all)]
    pub async fn wait_for_waiting_room_welcome(
        &self,
        meet_link_name: String,
    ) -> Result<(), MeetCoreError> {
        tracing::info!("wait_for_waiting_room_welcome start");
        let user_id = self.current_user_id().await?;

        {
            let mut state = self.state.write().await;
            state.join_start_time = state
                .join_start_time
                .or_else(|| Some(crate::utils::instant::now()));
        }

        self.user_service
            .read()
            .await
            .wait_for_join_proposal_welcome_and_join(
                &user_id,
                meet_link_name.as_str(),
                Some(crate::service::service::WAITING_ROOM_WELCOME_TIMEOUT),
            )
            .await?;

        {
            let mut state = self.state.write().await;
            state.join_mls_time = Some(crate::utils::instant::now());
            state.join_type = Some(JoinType::ExternalProposal);
        }

        tracing::info!("wait_for_waiting_room_welcome success");

        Ok(())
    }

    /// Connects the MLS websocket so waiting-room join decisions can be received.
    pub async fn connect_websocket_for_waiting_room(&self) -> Result<(), MeetCoreError> {
        tracing::info!("connect_websocket_for_waiting_room start");
        self.connect_to_ws().await?;
        tracing::info!("connect_websocket_for_waiting_room success");
        Ok(())
    }

    /// Resets local guest waiting-room admission state only. Does not call the server
    /// cancel endpoint or disconnect the MLS websocket. Use after host reject/admit when
    /// the server has already purged the join request.
    pub async fn clear_waiting_room_join_request(&self) {
        self.user_service
            .read()
            .await
            .reset_waiting_room_guest_join_state()
            .await;
        let mut state = self.state.write().await;
        state.pending_waiting_room_join_request_id = None;
    }

    /// Cancels the guest's outstanding waiting-room join request on the server (when a
    /// `request_id` was stored), resets local admission state, and disconnects the MLS
    /// websocket. Idempotent; skips DELETE when no request was submitted.
    pub async fn cancel_waiting_room_join_request(
        &self,
        meet_link_name: String,
    ) -> Result<(), MeetCoreError> {
        let user_id = self.current_user_id().await?;
        let should_delete = {
            let state = self.state.read().await;
            state.pending_waiting_room_join_request_id.is_some()
        };

        if should_delete {
            tracing::info!(
                "cancel_waiting_room_join_request start meet_link_name={}",
                meet_link_name
            );
            self.user_service
                .read()
                .await
                .cancel_join_request(&user_id, &meet_link_name)
                .await?;
        } else {
            self.user_service
                .read()
                .await
                .reset_waiting_room_guest_join_state()
                .await;
        }

        {
            let mut state = self.state.write().await;
            state.pending_waiting_room_join_request_id = None;
        }

        if let Err(e) = self.disconnect_from_ws().await {
            tracing::warn!(
                meet_link_name = %meet_link_name,
                error = %e,
                "disconnect_from_ws failed after cancel; local state already reset"
            );
        }

        tracing::info!(
            "cancel_waiting_room_join_request success, should_delete={}",
            should_delete
        );

        Ok(())
    }

    pub async fn is_mls_group_joined(&self) -> bool {
        self.user_service.read().await.is_mls_group_joined().await
    }

    pub async fn set_join_decision_handler<F, Fut>(&self, callback: F)
    where
        F: Fn(String, bool) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        self.user_service
            .write()
            .await
            .set_join_decision_handler(callback);
    }

    pub async fn clear_join_decision_handler(&self) {
        self.user_service
            .write()
            .await
            .clear_join_decision_handler();
    }

    pub async fn set_join_request_handler<F, Fut>(&self, callback: F)
    where
        F: Fn(JoinRequestChange, String, String, u64) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        self.user_service
            .write()
            .await
            .set_join_request_handler(callback);

        let user_service = self.user_service.clone();
        spawn_detached(async move {
            user_service
                .read()
                .await
                .notify_pending_waiting_room_join_requests()
                .await;
        });
    }

    pub async fn clear_join_request_handler(&self) {
        self.user_service.write().await.clear_join_request_handler();
    }

    pub async fn reject_waiting_room_join_request(
        &self,
        meet_link_name: String,
        request_id: String,
        participant_uid: String,
    ) -> Result<(), MeetCoreError> {
        tracing::info!(
            "reject_waiting_room_join_request start meet_link_name={} request_id={} participant_uid={}",
            meet_link_name, request_id, participant_uid
        );
        let user_id = self.current_user_id().await?;

        self.user_service
            .read()
            .await
            .reject_waiting_room_join_request(
                &user_id,
                &meet_link_name,
                &request_id,
                &participant_uid,
            )
            .await
    }

    pub async fn admit_waiting_room_join_request(
        &self,
        meet_link_name: String,
        request_id: String,
    ) -> Result<(), MeetCoreError> {
        tracing::info!(
            "admit_waiting_room_join_request start meet_link_name={} request_id={}",
            meet_link_name,
            request_id
        );
        self.admit_waiting_room_join_requests_internal(meet_link_name, Some(vec![request_id]), None)
            .await
            .map(|_| ())
    }

    pub async fn admit_all_waiting_room_join_requests(
        &self,
        meet_link_name: String,
        meeting_session_key: Option<MeetingSessionKey>,
    ) -> Result<Vec<String>, MeetCoreError> {
        tracing::info!(
            "admit_all_waiting_room_join_requests start meet_link_name={}",
            meet_link_name
        );
        self.admit_waiting_room_join_requests_internal(meet_link_name, None, meeting_session_key)
            .await
    }

    pub async fn update_waiting_room_setting(
        &self,
        meet_link_name: String,
        enable: bool,
        meeting_session_key: Option<MeetingSessionKey>,
    ) -> Result<(), MeetCoreError> {
        if !enable {
            if let Err(e) = self
                .admit_all_waiting_room_join_requests(meet_link_name.clone(), meeting_session_key)
                .await
            {
                tracing::warn!("best-effort admit before WR disable failed: {e:?}");
            }
        }
        let user_id = self.current_user_id().await?;
        self.user_service
            .read()
            .await
            .update_waiting_room_setting_policy(&user_id, &meet_link_name, enable)
            .await
    }

    /// Updates waiting-room policy before the meeting starts (direct backend API, no MLS commit).
    pub async fn update_waiting_room_setting_pre_meeting(
        &self,
        meet_link_name: String,
        enable: bool,
    ) -> Result<(), MeetCoreError> {
        tracing::info!(
            "update_waiting_room_setting_pre_meeting meet_link_name={} enable={}",
            meet_link_name,
            enable
        );
        self.meeting_api
            .update_waiting_room_setting_pre_meeting(&meet_link_name, enable)
            .await?;
        Ok(())
    }

    pub(crate) async fn admit_waiting_room_join_requests_internal(
        &self,
        meet_link_name: String,
        request_ids: Option<Vec<String>>,
        meeting_session_key: Option<MeetingSessionKey>,
    ) -> Result<Vec<String>, MeetCoreError> {
        tracing::debug!(
            "admit_waiting_room_join_requests_internal start meet_link_name={} request_count={}",
            meet_link_name,
            request_ids.as_ref().map(|ids| ids.len()).unwrap_or(0)
        );
        let user_id = self.current_user_id().await?;
        let session_key = match meeting_session_key {
            Some(key) => key,
            None => MeetingSessionKey::from(self.get_meeting_display_name_session_key().await?),
        };
        let meeting_link_name = MeetingLinkName::from(meet_link_name.as_str());
        let pending = self
            .user_service
            .read()
            .await
            .pending_waiting_room_join_requests_for_admit(request_ids.clone())
            .await;
        if pending.is_empty() {
            if request_ids.is_some() {
                tracing::warn!(
                    "waiting-room join request not found for admit meet_link_name={}",
                    meet_link_name
                );
                return Err(MeetCoreError::WaitingRoomJoinRequestNotFound);
            }
            tracing::info!(
                "no pending waiting-room join requests to admit meet_link_name={}",
                meet_link_name
            );
            return Ok(vec![]);
        }

        tracing::info!(
            "admit_waiting_room_join_requests_internal start meet_link_name={} pending_count={}",
            meet_link_name,
            pending.len()
        );

        let mut key_packages = Vec::with_capacity(pending.len());
        let mut admitted_request_ids = Vec::with_capacity(pending.len());
        for request in &pending {
            let serialized = self
                .waiting_room_service
                .decrypt_key_package(
                    &request.encrypted_key_package,
                    &meeting_link_name,
                    &session_key,
                )
                .await?;
            let key_package = Service::parse_key_package_bytes(&serialized)?;
            key_packages.push(key_package);
            admitted_request_ids.push(request.request_id.clone());
        }
        let admitted_request_ids = self
            .user_service
            .write()
            .await
            .admit_waiting_room_join_requests(
                &user_id,
                meeting_link_name.as_str(),
                key_packages,
                admitted_request_ids,
            )
            .await?;
        tracing::info!(
            "admit_waiting_room_join_requests_internal success meet_link_name={} admitted_request_ids={:?}",
            meet_link_name,
            admitted_request_ids
        );
        Ok(admitted_request_ids)
    }
}
