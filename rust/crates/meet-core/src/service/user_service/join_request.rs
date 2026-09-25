use std::{collections::HashSet, time::Duration};

use crate::{
    domain::{
        room::JoinRequestChange,
        user::{
            models::{meeting_link_name::MeetingLinkName, UserId},
            ports::UserService,
        },
    },
    errors::core::MeetCoreError,
    service::{
        service_state::{MlsGroupState, PendingWaitingRoomJoinRequest},
        user_service::{credential_is_agent, GroupKeyUpdateReason, Service, JOIN_PROPOSAL_TIMEOUT},
        utils::convert_mls_types_to_spec,
    },
    utils::{instant, timeout},
};
use meet_identifiers::AsOwned;
use meet_mls::reexports::meet_policy::UserRole;
use meet_type::fanout::{
    JoinDecisionInfo, JoinDecisionStatus, JoinRequestInfo, JoinRequestRemovedInfo, MlsCommitInfo,
};
use mls_trait::{AuthorizerExt, ProposalArg, ProtonMeetIdentityProvider};
use mls_types::ExternalPskId;
use proton_meet_mls::MlsGroupTrait;

impl Service {
    pub(super) async fn handle_join_request(
        &self,
        info: JoinRequestInfo,
    ) -> Result<(), anyhow::Error> {
        let request_id = String::from_utf8_lossy(&info.request_id).into_owned();
        let participant_uid = String::from_utf8_lossy(&info.participant_uid).into_owned();
        tracing::info!(
            "handle_join_request request_id={} participant_uid={} expires_at={}",
            request_id,
            participant_uid,
            info.expires_at
        );

        {
            let mut state = self.state.lock().await;
            state.pending_waiting_room_join_requests.insert(
                request_id.clone(),
                PendingWaitingRoomJoinRequest {
                    request_id: request_id.clone(),
                    participant_uid: participant_uid.clone(),
                    encrypted_key_package: info.encrypted_key_package,
                    expires_at: info.expires_at,
                },
            );
        }

        self.handlers.call_detached_join_request_handler(
            JoinRequestChange::Added,
            request_id,
            participant_uid,
            info.expires_at,
        );

        Ok(())
    }

    /// Replays join requests that arrived before the host registered a handler.
    pub async fn notify_pending_waiting_room_join_requests(&self) {
        if !self.handlers.has_join_request_handler() {
            return;
        }

        let pending: Vec<PendingWaitingRoomJoinRequest> = {
            let state = self.state.lock().await;
            state
                .pending_waiting_room_join_requests
                .values()
                .cloned()
                .collect()
        };

        if pending.is_empty() {
            return;
        }

        for request in pending {
            tracing::info!(
                request_id = %request.request_id,
                participant_uid = %request.participant_uid,
                "Replaying pending waiting-room join request"
            );

            self.handlers.call_detached_join_request_handler(
                JoinRequestChange::Added,
                request.request_id,
                request.participant_uid,
                request.expires_at,
            );
        }
    }

    pub(super) fn spawn_join_request_removed_notification(
        &self,
        request_id: String,
        participant_uid: String,
    ) {
        self.handlers.call_detached_join_request_handler(
            JoinRequestChange::Removed,
            request_id,
            participant_uid,
            0,
        );
    }

    pub(super) async fn handle_join_request_removed(
        &self,
        info: JoinRequestRemovedInfo,
    ) -> Result<(), anyhow::Error> {
        let participant_uid = String::from_utf8_lossy(&info.participant_uid).into_owned();
        let request_id = String::from_utf8_lossy(&info.request_id).into_owned();

        // Server fanout may omit request_id; removing by participant_uid only would
        // drop a newer re-request from the same guest after a reject.
        if request_id.is_empty() {
            tracing::info!(
                participant_uid = %participant_uid,
                "Ignoring join request removal without request_id"
            );
            return Ok(());
        }

        tracing::info!(
            participant_uid = %participant_uid,
            request_id = %request_id,
            "Processing waiting-room join request removal"
        );

        {
            let mut state = self.state.lock().await;
            state.pending_waiting_room_join_requests.remove(&request_id);
        }

        self.spawn_join_request_removed_notification(request_id, participant_uid);

        Ok(())
    }

