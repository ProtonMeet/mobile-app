#[cfg(test)]
use std::sync::Arc;
use std::{cmp::Ordering, time::Duration};

#[cfg(test)]
use crate::infra::message_cache::MlsMessageCache;
use crate::{
    domain::user::ports::{ConnectionState, UserService},
    errors::service::ServiceError,
    infra::{
        dto::websocket::ClientAck, message_cache::CachedMessageType, ws_client::WebSocketMessage,
    },
    service::{
        service_state::MlsGroupState,
        user_service::{
            utils::{DELAY_PER_RANK_MS, RANK_GROUP_DELAY_MS, RANK_GROUP_SIZE},
            CommitProcessingOutcome, GroupKeyUpdateReason, MessageWithId,
            ProposalProcessingOutcome, ProposalType, QueuedProposal, Service,
        },
        utils::describe_proposal_kind,
    },
    utils::{instant, sleep},
};
use meet_mls::reexports::meet_policy::UserRole;
use meet_type::{
    fanout::{RTCMessageIn, RTCMessageInContent},
    JoinRoomResponse, WebSocketTextResponse, WebSocketTextResponseCommand,
};
use mls_spec::Parsable;
use mls_trait::types::ReceivedMessage;
use proton_meet_mls::MlsGroupTrait;
use rand::Rng;
#[cfg(test)]
use tokio::sync::Mutex;
use uuid::Uuid;

impl Service {
    pub(super) async fn process_cached_messages(&self, room_id: &str) -> Result<(), anyhow::Error> {
        #[cfg(debug_assertions)]
        tracing::info!("Processing cached messages for room {}", room_id);
        let mut total_processed_epochs = Vec::<u64>::new();
        let max_iterations = 10; // Prevent infinite loops
        let mut iteration = 0;

        loop {
            iteration += 1;
            if iteration > max_iterations {
                tracing::warn!(
                "Max iterations ({}) reached for cached message processing in room {}, stopping",
                max_iterations,
                room_id
            );
                break;
            }

            // Get current epoch once and use it for both filtering and validation
            let current_epoch = self.get_current_epoch(room_id).await?;

            // Get all processable epochs (epochs <= current_epoch) and sort them
            let mut processable_epochs = self
                .message_cache
                .lock()
                .await
                .get_processable_epochs(room_id, current_epoch);
            processable_epochs.sort();

            if processable_epochs.is_empty() {
                tracing::debug!("No more cached epochs to process for room {}", room_id);
                break;
            }

            #[cfg(debug_assertions)]
            tracing::info!(
                "Iteration {}: Processing {} cached epochs for room {} (current epoch: {}): {:?}",
                iteration,
                processable_epochs.len(),
                room_id,
                current_epoch,
                processable_epochs
            );

            // Use swap_remove for O(1) removal (order doesn't matter after selection)
            let epoch_to_process = processable_epochs.swap_remove(0);

            let mut epoch_advanced = false;

            // Epoch revalidation: Check if this epoch is still processable
            // The group epoch might have advanced since we started this iteration.
            // We need a fresh check here because the epoch could have advanced between
            // getting the processable epochs list and selecting this specific epoch.
            let current_group_epoch = self.get_current_epoch(room_id).await?;

            // Skip epochs that are no longer processable due to group advancement
            if epoch_to_process > current_group_epoch {
                tracing::debug!(
                    "Skipping epoch {} for room {} (now greater than current group epoch {})",
                    epoch_to_process,
                    room_id,
                    current_group_epoch
                );
                continue;
            }

            let cached_messages = match self
                .message_cache
                .lock()
                .await
                .get_messages_for_epoch(room_id, epoch_to_process)
            {
                Some(messages) if !messages.is_empty() => messages,
                Some(_) => {
                    tracing::debug!(
                        "No messages found for epoch {} in room {} (empty epoch entry)",
                        epoch_to_process,
                        room_id
                    );
                    continue;
                }
                None => {
                    tracing::debug!(
                        "Epoch {} no longer exists in cache for room {} (may have been cleaned up)",
                        epoch_to_process,
                        room_id
                    );
                    continue;
                }
            };

            tracing::info!(
                "Processing {} cached messages for room {} at epoch {} (group epoch: {})",
                cached_messages.len(),
                room_id,
                epoch_to_process,
                current_group_epoch
            );

            let mut epoch_success = true;
            let mut early_break_due_to_epoch_advance = false;

            for (message_type, cached_message) in cached_messages {
                match message_type {
                    CachedMessageType::Proposal => {
                        match self
                            .process_proposal_message(cached_message.message, room_id)
                            .await
                        {
                            Ok(_) => {}
                            Err(e) => {
                                tracing::warn!(
                                    "Failed to process cached proposal for room {} at epoch {}: {}",
                                    room_id,
                                    epoch_to_process,
                                    e
                                );
                                epoch_success = false;
                                break;
                            }
                        }
                    }
                    CachedMessageType::Commit => {
                        match self
                            .process_commit_message(cached_message.message, room_id)
                            .await
                        {
                            Ok(CommitProcessingOutcome::Applied) => {
                                // Commit processed successfully, epoch may have advanced.
                                epoch_advanced = true;

                                // Revalidate epoch after commit processing
                                let new_group_epoch = self.get_current_epoch(room_id).await?;

                                // If epoch advanced significantly, break to start fresh iteration
                                if new_group_epoch > current_group_epoch {
                                    tracing::info!(
                                            "Group epoch advanced from {} to {} after commit, breaking to revalidate cached messages",
                                            current_group_epoch,
                                            new_group_epoch
                                        );
                                    // Mark that we're breaking early due to epoch advancement, not failure
                                    early_break_due_to_epoch_advance = true;
                                    break;
                                }
                            }
                            Ok(CommitProcessingOutcome::NoStateChange) => {}
                            Ok(CommitProcessingOutcome::DeferredFutureEpoch) => {}
                            Err(e) => {
                                tracing::warn!(
                                    "Failed to process cached commit for room {} at epoch {}: {}",
                                    room_id,
                                    epoch_to_process,
                                    e
                                );
                                epoch_success = false;
                                break;
                            }
                        }
                    }
                }
            }

            // If we broke due to epoch advancement, still consider the epoch successful
            if early_break_due_to_epoch_advance {
                epoch_success = true;
            }

            if epoch_success {
                tracing::info!(
                    "Successfully processed cached messages for room {} at epoch {}",
                    room_id,
                    epoch_to_process
                );

                // Clean up successfully processed epochs
                let mut cache = self.message_cache.lock().await;
                cache.remove_processed_messages(room_id, epoch_to_process);
                #[cfg(debug_assertions)]
                tracing::info!(
                    "Cleaned up processed cached messages for room {} epochs: {:?}",
                    room_id,
                    epoch_to_process
                );
                total_processed_epochs.push(epoch_to_process);

                // continue to the next iteration, so we can process the next epoch until it failed
                if early_break_due_to_epoch_advance {
                    tracing::debug!(
                        "Breaking from epoch processing loop due to epoch advancement for room {}",
                        room_id
                    );
                    continue;
                }
            } else {
                tracing::warn!(
                        "Failed to process some cached messages for room {} at epoch {}, stopping cache processing",
                        room_id,
                        epoch_to_process
                    );
                break;
            }

            // If no epoch advancement occurred, we're done
            if !epoch_advanced {
                tracing::debug!(
                    "No epoch advancement in iteration {}, stopping cache processing for room {}",
                    iteration,
                    room_id
                );
                break;
            }
        }

        if !total_processed_epochs.is_empty() {
            #[cfg(debug_assertions)]
            tracing::info!(
                "Completed cached message processing for room {}: processed {} epochs total in {} iterations: {:?}",
                room_id,
                total_processed_epochs.len(),
                iteration,
                total_processed_epochs
            );
        }

        // Clean up old cached messages to prevent memory leaks
        // Keep messages for up to 10 epochs behind current epoch
        let final_epoch = self.get_current_epoch(room_id).await?;

        // Remove cached messages that are older than current epoch
        self.message_cache
            .lock()
            .await
            .cleanup_old_messages(room_id, final_epoch, 0);

        Ok(())
    }