    pub(super) async fn handle_join_decision(
        &self,
        info: JoinDecisionInfo,
    ) -> Result<(), anyhow::Error> {
        let request_id = String::from_utf8_lossy(&info.request_id).into_owned();
        let admitted = info.status == JoinDecisionStatus::Admitted;
        tracing::info!(
            request_id = %request_id,
            admitted,
            "Processing join decision"
        );

        if admitted {
            self.handlers
                .call_detached_join_decision_handler(request_id, admitted);
            return Ok(());
        }

        let pending_id = {
            let state = self.state.lock().await;
            let Some(pending) = state.guest_pending_join_request_id.clone() else {
                tracing::info!(
                    request_id = %request_id,
                    "Ignoring join decision reject with no pending guest request"
                );
                return Ok(());
            };
            if request_id.is_empty() {
                tracing::info!(
                    pending = %pending,
                    "Ignoring join decision reject without request_id"
                );
                return Ok(());
            }
            if request_id != pending {
                tracing::info!(
                    request_id = %request_id,
                    pending = %pending,
                    "Ignoring stale join decision reject"
                );
                return Ok(());
            }
            pending
        };

        {
            let mut state = self.state.lock().await;
            if state.guest_pending_join_request_id.as_deref() == Some(pending_id.as_str()) {
                state.guest_pending_join_request_id = None;
            }
        }

        self.handlers
            .call_detached_join_decision_handler(pending_id, false);

        Ok(())
    }

    pub async fn reset_waiting_room_guest_join_state(&self) {
        let mut state = self.state.lock().await;
        state.reset_waiting_room_guest_join_state();
        drop(state);
        self.join_proposal_welcome_notify.notify_waiters();
    }

    /// Guest cancels an outstanding join request on the server (best-effort) and resets
    /// local waiting-room admission state so welcome-wait loops exit.
    pub async fn cancel_join_request(
        &self,
        user_identifier: &UserId,
        meeting_link_name: &str,
    ) -> Result<(), MeetCoreError> {
        let base64_sd_kbt = self.get_sd_kbt(user_identifier).await?;

        if let Err(e) = self
            .mls_api
            .cancel_join_request(&base64_sd_kbt, meeting_link_name)
            .await
        {
            tracing::warn!(
                meeting_link_name,
                error = %e,
                "cancel_join_request HTTP failed; resetting local guest state anyway"
            );
        }

        self.reset_waiting_room_guest_join_state().await;
        Ok(())
    }

    pub async fn submit_join_request(
        &self,
        user_identifier: &UserId,
        meeting_link_name: &str,
        encrypted_key_package: &[u8],
    ) -> Result<String, MeetCoreError> {
        self.reset_waiting_room_guest_join_state().await;

        let base64_sd_kbt = self.get_sd_kbt(user_identifier).await?;
        let request_id = self
            .mls_api
            .submit_join_request(&base64_sd_kbt, meeting_link_name, encrypted_key_package)
            .await
            .map_err(MeetCoreError::from)?;

        {
            let mut state = self.state.lock().await;
            state.guest_pending_join_request_id = Some(request_id.clone());
            if state.mls_group_state != MlsGroupState::Success {
                state.set_mls_group_state(MlsGroupState::WaitingForJoinProposalWelcome);
            }
        }

        Ok(request_id)
    }

    pub async fn is_mls_group_joined(&self) -> bool {
        let state = self.state.lock().await;
        state.mls_group_state == MlsGroupState::Success
    }

    /// Waits for a join-proposal Welcome over the MLS websocket, then joins the group.
    /// Caller must set `MlsGroupState::WaitingForJoinProposalWelcome` before waiting unless
    /// the group is already in `Success`.
    ///
    /// `timeout_secs`: max wait for Welcome; `None` uses [`JOIN_PROPOSAL_TIMEOUT`] (15s).
    #[expect(rustdoc::private_intra_doc_links)]
    pub async fn wait_for_join_proposal_welcome_and_join(
        &self,
        participant_id: &UserId,
        meeting_link_name: &str,
        timeout_secs: Option<u64>,
    ) -> Result<(), MeetCoreError> {
        let meeting_link_name = MeetingLinkName::from(meeting_link_name);
        let join_deadline = Duration::from_secs(timeout_secs.unwrap_or(JOIN_PROPOSAL_TIMEOUT));
        let start_time = instant::now();

        loop {
            let welcome_notify = self.join_proposal_welcome_notify.notified();
            {
                let state = self.state.lock().await;
                if state.mls_group_state == MlsGroupState::Success {
                    break;
                }
                if state.mls_group_state == MlsGroupState::WaitingForJoinProposalWelcome {
                    if let Some(welcome_info) = state.get_welcome_info() {
                        drop(state);
                        self.mls_service
                            .join_group_via_welcome(
                                participant_id,
                                &meeting_link_name,
                                welcome_info,
                            )
                            .await
                            .map_err(|e| {
                                tracing::warn!("Failed to join group with welcome info: {:?}", e);
                                MeetCoreError::RoomJoinFailed {
                                    room_id: meeting_link_name.as_str().to_string(),
                                    reason: "Failed to join group with welcome info".to_string(),
                                }
                            })?;
                        let mut state = self.state.lock().await;
                        state.set_mls_group_state(MlsGroupState::Success);
                        state.set_welcome_info(None);
                        tracing::info!("Join group with welcome info successfully");
                        break;
                    }
                } else if state.mls_group_state == MlsGroupState::Pending {
                    tracing::info!("Waiting room welcome wait cancelled");
                    return Err(MeetCoreError::WaitingRoomJoinCancelled);
                } else {
                    tracing::warn!(
                        "Join proposal state is not valid: {:?}",
                        state.mls_group_state
                    );
                    return Err(MeetCoreError::RoomJoinFailed {
                        room_id: meeting_link_name.as_str().to_string(),
                        reason: "Join proposal state is not valid".to_string(),
                    });
                }
            }

            let elapsed = start_time.elapsed();
            if elapsed >= join_deadline {
                return Err(MeetCoreError::RoomJoinRequestTimeout {
                    room_id: meeting_link_name.as_str().to_string(),
                });
            }
            let remaining = join_deadline.saturating_sub(elapsed);
            if timeout(remaining, welcome_notify).await.is_err() {
                return Err(MeetCoreError::RoomJoinRequestTimeout {
                    room_id: meeting_link_name.as_str().to_string(),
                });
            }
        }

        Ok(())
    }

    pub async fn reject_waiting_room_join_request(
        &self,
        user_identifier: &UserId,
        meeting_link_name: &str,
        request_id: &str,
        participant_uid: &str,
    ) -> Result<(), MeetCoreError> {
        tracing::info!(
            "reject_waiting_room_join_request start meeting_link_name={} request_id={} participant_uid={}",
            meeting_link_name, request_id, participant_uid
        );
        let group_arc = self
            .mls_store
            .read()
            .await
            .find_group(meeting_link_name)
            .map_err(|_| MeetCoreError::InternalError {
                message: format!("MLS group not found for room {meeting_link_name}"),
                details: None,
            })?;

        {
            let mls_group = group_arc.read().await;
            crate::service::utils::ensure_room_admin(&mls_group)?;
        }

        let base64_sd_kbt = self.get_sd_kbt(user_identifier).await?;
        self.mls_api
            .reject_join_request(
                &base64_sd_kbt,
                meeting_link_name,
                request_id,
                participant_uid,
            )
            .await?;

        let removed = {
            let mut state = self.state.lock().await;
            state.pending_waiting_room_join_requests.remove(request_id)
        };

        if removed.is_some() {
            self.spawn_join_request_removed_notification(
                request_id.to_string(),
                participant_uid.to_string(),
            );
        }

        Ok(())
    }

    /// Returns pending join requests to admit. When `request_ids` is `None`, returns all pending.
    pub async fn pending_waiting_room_join_requests_for_admit(
        &self,
        request_ids: Option<Vec<String>>,
    ) -> Vec<PendingWaitingRoomJoinRequest> {
        let state = self.state.lock().await;
        match request_ids {
            Some(ids) => ids
                .into_iter()
                .filter_map(|id| state.pending_waiting_room_join_requests.get(&id).cloned())
                .collect(),
            None => state
                .pending_waiting_room_join_requests
                .values()
                .cloned()
                .collect(),
        }
    }