    pub(super) async fn process_commit_message(
        &self,
        commit_message: mls_types::MlsMessage,
        room_id: &str,
    ) -> Result<CommitProcessingOutcome, anyhow::Error> {
        let epoch_of_commit = commit_message
            .epoch()
            .ok_or(anyhow::anyhow!("Expected commit to have an epoch"))?;

        // Get epoch via MLS store adapter (through the service's port)
        // We need to access it directly from mls_store for now since we need the epoch before processing
        let mls_group_epoch = self.get_current_epoch(room_id).await?;

        tracing::info!(
            "Before processing commit message. epoch: {:?}",
            mls_group_epoch
        );

        match epoch_of_commit.cmp(&mls_group_epoch) {
            Ordering::Less => {
                tracing::info!(
                    "Received commit message with old epoch. commit epoch: {:?}, group epoch: {:?}",
                    epoch_of_commit,
                    mls_group_epoch
                );
                // Old commit is expected during backlog replay; ignore without extra cache churn.
                return Ok(CommitProcessingOutcome::NoStateChange);
            }
            Ordering::Equal => {}
            Ordering::Greater => {
                tracing::info!(
                    "Received commit message with future epoch. epoch: {:?}",
                    epoch_of_commit
                );
                self.cache_commit_message(room_id, commit_message).await?;
                return Ok(CommitProcessingOutcome::DeferredFutureEpoch);
            }
        }

        let room_processing_lock = self.room_processing_lock(room_id).await;
        let _room_processing_guard = room_processing_lock.lock().await;

        let mut queued_proposals: Vec<QueuedProposal> = {
            let mut proposal_lock = self.proposal_queue.lock().await;
            proposal_lock.remove(room_id).unwrap_or_default()
        };

        // Process proposals outside the lock
        // handle the proposals in the queue before we process the commit message
        for queued_proposal in &queued_proposals {
            let result = self
                .handle_proposal(room_id, queued_proposal.proposal_message.clone())
                .await;
            if let Err(e) = result {
                tracing::warn!("Failed to handle proposal in the queue: {:?}", e);
            }
        }

        // handle proposals from message_cache for this epoch
        if let Some(cached_messages) = self
            .message_cache
            .lock()
            .await
            .get_messages_for_epoch(room_id, mls_group_epoch)
        {
            for (message_type, cached_message) in cached_messages {
                if let CachedMessageType::Proposal = message_type {
                    let result = self
                        .handle_proposal(room_id, cached_message.message.clone())
                        .await;
                    if let Err(e) = result {
                        tracing::warn!(
                            "Failed to handle proposal from message_cache for epoch {}: {:?}",
                            mls_group_epoch,
                            e
                        );
                    }
                }
            }
        }

        let store = self.mls_store.read().await;
        let mut mls_group = store
            .group_map
            .get(room_id)
            .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
            .write()
            .await;
        if let Err(e) = Self::validate_psk_proposal(commit_message.clone(), room_id) {
            // PSK validation failed: restore queue and return.
            drop(mls_group);
            self.restore_proposal_queue_on_failure(
                room_id,
                &mut queued_proposals,
                "Failed to process commit message",
            )
            .await;
            return Err(e);
        }

        let result = mls_group.decrypt_message(commit_message.clone()).await;
        let (received_message, _reinit) = match result {
            Ok((received_message, reinit)) => (received_message, reinit),
            Err(e) => {
                tracing::error!("Failed to decrypt commit message: {:?}", e);
                self.restore_proposal_queue_on_failure(
                    room_id,
                    &mut queued_proposals,
                    "Failed to process commit message",
                )
                .await;
                return Err(anyhow::Error::from(e));
            }
        };
        match received_message {
            ReceivedMessage::Commit { ref output, .. } => {
                use crate::service::agent_host_service::agent_psk_id_for_meeting;
                let expected_id = room_id.as_bytes();
                let expected_agent_id = agent_psk_id_for_meeting(room_id);
                let has_psk = output.applied_proposals.iter().any(|p| {
                    matches!(
                        &p.effect,
                        mls_trait::types::ProposalEffect::PskAdded {
                            reference: mls_types::PskReference::External(mls_types::ExternalPskId(id))
                        } if id.as_slice() == expected_id || id.as_slice() == expected_agent_id.as_slice()
                    )
                });
                if !has_psk {
                    tracing::error!("Commit missing required PSK proposal for room {room_id}");
                    drop(mls_group);
                    self.restore_proposal_queue_on_failure(
                        room_id,
                        &mut queued_proposals,
                        "Commit missing PSK proposal",
                    )
                    .await;
                    return Err(anyhow::Error::from(ServiceError::PskProposalMissing));
                }
            }
            ReceivedMessage::Error(mls_types::MlsTypesError::MlsClientError(
                mls_rs::client::MlsError::ProposalNotFound,
            )) => {
                tracing::error!("Proposal not found in commit message");
                self.cache_commit_message(room_id, commit_message).await?;
                self.restore_proposal_queue_on_failure(
                    room_id,
                    &mut queued_proposals,
                    "Failed to process commit message",
                )
                .await;
                return Err(anyhow::Error::from(ServiceError::ProposalNotFound));
            }
            ReceivedMessage::Duplicate => {
                tracing::info!("Received duplicated commit message");
                self.restore_proposal_queue_on_failure(
                    room_id,
                    &mut queued_proposals,
                    "Received duplicated commit message",
                )
                .await;
                return Ok(CommitProcessingOutcome::NoStateChange);
            }
            _ => {
                tracing::error!("Received message is not a commit: {:?}", received_message);
                self.restore_proposal_queue_on_failure(
                    room_id,
                    &mut queued_proposals,
                    "Failed to process commit message",
                )
                .await;
                return Err(anyhow::Error::from(ServiceError::InvalidMlsMessageType));
            }
        }

        let new_epoch = *mls_group.epoch();
        tracing::info!("Commit message processed. epoch: {:?}", new_epoch);

        drop(mls_group);

        let key_update_reason = match &received_message {
            ReceivedMessage::Commit { output, .. } => {
                let has_add = output.applied_proposals.iter().any(|p| {
                    matches!(
                        &p.effect,
                        mls_trait::types::ProposalEffect::Add(_)
                            | mls_trait::types::ProposalEffect::ExternalInit(_)
                            | mls_trait::types::ProposalEffect::SelfExternalInit
                    )
                });
                let has_remove = output.applied_proposals.iter().any(|p| {
                    matches!(
                        &p.effect,
                        mls_trait::types::ProposalEffect::Remove(_)
                            | mls_trait::types::ProposalEffect::SelfRemove(_)
                    )
                });
                match (has_add, has_remove) {
                    (true, true) => GroupKeyUpdateReason::Mixed,
                    (true, false) => GroupKeyUpdateReason::Join,
                    (false, true) => GroupKeyUpdateReason::Leave,
                    _ => GroupKeyUpdateReason::Unknown,
                }
            }
            _ => GroupKeyUpdateReason::Unknown,
        };

        // trigger the group update callback outside of locks to prevent lock inversion
        self.handlers
            .call_mls_group_update_handler(room_id, key_update_reason)
            .await;

        let _unused_proposals = match received_message {
            ReceivedMessage::Commit { output, .. } => output.unused_proposals,
            _ => Vec::new(),
        };

        // Check if epoch advanced (it should have, since we processed a commit)
        // Only check if epoch changed from the original epoch
        if new_epoch > mls_group_epoch {
            // Epoch advanced, check and update host role if needed
            if let Err(e) = self.check_and_update_host_role(room_id).await {
                tracing::warn!(
                    "Failed to check and update host role after epoch change: {:?}",
                    e
                );
                // Don't fail the commit processing if role update fails
            }
        }

        // TODO: handle the unused proposals and recreate if needed

        Ok(CommitProcessingOutcome::Applied)
    }

    // receive proposal message
    // the host client will need to create the commit and broadcast to server
    // the other clients will need to decrypt the proposal to prepare for the comming commit
    pub(super) async fn process_proposal_message(
        &self,
        proposal_message: mls_types::MlsMessage,
        room_id: &str,
    ) -> Result<ProposalProcessingOutcome, anyhow::Error> {
        // self.handle_proposal(&room_id, proposal_message.clone())
        //     .await?;

        let proposal = match proposal_message.clone().as_proposal() {
            Some(p) => {
                let mls_types_proposal: mls_types::Proposal = p.clone().try_into()?;
                mls_types_proposal
            }
            None => return Ok(ProposalProcessingOutcome::NoStateChange),
        };

        let proposal_epoch = proposal_message
            .epoch()
            .ok_or(anyhow::anyhow!("Expected proposal to have an epoch"))?;
        let current_epoch = self.get_current_epoch(room_id).await?;

        match proposal_epoch.cmp(&current_epoch) {
            Ordering::Less => {
                tracing::info!(
                    "Received proposal message with old epoch. proposal epoch: {:?}, group epoch: {:?}",
                    proposal_epoch,
                    current_epoch
                );
                return Ok(ProposalProcessingOutcome::NoStateChange);
            }
            Ordering::Equal => {}
            Ordering::Greater => {
                tracing::info!(
                    "Received proposal message with future epoch. proposal epoch: {:?}, group epoch: {:?}",
                    proposal_epoch,
                    current_epoch
                );
                self.cache_proposal_message(room_id, proposal_message)
                    .await?;
                return Ok(ProposalProcessingOutcome::DeferredFutureEpoch);
            }
        }

        match &proposal {
            mls_types::Proposal::Remove(_)
            | mls_types::Proposal::Add(_)
            | mls_types::Proposal::AppDataUpdate(_) => {
                // add the proposal to the queue
                let proposal_type = match &proposal {
                    mls_types::Proposal::Add(_) => ProposalType::Add,
                    mls_types::Proposal::Remove(_) => ProposalType::Remove,
                    mls_types::Proposal::AppDataUpdate(_) => ProposalType::AppDataUpdate,
                    _ => unreachable!(),
                };
                let queued_proposal = QueuedProposal {
                    proposal_message: proposal_message.clone(),
                    proposal_type,
                };
                {
                    let mut queue = self.proposal_queue.lock().await;
                    queue
                        .entry(room_id.to_string())
                        .or_insert_with(Vec::new)
                        .push(queued_proposal);
                }
            }
            _ => {
                let type_name = match proposal {
                    mls_types::Proposal::Add(_) => "ADD",
                    mls_types::Proposal::Remove(_) => "REMOVE",
                    mls_types::Proposal::Update(_) => "UPDATE",
                    mls_types::Proposal::Psk(_) => "PSK",
                    mls_types::Proposal::ReInit(_) => "RE_INIT",
                    mls_types::Proposal::ExternalInit(_) => "EXTERNAL_INIT",
                    mls_types::Proposal::GroupContextExtensions(_) => "GROUP_CONTEXT_EXTENSIONS",
                    mls_types::Proposal::AppDataUpdate(_) => "APP_DATA_UPDATE",
                    mls_types::Proposal::AppEphemeral(_) => "APP_EPHEMERAL",
                };
                tracing::warn!(
                    "Received proposal is not an expected proposal, it is {} proposal",
                    type_name
                );
            }
        }

        let mls_group_lock = {
            let store_lock = self.mls_store.read().await;
            store_lock
                .group_map
                .get(room_id)
                .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
                .clone()
        };
        let mls_group = mls_group_lock.read().await;

        let self_leaf_index = mls_group.own_leaf_index()?;
        let epoch_at = *mls_group.epoch();
        let authorizer = mls_group.authorizer()?;
        let own_role = authorizer.own_role(epoch_at)?;
        // If the own role is RoomAdmin, the client will be the designated committer
        // otherwise, the client will be the committer with the deterministic random rank
        let deterministic_random_rank = if own_role.role_index == UserRole::RoomAdmin as u32 {
            0
        } else {
            self.get_deterministic_random_rank(
                *self_leaf_index,
                epoch_at,
                mls_group.roster().collect::<Vec<_>>(),
            )
            .await?
        };
        drop(mls_group);

        let rank_group = deterministic_random_rank / RANK_GROUP_SIZE;

        tracing::debug!(
            "deterministic_random_rank: {:?}, rank_group: {:?}",
            deterministic_random_rank,
            rank_group
        );

        // Calculate delay: random component (0-2000ms) + group-based component (0-5000ms per group)
        // Total delay range: 0ms to (20 * 100 + rank_group * 5000)ms
        let random_jitter = rand::thread_rng().gen_range(0..=20);
        let delay_ms = random_jitter * DELAY_PER_RANK_MS + rank_group * RANK_GROUP_DELAY_MS;

        self.clone()
            .start_proposal_timer(room_id.to_string(), delay_ms, epoch_at, rank_group);
        // TODO: Refactor this designated committer selection logic based on proposal type
        // and try to avoid shuffle() for efficiency if needed
        Ok(ProposalProcessingOutcome::Applied)
    }