    /// Host admits one or more waiting-room joiners by building Add proposals, a commit,
    /// groupInfo, ratchet tree, and welcome, then POSTing to `/v1/groupInfo`.
    pub async fn admit_waiting_room_join_requests(
        &self,
        user_identifier: &UserId,
        meeting_link_name: &str,
        key_packages: Vec<mls_types::KeyPackage>,
        request_ids: Vec<String>,
    ) -> Result<Vec<String>, MeetCoreError> {
        tracing::info!(
            "admit_waiting_room_join_requests start meeting_link_name={} admit_count={} request_ids={:?}",
            meeting_link_name,
            key_packages.len(),
            request_ids
        );
        if key_packages.is_empty() {
            return Ok(vec![]);
        }
        if key_packages.len() != request_ids.len() {
            return Err(MeetCoreError::InternalError {
                message: "key_packages and request_ids length mismatch".to_string(),
                details: None,
            });
        }

        let room_id = meeting_link_name;
        let group_arc = self
            .mls_store
            .read()
            .await
            .find_group(room_id)
            .map_err(|_| MeetCoreError::InternalError {
                message: format!("MLS group not found for room {room_id}"),
                details: None,
            })?;

        let mut mls_group = group_arc.write().await;

        crate::service::utils::ensure_room_admin(&mls_group)?;

        let roster = mls_group.all_device_ids().collect::<HashSet<_>>();
        let mut proposal_args: Vec<ProposalArg> = Vec::with_capacity(key_packages.len());
        let mut added_user_identifiers = HashSet::new();
        let mut agent_user_identifiers = HashSet::new();
        let mut resolved_request_ids = Vec::with_capacity(key_packages.len());
        let mut committed_request_ids = Vec::with_capacity(key_packages.len());

        for (key_package, request_id) in key_packages.into_iter().zip(request_ids) {
            let Ok(mut cred) = key_package.credential() else {
                tracing::warn!(
                    request_id = %request_id,
                    "Failed to extract credential from waiting-room key package"
                );
                continue;
            };
            let Ok(device_id) = cred.device_id() else {
                tracing::warn!(
                    request_id = %request_id,
                    "Failed to extract device_id from waiting-room key package"
                );
                continue;
            };
            if roster.contains(&device_id) {
                tracing::info!(
                    device_id = %device_id,
                    request_id = %request_id,
                    "Skipping Add proposal: device already in roster"
                );
                resolved_request_ids.push(request_id);
                continue;
            }
            let owning_identity_id = device_id.owning_identity_id().as_owned();
            if credential_is_agent(&cred) {
                agent_user_identifiers.insert(owning_identity_id.clone());
            }
            added_user_identifiers.insert(owning_identity_id);
            committed_request_ids.push(request_id);
            proposal_args.push(ProposalArg::Add(Box::new(key_package)));
        }

        if proposal_args.is_empty() {
            let mut state = self.state.lock().await;
            for request_id in &resolved_request_ids {
                state.pending_waiting_room_join_requests.remove(request_id);
            }
            return Ok(resolved_request_ids);
        }

        let participant_list: HashSet<_> = mls_group
            .participant_list()?
            .map(|l| l.participants.into_iter().map(|p| p.user).collect())
            .unwrap_or_default();
        let epoch = *mls_group.epoch();

        for user_identifier in added_user_identifiers {
            let identifier = ProtonMeetIdentityProvider::user_identifier(&user_identifier);
            if participant_list.contains(&identifier) {
                continue;
            }
            let is_agent = agent_user_identifiers.contains(&user_identifier);
            let role = if is_agent {
                UserRole::Agent
            } else {
                UserRole::Member
            };
            if is_agent {
                tracing::info!(
                    "Agent entering room: assigning role {:?} to user identifier {:?}",
                    role,
                    user_identifier
                );
            }
            let Some(role_update) = mls_group
                .authorizer()?
                .role_proposal_for_added_user(epoch, identifier, role)?
                .map(|component| ProposalArg::UpdateComponent {
                    id: component.component_id,
                    data: component.data,
                })
            else {
                tracing::error!(
                    "Failed to compute role for admitted user identifier: {:?}",
                    user_identifier
                );
                continue;
            };
            proposal_args.push(role_update);
        }

        proposal_args.push(ProposalArg::PskExternal {
            id: ExternalPskId(room_id.as_bytes().to_vec()),
        });

        let (commit_bundle, ..) = mls_group.new_commit(proposal_args).await?;

        let group_info = commit_bundle
            .group_info
            .ok_or_else(|| anyhow::anyhow!("Expected commit to have a GroupInfo"))?;
        let group_info_message = convert_mls_types_to_spec(&group_info)?;
        let ratchet_tree_option = commit_bundle
            .ratchet_tree
            .ok_or_else(|| anyhow::anyhow!("Expected commit to have a RatchetTree"))?
            .try_into()
            .map_err(|e| anyhow::anyhow!("Failed to convert ratchet tree: {e}"))?;

        let base64_sd_kbt = self.get_sd_kbt(user_identifier).await?;
        let welcome = commit_bundle.welcome.map(TryInto::try_into).transpose()?;
        let commit_info = MlsCommitInfo {
            room_id: room_id.as_bytes().to_vec(),
            welcome_message: welcome,
            commit: convert_mls_types_to_spec(&commit_bundle.commit)?,
        };

        let result = self
            .mls_api
            .update_group_info(
                &base64_sd_kbt,
                &group_info_message,
                &ratchet_tree_option,
                Some(&commit_info),
                None,
            )
            .await;

        match result {
            Ok(_) => {
                mls_group.merge_pending_commit().await?;
                tracing::info!(
                    room_id,
                    admitted_count = committed_request_ids.len(),
                    resolved_count = resolved_request_ids.len(),
                    "Admitted waiting-room joiners"
                );
            }
            Err(e) => {
                mls_group.clear_pending_commit();
                mls_group.clear_pending_proposals();
                mls_group.write_to_storage().await?;
                return Err(e.into());
            }
        }

        drop(mls_group);

        let mut admitted_request_ids = resolved_request_ids;
        admitted_request_ids.extend(committed_request_ids);

        {
            let mut state = self.state.lock().await;
            for request_id in &admitted_request_ids {
                state.pending_waiting_room_join_requests.remove(request_id);
            }
        }

        self.handlers
            .call_mls_group_update_handler(room_id.to_string(), GroupKeyUpdateReason::Join)
            .await;

        Ok(admitted_request_ids)
    }
}