    pub(super) async fn cache_commit_message(
        &self,
        room_id: &str,
        commit_message: mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error> {
        self.mls_msg_service
            .cache_commit_message(room_id, commit_message)
            .await
    }

    pub(super) async fn cache_proposal_message(
        &self,
        room_id: &str,
        proposal_message: mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error> {
        self.mls_msg_service
            .cache_proposal_message(room_id, proposal_message)
            .await
    }

    pub(super) async fn handle_websocket_message_impl(
        &self,
        message: WebSocketMessage,
    ) -> Result<(), anyhow::Error> {
        const MLS_STATE_CHECK_TIMEOUT: u64 = 3; // seconds

        match message {
            WebSocketMessage::Text(text) => {
                if let Ok(envelope) = serde_json::from_str::<WebSocketTextResponse>(&text) {
                    match envelope.command {
                        WebSocketTextResponseCommand::AgentPending(notification) => {
                            let device_id = notification.device_id;
                            if !self
                                .handlers
                                .call_agent_pending_handler(device_id.clone())
                                .await
                            {
                                tracing::debug!("AgentPending received but no handler registered: device_id={device_id}");
                            }
                            return Ok(());
                        }
                        WebSocketTextResponseCommand::AgentLeft(notification) => {
                            let device_id = notification.device_id;
                            if !self
                                .handlers
                                .call_agent_left_handler(device_id.clone())
                                .await
                            {
                                tracing::debug!("AgentLeft received but no handler registered: device_id={device_id}");
                            }
                            return Ok(());
                        }
                        _ => {}
                    }
                }

                // try to parse as JoinRoomResponse
                if let Ok(join_response) = serde_json::from_str::<JoinRoomResponse>(&text) {
                    #[cfg(debug_assertions)]
                    tracing::info!(
                        "Parsed JoinRoomResponse: success={}, error={:?}",
                        join_response.success,
                        join_response.error
                    );
                    if !join_response.success {
                        if let Some(error) = join_response.error {
                            tracing::error!("Join room failed: {}", error);
                        }
                    } else {
                        {
                            tracing::info!("Join room successful");
                        } // Release state lock before sending message to avoid deadlock
                    }
                    return Ok(());
                }
                // if none of the above, log the original text
                tracing::info!("Received text message from meet-server: {}", text);
            }
            WebSocketMessage::Binary(items) => {
                let mut requires_ack = true;
                let rtc_payload: Option<Vec<u8>>;
                let mut msg_id: Option<Uuid> = None;

                // Try CBOR decoding for wrapped messages
                if let Ok(msg) = ciborium::from_reader::<MessageWithId, _>(&items[..]) {
                    rtc_payload = Some(msg.payload);
                    msg_id = Some(msg.id);
                } else {
                    rtc_payload = Some(items);
                }

                if let Some(payload) = rtc_payload {
                    match RTCMessageIn::from_tls_bytes(&payload) {
                        Ok(rtc_message) => {
                            let msg_id_for_log = msg_id.as_ref().map(|id| id.to_string());
                            match rtc_message.content {
                                RTCMessageInContent::JoinRequest(info) => {
                                    requires_ack = false;
                                    tracing::info!(
                                        ws_msg_id = msg_id_for_log.as_deref().unwrap_or("n/a"),
                                        "Received join request notification"
                                    );
                                    self.handle_join_request(info).await?;
                                }
                                RTCMessageInContent::JoinRequestRemoved(info) => {
                                    requires_ack = false;
                                    tracing::info!(
                                        ws_msg_id = msg_id_for_log.as_deref().unwrap_or("n/a"),
                                        "Received join request removed notification"
                                    );
                                    self.handle_join_request_removed(info).await?;
                                }
                                other => {
                                    // check if the mls group is ready before we process the message
                                    let mls_check_start = instant::now();

                                    let mut check_count = 0;
                                    // Clone Arc outside loop to avoid repeated cloning
                                    loop {
                                        check_count += 1;

                                        // Check connection state first - drop guard immediately after check
                                        let ws_connection_state =
                                            { self.ws_client.get_connection_state().await };

                                        if ws_connection_state == ConnectionState::Disconnected {
                                            tracing::error!("Websocket is disconnected, skipping binary message processing");
                                            return Ok(());
                                        }

                                        // Check MLS group state
                                        let mls_state = {
                                            let state = self.state.lock().await;
                                            state.mls_group_state.clone()
                                        };

                                        if mls_state == MlsGroupState::Success {
                                            if check_count > 1 {
                                                let elapsed = mls_check_start.elapsed();
                                                tracing::info!(
                                                    "MLS group ready after {} checks (elapsed: {:?})",
                                                    check_count,
                                                    elapsed
                                                );
                                            } else {
                                                tracing::debug!("MLS group ready immediately");
                                            }
                                            break;
                                        }

                                        let elapsed = mls_check_start.elapsed();
                                        if elapsed > Duration::from_secs(MLS_STATE_CHECK_TIMEOUT) {
                                            tracing::warn!(
                                                "MLS group not ready after {}s (checked {} times, state: {:?}), skipping binary message processing",
                                                MLS_STATE_CHECK_TIMEOUT,
                                                check_count,
                                                mls_state
                                            );
                                            return Ok(());
                                        }

                                        let state = self.state.lock().await;
                                        if state.mls_group_state == MlsGroupState::Success
                                            || state.mls_group_state
                                                == MlsGroupState::WaitingForJoinProposalWelcome
                                        {
                                            break;
                                        }

                                        // Use shorter sleep interval for faster response (100ms instead of 1s)
                                        sleep(std::time::Duration::from_millis(100)).await;
                                    }

                                    match other {
                                        RTCMessageInContent::Welcome(mls_welcome_info) => {
                                            tracing::info!(
                                                ws_msg_id =
                                                    msg_id_for_log.as_deref().unwrap_or("n/a"),
                                                "Received welcome message"
                                            );
                                            let mut state = self.state.lock().await;
                                            // save the welcome info to the state
                                            state.set_welcome_info(Some(mls_welcome_info));
                                            drop(state);
                                            self.join_proposal_welcome_notify.notify_waiters();
                                        }
                                        RTCMessageInContent::CommitUpdate(mls_commit_info) => {
                                            let room_id_str =
                                                String::from_utf8_lossy(&mls_commit_info.room_id);
                                            let commit_message = mls_types::MlsMessage::try_from(
                                                mls_commit_info.commit.clone(),
                                            )
                                            .map_err(|e| {
                                                tracing::error!(
                                                    ws_msg_id = msg_id_for_log
                                                        .as_deref()
                                                        .unwrap_or("n/a"),
                                                    room_id = %room_id_str,
                                                    error = %e,
                                                    "Failed to parse commit message"
                                                );
                                                e
                                            })?;
                                            let room_id =
                                                String::from_utf8(mls_commit_info.room_id.clone())
                                                    .map_err(|e| {
                                                        tracing::error!(
                                                            ws_msg_id = msg_id_for_log
                                                                .as_deref()
                                                                .unwrap_or("n/a"),
                                                            error = %e,
                                                            "Failed to parse room_id as UTF-8"
                                                        );
                                                        e
                                                    })?;
                                            let epoch = commit_message.epoch();
                                            let has_welcome =
                                                mls_commit_info.welcome_message.is_some();
                                            tracing::info!(
                                                ws_msg_id = msg_id_for_log
                                                    .as_deref()
                                                    .unwrap_or("n/a"),
                                                room_id = %room_id,
                                                commit_epoch = ?epoch,
                                                has_welcome = has_welcome,
                                                "Received commit update"
                                            );
                                            let mut should_process_cached_messages = false;
                                            match self
                                                .process_commit_message(commit_message, &room_id)
                                                .await
                                            {
                                                Ok(CommitProcessingOutcome::Applied) => {
                                                    should_process_cached_messages = true;
                                                }
                                                Ok(CommitProcessingOutcome::NoStateChange) => {
                                                    tracing::debug!(
                                                "Commit did not change state for room {}, skipping cached message processing",
                                                room_id
                                            );
                                                }
                                                Ok(
                                                    CommitProcessingOutcome::DeferredFutureEpoch,
                                                ) => {
                                                    tracing::debug!(
                                                "Commit deferred for future epoch in room {}, skipping cached message processing",
                                                room_id
                                            );
                                                }
                                                Err(e) => {
                                                    if let Some(ServiceError::ProposalNotFound) =
                                                        e.downcast_ref::<ServiceError>()
                                                    {
                                                        let commit_message =
                                                            mls_types::MlsMessage::try_from(
                                                                mls_commit_info.commit.clone(),
                                                            )?;
                                                        let _ = self
                                                            .cache_commit_message(
                                                                &room_id,
                                                                commit_message,
                                                            )
                                                            .await;
                                                        tracing::info!(
                                                    "Cached commit message for later processing"
                                                );
                                                    } else if let Some(
                                                        ServiceError::PskProposalMissing,
                                                    ) = e.downcast_ref::<ServiceError>()
                                                    {
                                                        tracing::error!(
                                                    "Commit rejected: PSK proposal missing or has wrong ID for room {}",
                                                    room_id
                                                );
                                                        return Err(e);
                                                    } else {
                                                        tracing::warn!(
                                                    "Failed to process commit message for room {}: {}",
                                                    room_id,
                                                    e
                                                );
                                                    }
                                                }
                                            }

                                            if should_process_cached_messages {
                                                // Process cached messages only after we actually advanced/applied commit state.
                                                match self.process_cached_messages(&room_id).await {
                                            Ok(_) => tracing::debug!(
                                                "Cached messages processed successfully for room {}",
                                                room_id
                                            ),
                                            Err(e) => tracing::warn!(
                                                "Failed to process cached messages for room {}: {:?}",
                                                room_id,
                                                e
                                            ),
                                        }
                                            }
                                        }
                                        RTCMessageInContent::Proposal(proposal_info) => {
                                            let room_id_str =
                                                String::from_utf8_lossy(&proposal_info.room_id);
                                            let proposal_message = mls_types::MlsMessage::try_from(
                                                proposal_info.proposal.clone(),
                                            )
                                            .map_err(|e| {
                                                tracing::error!(
                                                    ws_msg_id = msg_id_for_log
                                                        .as_deref()
                                                        .unwrap_or("n/a"),
                                                    room_id = %room_id_str,
                                                    error = %e,
                                                    "Failed to parse proposal message"
                                                );
                                                e
                                            })?;
                                            let room_id =
                                                String::from_utf8(proposal_info.room_id.clone())
                                                    .map_err(|e| {
                                                        tracing::error!(
                                                            ws_msg_id = msg_id_for_log
                                                                .as_deref()
                                                                .unwrap_or("n/a"),
                                                            error = %e,
                                                            "Failed to parse room_id as UTF-8"
                                                        );
                                                        e
                                                    })?;
                                            let proposal_epoch = proposal_message.epoch();
                                            let proposal_type =
                                                describe_proposal_kind(&proposal_message)
                                                    .unwrap_or("UNKNOWN");
                                            tracing::info!(
                                                ws_msg_id = msg_id_for_log
                                                    .as_deref()
                                                    .unwrap_or("n/a"),
                                                room_id = %room_id,
                                                proposal_epoch = ?proposal_epoch,
                                                proposal_type = proposal_type,
                                                "Received proposal message"
                                            );
                                            let mut should_process_cached_messages = false;
                                            match self
                                                .process_proposal_message(
                                                    proposal_message,
                                                    &room_id,
                                                )
                                                .await
                                            {
                                                Ok(ProposalProcessingOutcome::Applied) => {
                                                    should_process_cached_messages = true;
                                                }
                                                Ok(ProposalProcessingOutcome::NoStateChange) => {
                                                    tracing::debug!(
                                                "Proposal did not change state for room {}, skipping cached message processing",
                                                room_id
                                            );
                                                }
                                                Ok(
                                                    ProposalProcessingOutcome::DeferredFutureEpoch,
                                                ) => {
                                                    tracing::debug!(
                                                "Proposal deferred for future epoch in room {}, skipping cached message processing",
                                                room_id
                                            );
                                                }
                                                Err(e) => {
                                                    tracing::warn!(
                                                        "Failed to process proposal message: {}",
                                                        e
                                                    );
                                                    let proposal_message =
                                                        mls_types::MlsMessage::try_from(
                                                            proposal_info.proposal.clone(),
                                                        )?;
                                                    let _ = self
                                                        .cache_proposal_message(
                                                            &room_id,
                                                            proposal_message,
                                                        )
                                                        .await;
                                                    tracing::info!(
                                                "Cached proposal message for later processing"
                                            );
                                                }
                                            }

                                            if should_process_cached_messages {
                                                // Process cached messages only after proposal was accepted into current epoch state.
                                                match self.process_cached_messages(&room_id).await {
                                            Ok(_) => tracing::debug!(
                                                "Cached messages processed successfully for room {}",
                                                room_id
                                            ),
                                            Err(e) => tracing::warn!(
                                                "WS-MSG: Failed to process cached messages for room {}: {:?}",
                                                room_id,
                                                e
                                            ),
                                        }
                                            }
                                        }

                                        RTCMessageInContent::LiveKitAdminChange(
                                            livekit_admin_change_info,
                                        ) => {
                                            let room_id = String::from_utf8(
                                                livekit_admin_change_info.room_id.clone(),
                                            )?;
                                            let participant_uid = String::from_utf8(
                                                livekit_admin_change_info.participant_uid.clone(),
                                            )?;
                                            let participant_type =
                                                livekit_admin_change_info.participant_type;
                                            tracing::info!(
                                                ws_msg_id = msg_id_for_log
                                                    .as_deref()
                                                    .unwrap_or("n/a"),
                                                room_id = %room_id,
                                                participant_uid = %participant_uid,
                                                participant_type = participant_type,
                                                "Received livekit admin change"
                                            );
                                            self.handle_livekit_admin_change(
                                                &room_id,
                                                participant_uid,
                                                participant_type,
                                            )
                                            .await?;
                                        }
                                        RTCMessageInContent::RemoveLeafNode(
                                            _mls_remove_leaf_node_info,
                                        ) => {
                                            tracing::debug!(
                                                "Received RemoveLeafNode message (not being used)"
                                            );
                                        }
                                        RTCMessageInContent::SendCommit(_mls_commit_info) => {
                                            tracing::debug!(
                                                "Received SendCommit message (not being used)"
                                            );
                                        }
                                        RTCMessageInContent::SendProposalAndCommit(
                                            _mls_proposal_and_commit_info,
                                        ) => {
                                            tracing::debug!(
                                        "Received SendProposalAndCommit message (not being used)"
                                    );
                                        }
                                        RTCMessageInContent::JoinDecision(join_decision_info) => {
                                            requires_ack = false;
                                            tracing::info!(
                                                ws_msg_id =
                                                    msg_id_for_log.as_deref().unwrap_or("n/a"),
                                                "Received join decision notification"
                                            );
                                            self.handle_join_decision(join_decision_info).await?;
                                        }
                                        RTCMessageInContent::JoinRequest(_)
                                        | RTCMessageInContent::JoinRequestRemoved(_) => {
                                            unreachable!("join request frames are handled before MLS processing")
                                        }
                                        RTCMessageInContent::AgentBundle(
                                            _mls_agent_bundle_info,
                                        ) => {
                                            todo!()
                                        }
                                    }
                                }
                                RTCMessageInContent::JoinRequest(_) => {
                                    tracing::debug!(
                                        "Received JoinRequest message (not being used)"
                                    );
                                }
                                RTCMessageInContent::JoinDecision(_) => {
                                    tracing::debug!(
                                        "Received JoinDecision message (not being used)"
                                    );
                                }
                                RTCMessageInContent::JoinRequestRemoved(_) => {
                                    tracing::debug!(
                                        "Received JoinRequestRemoved message (not being used)"
                                    );
                                }
                                RTCMessageInContent::AgentBundle(_) => {
                                    tracing::debug!(
                                        "Received AgentBundle message (not being used)"
                                    );
                                }
                            }
                        }
                        Err(e) => {
                            tracing::error!("Failed to parse RTC message from payload: {:?}", e);
                        }
                    }
                } else {
                    tracing::warn!("No payload extracted from binary message");
                }

                if requires_ack {
                    if let Some(message_id) = msg_id {
                        // Encode UUID back to CBOR for ack
                        let mut ack_bytes = Vec::new();
                        ciborium::into_writer(
                            &ClientAck {
                                msg_type: "ack".to_string(),
                                id: message_id,
                            },
                            &mut ack_bytes,
                        )?;
                        self.ws_client
                            .send_message(WebSocketMessage::Binary(ack_bytes))
                            .await?;
                        #[cfg(debug_assertions)]
                        tracing::info!("Ack sent for message ID: {:?}", message_id);
                    }
                }

                #[cfg(debug_assertions)]
                tracing::info!("Binary message processing completed successfully");
            }
            WebSocketMessage::Close(reason) => {
                tracing::info!("Received close message: {:?}", reason);
            }
        }

        Ok(())
    }
}

#[cfg(not(target_family = "wasm"))]
#[cfg(test)]
impl Service {
    pub async fn get_cached_message(&self) -> Result<Arc<Mutex<MlsMessageCache>>, anyhow::Error> {
        Ok(self.message_cache.clone())
    }
}
