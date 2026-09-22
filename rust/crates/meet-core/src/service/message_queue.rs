use std::{
    cmp::Ordering,
    collections::HashSet,
    mem,
    str::FromStr,
    sync::{Arc, Weak},
    time::Duration,
};

use meet_identifiers::{AsOwned, DeviceId, Epoch, UserId};
use meet_type::fanout::{MlsCommitInfo, MlsProposalInfo};
use mls_rs::{
    framing::{Content, MlsMessagePayload},
    group::proposal::{Proposal, ProposalOrRef},
};
use mls_spec::messages::{ContentTypeInner, MlsMessageContent};
use mls_trait::{
    meet_policy::UserRole, types::ReceivedMessage, AuthorizerExt, MlsGroup, MlsGroupTrait,
    ProposalArg, ProtonMeetIdentityProvider,
};
use mls_types::MlsTypesError;
use proton_meet_mls::kv::MemKv;

use crate::{
    domain::{
        mls::ports::MessageCachePort,
        user::{
            models::UserTokenInfo,
            ports::{MlsApi, UserService},
        },
    },
    errors::service::ServiceError,
    infra::{message_cache::CachedMessageType, mimi_subject_parser::MimiSubject},
    service::{
        compute_stagger_time,
        service_state::MlsGroupState,
        services_bundle::ServiceBundle,
        user_service::{
            credential_is_agent, psk_id_for_commit, utils::group_has_agent, GroupKeyUpdateReason,
            ProposalType, QueuedProposal,
        },
        utils::convert_mls_types_to_spec,
        StaggerStats, RANK_GROUP_DELAY_MS,
    },
    utils::{
        sleep, spawn_detached,
        sync::{AsyncMutex, SyncRwLock},
    },
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CommitProcessingOutcome {
    Applied,
    DeferredFutureEpoch,
    NoStateChange,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ProposalProcessingOutcome {
    Applied,
    DeferredFutureEpoch,
    NoStateChange,
}

pub(crate) struct MessageQueue {
    room_id: String,
    group: Arc<tokio::sync::RwLock<MlsGroup<MemKv>>>,
    queue: SyncRwLock<Vec<QueuedProposal>>,
    msg_cache: Arc<dyn MessageCachePort>,
    // Separate processing guard, such that queue processing can be serialized without preventing
    // incoming proposals to be pushed (for later processing).
    processing_lock: AsyncMutex<()>,
    timer: SyncRwLock<Option<Epoch>>,
    services: Weak<ServiceBundle>,
    mls_api: Arc<dyn MlsApi>,
}

impl MessageQueue {
    pub fn new(
        room_id: String,
        group: Arc<tokio::sync::RwLock<MlsGroup<MemKv>>>,
        msg_cache: Arc<dyn MessageCachePort>,
        services: Weak<ServiceBundle>,
        mls_api: Arc<dyn MlsApi>,
    ) -> Self {
        Self {
            room_id,
            group,
            queue: SyncRwLock::new(Vec::new(), |_| {}),
            msg_cache,
            processing_lock: Default::default(),
            timer: SyncRwLock::new(None, |v| *v = None),
            services,
            mls_api,
        }
    }

    fn services(&self) -> Result<Arc<ServiceBundle>, anyhow::Error> {
        self.services
            .upgrade()
            .ok_or_else(|| anyhow::anyhow!("Could not upgrade service bundle"))
    }

    pub async fn push_proposal(
        self: &Arc<Self>,
        proposal: mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error> {
        self.handle_proposal(proposal).await
    }

    pub async fn push_commit(
        self: &Arc<Self>,
        commit: mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error> {
        match self.process_commit_message(commit).await {
            Ok(CommitProcessingOutcome::Applied) => {
                // Process cached messages only after we actually advanced/applied commit state.
                match self.process_cached_messages().await {
                    Ok(_) => tracing::debug!(
                        "Cached messages processed successfully for room {}",
                        self.room_id
                    ),
                    Err(e) => tracing::warn!(
                        "Failed to process cached messages for room {}: {e:?}",
                        self.room_id,
                    ),
                }
            }
            Ok(CommitProcessingOutcome::NoStateChange) => {
                tracing::debug!(
                    "Commit did not change state for room {}, skipping cached message processing",
                    self.room_id
                );
            }
            Ok(CommitProcessingOutcome::DeferredFutureEpoch) => {
                tracing::debug!("Commit deferred for future epoch in room {}, skipping cached message processing", self.room_id);
            }

            Err(e) => {
                if let Some(ServiceError::PskProposalMissing) = e.downcast_ref::<ServiceError>() {
                    tracing::error!(
                        "Commit rejected: PSK proposal missing or has wrong ID for room {}",
                        self.room_id
                    );
                    return Err(e);
                } else {
                    tracing::warn!(
                        "Failed to process commit message for room {}: {e}",
                        self.room_id,
                    );
                }
            }
        }

        Ok(())
    }

    async fn process_commit_message(
        self: &Arc<Self>,
        commit: mls_types::MlsMessage,
    ) -> Result<CommitProcessingOutcome, anyhow::Error> {
        let group_epoch = self.epoch().await;
        let commit_epoch = commit
            .epoch()
            .ok_or(anyhow::anyhow!("Expected commit to have an epoch"))?;

        tracing::info!("Before processing commit message. epoch: {group_epoch:?}");

        match commit_epoch.cmp(&group_epoch) {
            Ordering::Less => {
                tracing::info!(
                    "Received commit message with old epoch. commit epoch: {commit_epoch:?}, group epoch: {group_epoch:?}",
                );
                // Old commit is expected during backlog replay; ignore without extra cache churn.
                return Ok(CommitProcessingOutcome::NoStateChange);
            }
            Ordering::Equal => {}
            Ordering::Greater => {
                tracing::info!(
                    "Received commit message with future epoch. epoch: {commit_epoch:?}"
                );
                self.cache_commit_message(commit).await?;
                return Ok(CommitProcessingOutcome::DeferredFutureEpoch);
            }
        }

        let room_processing_guard = self.processing_lock.lock_send().await;
        let queued_proposals: Vec<QueuedProposal> = mem::take(&mut self.queue.write());

        // Process proposals outside the lock
        // handle the proposals in the queue before we process the commit message
        for queued_proposal in &queued_proposals {
            let result = self
                .handle_proposal(queued_proposal.proposal_message.clone())
                .await;
            if let Err(e) = result {
                tracing::warn!("Failed to handle proposal in the queue: {:?}", e);
            }
        }

        self.process_cached_proposals(group_epoch).await?;

        if let Err(e) = self.validate_psk_proposal(&commit) {
            // PSK validation failed: restore queue and return.
            self.restore_proposal_queue_on_failure(
                queued_proposals,
                "Failed to process commit message",
            );
            return Err(e);
        }

        let mut mls_group = self.group.write().await;
        let result = mls_group.decrypt_message(commit.clone()).await;
        let received_message = match result {
            Ok((v, _)) => v,
            Err(e) => {
                tracing::error!("Failed to decrypt commit message: {:?}", e);
                self.restore_proposal_queue_on_failure(
                    queued_proposals,
                    "Failed to process commit message",
                );
                return Err(e.into());
            }
        };

        let res = match received_message {
            ReceivedMessage::Commit { ref output, .. } => {
                use crate::service::agent_host_service::agent_psk_id_for_meeting;
                let expected_id = self.room_id.as_bytes();
                let expected_agent_id = agent_psk_id_for_meeting(&self.room_id);
                let has_psk = output.applied_proposals.iter().any(|p| {
                    matches!(
                        &p.effect,
                        mls_trait::types::ProposalEffect::PskAdded {
                            reference: mls_types::PskReference::External(mls_types::ExternalPskId(id))
                        } if id.as_slice() == expected_id || id.as_slice() == expected_agent_id.as_slice()
                    )
                });
                if !has_psk {
                    tracing::error!(
                        "Commit missing required PSK proposal for room {}",
                        self.room_id
                    );
                    Some((
                        Err(anyhow::Error::from(ServiceError::PskProposalMissing)),
                        "Commit missing PSK proposal",
                    ))
                } else {
                    None
                }
            }
            ReceivedMessage::Error(mls_types::MlsTypesError::MlsClientError(
                mls_rs::client::MlsError::ProposalNotFound,
            )) => {
                tracing::error!("Proposal not found in commit message");
                self.cache_commit_message(commit).await?;
                Some((
                    Err(anyhow::Error::from(ServiceError::ProposalNotFound)),
                    "Failed to process commit message",
                ))
            }
            ReceivedMessage::Duplicate => {
                tracing::info!("Received duplicated commit message");
                Some((
                    Ok(CommitProcessingOutcome::NoStateChange),
                    "Received duplicated commit message",
                ))
            }
            _ => {
                tracing::error!("Received message is not a commit: {:?}", received_message);
                Some((
                    Err(anyhow::Error::from(ServiceError::InvalidMlsMessageType)),
                    "Failed to process commit message",
                ))
            }
        };

        if let Some((res, ctx)) = res {
            self.restore_proposal_queue_on_failure(queued_proposals, ctx);
            return res;
        }

        let new_epoch = mls_group.epoch();
        tracing::info!("Commit message processed. epoch: {:?}", new_epoch);

        drop(mls_group);
        drop(room_processing_guard);

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
                GroupKeyUpdateReason::from_applied_proposals(has_add, has_remove)
            }
            _ => GroupKeyUpdateReason::Unknown,
        };

        self.handle_group_update(group_epoch, new_epoch, key_update_reason)
            .await?;

        let _unused_proposals = match received_message {
            ReceivedMessage::Commit { output, .. } => output.unused_proposals,
            _ => Vec::new(),
        };

        // TODO: handle the unused proposals and recreate if needed

        Ok(CommitProcessingOutcome::Applied)
    }

    pub(super) async fn process_cached_messages(self: &Arc<Self>) -> Result<(), anyhow::Error> {
        #[cfg(debug_assertions)]
        tracing::info!("Processing cached messages for room {}", self.room_id);
        let mut total_processed_epochs = Vec::<u64>::new();
        let max_iterations = 10; // Prevent infinite loops
        let mut iteration = 0;

        loop {
            iteration += 1;
            if iteration > max_iterations {
                tracing::warn!(
                "Max iterations ({max_iterations}) reached for cached message processing in room {}, stopping",
                self.room_id
            );
                break;
            }

            // Get current epoch once and use it for both filtering and validation
            let current_epoch = self.epoch().await;

            // Get all processable epochs (epochs <= current_epoch) and sort them
            let processable_epochs = self
                .msg_cache
                .get_processable_epochs(&self.room_id, *current_epoch)
                .await;

            let Some(epoch_to_process) = processable_epochs.iter().min().copied() else {
                tracing::debug!("No more cached epochs to process for room {}", self.room_id);
                break;
            };

            #[cfg(debug_assertions)]
            tracing::info!(
                "Iteration {iteration}: Processing {} cached epochs for room {} (current epoch: {current_epoch}): {processable_epochs:?}",
                processable_epochs.len(),
                self.room_id,
            );

            let mut epoch_advanced = false;

            // Epoch revalidation: Check if this epoch is still processable
            // The group epoch might have advanced since we started this iteration.
            // We need a fresh check here because the epoch could have advanced between
            // getting the processable epochs list and selecting this specific epoch.
            let current_group_epoch = self.epoch().await;

            // Skip epochs that are no longer processable due to group advancement
            if epoch_to_process > *current_group_epoch {
                tracing::debug!(
                    "Skipping epoch {epoch_to_process} for room {} (now greater than current group epoch {current_group_epoch})",
                    self.room_id,
                );
                continue;
            }

            let cached_messages = match self
                .msg_cache
                .get_cached_messages(&self.room_id, epoch_to_process)
                .await?
            {
                Some(messages) if !messages.is_empty() => messages,
                Some(_) => {
                    tracing::debug!(
                        "No messages found for epoch {epoch_to_process} in room {} (empty epoch entry)",
                        self.room_id
                    );
                    continue;
                }
                None => {
                    tracing::debug!(
                        "Epoch {} no longer exists in cache for room {epoch_to_process} (may have been cleaned up)",
                        self.room_id
                    );
                    continue;
                }
            };

            tracing::info!(
                "Processing {} cached messages for room {} at epoch {epoch_to_process} (group epoch: {current_group_epoch})",
                cached_messages.len(),
                self.room_id,
            );

            let mut epoch_success = true;
            let mut early_break_due_to_epoch_advance = false;

            for (message_type, cached_message) in cached_messages {
                match message_type {
                    CachedMessageType::Proposal => {
                        match self.process_proposal_message(cached_message.message).await {
                            Ok(_) => {}
                            Err(e) => {
                                tracing::warn!(
                                    "Failed to process cached proposal for room {} at epoch {}: {}",
                                    self.room_id,
                                    epoch_to_process,
                                    e
                                );
                                epoch_success = false;
                                break;
                            }
                        }
                    }
                    CachedMessageType::Commit => {
                        match self.process_commit_message(cached_message.message).await {
                            Ok(CommitProcessingOutcome::Applied) => {
                                // Commit processed successfully, epoch may have advanced.
                                epoch_advanced = true;

                                // Revalidate epoch after commit processing
                                let new_group_epoch = self.epoch().await;

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
                                    "Failed to process cached commit for room {} at epoch {epoch_to_process}: {e}",
                                    self.room_id
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
                    self.room_id,
                    epoch_to_process
                );

                // Clean up successfully processed epochs
                self.msg_cache
                    .remove_processed_messages(&self.room_id, epoch_to_process)
                    .await;
                #[cfg(debug_assertions)]
                tracing::info!(
                    "Cleaned up processed cached messages for room {} epochs: {:?}",
                    self.room_id,
                    epoch_to_process
                );
                total_processed_epochs.push(epoch_to_process);

                // continue to the next iteration, so we can process the next epoch until it failed
                if early_break_due_to_epoch_advance {
                    tracing::debug!(
                        "Breaking from epoch processing loop due to epoch advancement for room {}",
                        self.room_id
                    );
                    continue;
                }
            } else {
                tracing::warn!(
                        "Failed to process some cached messages for room {} at epoch {}, stopping cache processing",
                        self.room_id,
                        epoch_to_process
                    );
                break;
            }

            // If no epoch advancement occurred, we're done
            if !epoch_advanced {
                tracing::debug!(
                    "No epoch advancement in iteration {}, stopping cache processing for room {}",
                    iteration,
                    self.room_id
                );
                break;
            }
        }

        if !total_processed_epochs.is_empty() {
            #[cfg(debug_assertions)]
            tracing::info!(
                "Completed cached message processing for room {}: processed {} epochs total in {} iterations: {:?}",
                self.room_id,
                total_processed_epochs.len(),
                iteration,
                total_processed_epochs
            );
        }

        // Clean up old cached messages to prevent memory leaks
        // Keep messages for up to 10 epochs behind current epoch
        let final_epoch = self.epoch().await;

        // Remove cached messages that are older than current epoch
        self.msg_cache
            .cleanup_old_messages(&self.room_id, *final_epoch, 0)
            .await;

        Ok(())
    }

    async fn process_cached_proposals(
        self: &Arc<Self>,
        group_epoch: Epoch,
    ) -> Result<(), anyhow::Error> {
        // handle proposals from msg_cache for this epoch
        if let Some(cached_messages) = self
            .msg_cache
            .get_cached_messages(&self.room_id, *group_epoch)
            .await?
        {
            for message in cached_messages
                .into_iter()
                .filter_map(|(ty, msg)| matches!(ty, CachedMessageType::Proposal).then_some(msg))
            {
                let result: Result<_, _> = self.handle_proposal(message.message).await;
                if let Err(e) = result {
                    tracing::warn!(
                        "Failed to handle proposal from msg_cache for epoch {group_epoch}: {e:?}"
                    );
                }
            }
        }

        Ok(())
    }

    async fn cache_commit_message(
        self: &Arc<Self>,
        commit: mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error> {
        Ok(self
            .msg_cache
            .cache_message(
                &self.room_id,
                commit.epoch().ok_or(ServiceError::NoEpochCommit)?,
                CachedMessageType::Commit,
                commit,
            )
            .await?)
    }
    async fn cache_proposal_message(
        self: &Arc<Self>,
        proposal: mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error> {
        Ok(self
            .msg_cache
            .cache_message(
                &self.room_id,
                proposal.epoch().ok_or(ServiceError::NoEpochProposal)?,
                CachedMessageType::Proposal,
                proposal,
            )
            .await?)
    }

    fn restore_proposal_queue_on_failure(
        self: &Arc<Self>,
        queued_proposals: Vec<QueuedProposal>,
        error_context: &str,
    ) {
        if !queued_proposals.is_empty() {
            let items_count = queued_proposals.len();
            tracing::warn!(
                "{}: restoring {} items to queue for room {}",
                error_context,
                items_count,
                self.room_id
            );
            self.queue.write().extend(queued_proposals.into_iter());
        }
    }

    async fn epoch(&self) -> Epoch {
        self.group.read().await.epoch()
    }

    fn validate_psk_proposal(
        self: &Arc<Self>,
        message: &mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error> {
        use crate::service::agent_host_service::agent_psk_id_for_meeting;
        let expected_agent_id = agent_psk_id_for_meeting(&self.room_id);
        if let MlsMessagePayload::Plain(public_message) = &message.mls_message.payload {
            if let Content::Commit(commit) = &public_message.content.content {
                let proposals = &commit.proposals;
                let mut has_psk = false;
                for proposal in proposals {
                    if let ProposalOrRef::Proposal(proposal) = proposal {
                        if let Proposal::Psk(psk) = proposal.as_ref() {
                            if let Some(psk_id) = psk.external_psk_id() {
                                has_psk = true;
                                let id_bytes = psk_id.to_vec();
                                if id_bytes != self.room_id.as_bytes()
                                    && id_bytes.as_slice() != expected_agent_id.as_slice()
                                {
                                    tracing::error!("PSK ID mismatch for room {}", self.room_id);
                                    return Err(anyhow::Error::from(
                                        ServiceError::PskProposalMissing,
                                    ));
                                }
                            }
                        }
                    }
                }
                if !has_psk {
                    tracing::error!("PSK proposal missing for room {}", self.room_id);
                    return Err(anyhow::Error::from(ServiceError::PskProposalMissing));
                }
            }
        }
        Ok(())
    }

    async fn process_proposal_message(
        self: &Arc<Self>,
        message: mls_types::MlsMessage,
    ) -> Result<ProposalProcessingOutcome, anyhow::Error> {
        // self.handle_proposal(&room_id, proposal_message.clone())
        //     .await?;

        let proposal = match message.clone().as_proposal() {
            Some(p) => {
                let mls_types_proposal: mls_types::Proposal = p.clone().try_into()?;
                mls_types_proposal
            }
            None => return Ok(ProposalProcessingOutcome::NoStateChange),
        };

        let proposal_epoch = message
            .epoch()
            .ok_or(anyhow::anyhow!("Expected proposal to have an epoch"))?;
        let current_epoch = self.epoch().await;

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
                self.cache_proposal_message(message).await?;
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
                    proposal_message: message.clone(),
                    proposal_type,
                };

                self.queue.write().push(queued_proposal);
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

        let (epoch_at, rank) = self
            .services()?
            .user_service
            .read()
            .await
            .committer_rank(&*self.group.read().await)
            .await?;
        let StaggerStats {
            delay_ms,
            rank_group,
        } = compute_stagger_time(rank, RANK_GROUP_DELAY_MS);

        self.start_proposal_timer(delay_ms, epoch_at.into(), rank_group);
        // TODO: Refactor this designated committer selection logic based on proposal type
        // and try to avoid shuffle() for efficiency if needed
        Ok(ProposalProcessingOutcome::Applied)
    }

    fn start_proposal_timer(
        self: &Arc<Self>,
        delay_ms: Duration,
        epoch_at: Epoch,
        mls_rank_group: u64,
    ) {
        const BASE_PROPOSAL_DELAY_MS: u64 = 2000; // execute propsoal every 2s
        let delay_ms = delay_ms + Duration::from_millis(BASE_PROPOSAL_DELAY_MS);
        let queue = self.clone();

        spawn_detached(async move {
            // Check if there's already a timer for this room_id and epoch_at
            {
                let mut timer = queue.timer.write();
                if let Some(existing_epoch_at) = &*timer {
                    if *existing_epoch_at >= epoch_at {
                        tracing::debug!(
                            "Proposal timer for room {} with epoch {} already exists, skipping",
                            queue.room_id,
                            epoch_at
                        );
                        return;
                    }
                }
                // Register the timer
                *timer = Some(epoch_at);
            }
            tracing::debug!(
                "Proposal timer for room {}: starting timer with delay {}ms for epoch {}",
                queue.room_id,
                delay_ms.as_millis(),
                epoch_at
            );

            // Wait for the timer to complete
            sleep(delay_ms).await;

            tracing::debug!(
                "Proposal timer for room {}: timer completed, processing proposals for epoch {}",
                queue.room_id,
                epoch_at
            );

            // Remove timer when it completes
            {
                let mut timer = queue.timer.write();
                // Only remove if it's still the same epoch_at (in case epoch changed)
                if let Some(stored_epoch_at) = &*timer {
                    if *stored_epoch_at == epoch_at {
                        *timer = None
                    }
                }
            }

            let Ok(services) = queue.services() else {
                tracing::warn!("Proposal timer exited early due to missing ServiceBundle");
                return;
            };
            let mls_state_ok = services
                .user_service
                .read()
                .await
                .state
                .lock()
                .await
                .mls_group_state
                == MlsGroupState::Success;

            if !mls_state_ok {
                tracing::debug!(
                    "Proposal timer for room {}: mls group state is not Success, skipping",
                    queue.room_id
                );
                return;
            }

            // Check if epoch has changed, skip if not equal
            let current_epoch = queue.epoch().await;
            if current_epoch != epoch_at {
                #[cfg(debug_assertions)]
                tracing::info!(
                    "Proposal timer for room {}: epoch changed from {} to {}, skipping",
                    queue.room_id,
                    epoch_at,
                    current_epoch
                );
                return;
            }

            let _room_processing_lock = queue.processing_lock.lock_send().await;

            // Swap queue: take proposals out first to minimize lock time
            let queued_proposals = mem::take(&mut *queue.queue.write());

            if let Err(e) = queue
                .handle_batched_proposals(queued_proposals.clone(), mls_rank_group)
                .await
            {
                tracing::warn!("Batched proposal timer: {:?}", e);
                let current_epoch = queue.epoch().await;
                // Restore proposals on error
                let filtered_queued_proposals = queued_proposals
                    .into_iter()
                    .filter(|proposal| {
                        let proposal_epoch = proposal.proposal_message.epoch().unwrap_or(0);
                        proposal_epoch >= *current_epoch
                    })
                    .collect();

                queue.restore_proposal_queue_on_failure(
                    filtered_queued_proposals,
                    "Batched proposal timer failed",
                );
            }
        });
    }

    async fn handle_proposal(
        self: &Arc<Self>,
        proposal: mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error> {
        let epoch_of_proposal = proposal
            .epoch()
            .ok_or(anyhow::anyhow!("Expected proposal to have an epoch"))?;

        let mls_group_epoch = self.epoch().await;

        match epoch_of_proposal.cmp(&mls_group_epoch) {
            Ordering::Less => {
                // check if the proposal is an external add proposal, so we can recreate the proposal
                // and send to server to broadcast to all other clients
                let _ = match proposal.clone().as_proposal() {
                    Some(p) => {
                        let mls_types_proposal: mls_types::Proposal = p.clone().try_into()?;
                        mls_types_proposal
                    }
                    None => {
                        tracing::info!("Received proposal message with old epoch. proposal epoch: {epoch_of_proposal:?}, group epoch: {mls_group_epoch:?}",);
                        return Err(ServiceError::OldEpochProposal.into());
                    }
                };
                {
                    tracing::info!("Received proposal message with old epoch. proposal epoch: {epoch_of_proposal:?}, group epoch: {mls_group_epoch:?}",);
                    return Err(ServiceError::OldEpochProposal.into());
                }
            }
            Ordering::Equal => {}
            Ordering::Greater => {
                tracing::info!("Received proposal message with future epoch. proposal epoch: {:?}, group epoch: {:?}", epoch_of_proposal, mls_group_epoch);
                self.cache_proposal_message(proposal).await?;
                return Err(ServiceError::FutureEpochProposal.into());
            }
        }

        // Re-acquire locks for message processing
        let mut mls_group = self.group.write().await;

        let (received_message, _) = mls_group.decrypt_message(proposal).await?;
        match received_message {
            ReceivedMessage::Proposal => {
                tracing::debug!(
                    "Received proposal is processed. epoch: {:?}",
                    epoch_of_proposal
                );
            }
            ReceivedMessage::Duplicate => {
                #[cfg(debug_assertions)]
                tracing::warn!("Received duplicate message");
            }
            _ => {
                #[cfg(debug_assertions)]
                tracing::error!("Received message is not a proposal: {:?}", received_message);
                return Err(ServiceError::ProposalDecryptionFailed.into());
            }
        }

        Ok(())
    }

    async fn handle_batched_proposals(
        self: &Arc<Self>,
        queued_proposals: Vec<QueuedProposal>,
        mls_rank_group: u64,
    ) -> Result<(), anyhow::Error> {
        if queued_proposals.is_empty() {
            return Ok(());
        }

        let mut mls_group = self.group.write().await;

        let all_proposals =
            Self::decrypt_and_classify_batched_proposals(&mut *mls_group, queued_proposals).await?;

        #[cfg(debug_assertions)]
        tracing::info!(
            "Processing {} batched proposals. epoch: {:?}, roster: {:?}",
            all_proposals.len(),
            mls_group.epoch(),
            mls_group.roster().count()
        );

        let proposal_infos = all_proposals
            .iter()
            .filter_map(|v| match convert_mls_types_to_spec(&v.proposal_message) {
                Ok(proposal) => Some(MlsProposalInfo {
                    room_id: self.room_id.as_bytes().to_vec(),
                    proposal,
                }),
                Err(e) => {
                    tracing::warn!(
                        "Failed to convert proposal to spec for room {}: {:?}",
                        self.room_id,
                        e
                    );
                    None
                }
            })
            .collect::<Vec<_>>();

        if proposal_infos.is_empty() {
            tracing::info!("No valid proposals to process after filtering");
            return Ok(());
        }

        let (added_user_identifiers, agent_user_identifiers) =
            Self::classify_added_ids(&proposal_infos, &mls_group.all_device_ids().collect());
        let role_proposals = Self::compute_role_proposals(
            &self.room_id,
            &mls_group,
            added_user_identifiers,
            agent_user_identifiers,
        )?;

        self.add_pending_commit(&mut *mls_group, role_proposals, proposal_infos)
            .await?;

        let old_epoch = mls_group.epoch();
        mls_group.merge_pending_commit().await?;
        let new_epoch = mls_group.epoch();
        tracing::info!(
            "After handle batched proposals. epoch: {:?}, roster: {:?}",
            new_epoch,
            mls_group.roster().count()
        );

        drop(mls_group);

        let key_update_reason = {
            let has_add = all_proposals
                .iter()
                .any(|p| matches!(p.proposal_type, ProposalType::Add));
            let has_remove = all_proposals
                .iter()
                .any(|p| matches!(p.proposal_type, ProposalType::Remove));

            GroupKeyUpdateReason::from_applied_proposals(has_add, has_remove)
        };
        self.handle_group_update(old_epoch, new_epoch, key_update_reason)
            .await?;

        // update the designated committer metrics
        self.services()?
            .user_service
            .read()
            .await
            .state
            .lock()
            .await
            .set_mls_designated_committer_metrics(*new_epoch as u32, true, mls_rank_group);

        Ok(())
    }

    async fn decrypt_and_classify_batched_proposals(
        mls_group: &mut MlsGroup<MemKv>,
        queued_proposals: Vec<QueuedProposal>,
    ) -> Result<Vec<QueuedProposal>, anyhow::Error> {
        // separate add and remove proposals
        let mut add_proposals = Vec::new();
        let mut remove_proposals = Vec::new();
        let mut app_data_update_proposals = Vec::new();

        // prepare indices for remove proposal validation
        let own_leaf_index = *mls_group.own_leaf_index()?;
        let all_leaf_indices: Vec<u32> = mls_group
            .roster()
            .map(|member| *member.leaf_index())
            .collect();

        for queued_proposal in queued_proposals {
            // TODO: shouldn't remove proposals dropped by the match below be ignored here?
            let result = mls_group
                .decrypt_message(queued_proposal.proposal_message.clone())
                .await;

            let is_ok = match &result {
                Ok((ReceivedMessage::Proposal, _)) => true,
                Ok((ReceivedMessage::Duplicate, _)) => {
                    #[cfg(debug_assertions)]
                    tracing::warn!("Received duplicate proposal in batched processing");
                    false
                }
                Ok((_received, _)) => {
                    #[cfg(debug_assertions)]
                    tracing::error!(
                        "Unexpected message type in batched proposal processing: {:?}",
                        _received
                    );
                    false
                }
                Err(e) => {
                    tracing::warn!("Failed to decrypt proposal in batched processing: {:?}", e);
                    false
                }
            };

            if !is_ok {
                continue;
            }

            match queued_proposal.proposal_type {
                ProposalType::AppDataUpdate => app_data_update_proposals.push(queued_proposal),
                ProposalType::Add => add_proposals.push(queued_proposal),
                ProposalType::Remove => {
                    // validate remove proposal
                    let Some(proposal) = queued_proposal.proposal_message.as_proposal() else {
                        continue;
                    };
                    let Ok(proposal): Result<mls_types::Proposal, MlsTypesError> =
                        proposal.clone().try_into()
                    else {
                        tracing::error!("Invalid proposal: {proposal:?}");
                        continue;
                    };

                    // get the remove leaf node index of the proposal
                    let Some(remove_leaf_node_index) = &proposal.to_remove_index() else {
                        continue;
                    };

                    // check if this client is the smallest leaf node, which is responsible to be commit
                    if own_leaf_index == *remove_leaf_node_index {
                        #[cfg(debug_assertions)]
                        tracing::info!("This client is the node we want to remove, skip");
                        continue;
                    }

                    // check if this node is already removed
                    if !all_leaf_indices.contains(remove_leaf_node_index) {
                        #[cfg(debug_assertions)]
                        tracing::info!("The node is removed from mls group, skip");
                        continue;
                    }

                    remove_proposals.push(queued_proposal);
                }
            }
        }

        // TODO: classification is probably not needed
        // combine all proposals
        Ok(add_proposals
            .into_iter()
            .chain(remove_proposals)
            .chain(app_data_update_proposals)
            .collect())
    }

    fn classify_added_ids(
        proposal_infos: &[MlsProposalInfo],
        roster: &HashSet<DeviceId>,
    ) -> (HashSet<UserId>, HashSet<UserId>) {
        let mut added_user_identifiers = HashSet::new();
        let mut agent_user_identifiers = HashSet::new();

        for proposal_info in proposal_infos {
            // Extract Add proposal from nested structure
            let MlsMessageContent::MlsPublicMessage(message) = &proposal_info.proposal.content
            else {
                continue;
            };

            let ContentTypeInner::Proposal {
                proposal: mls_spec::group::proposals::Proposal::Add(add_proposal),
            } = &message.content.content
            else {
                continue;
            };

            // Convert key package and extract device ID
            let Ok(kp) = mls_types::KeyPackage::try_from(add_proposal.key_package.clone()) else {
                tracing::warn!("Failed to convert key package to mls_types for proposal");
                continue;
            };

            let Ok(mut cred) = kp.credential() else {
                tracing::warn!("Failed to extract credential from key package");
                continue;
            };

            let Ok(device_id) = cred.device_id() else {
                tracing::warn!("Failed to extract device_id from credential");
                continue;
            };

            // Skip if device is already in roster
            if roster.contains(&device_id) {
                continue;
            }

            let owning_identity_id = device_id.owning_identity_id().as_owned();
            if credential_is_agent(&cred) {
                agent_user_identifiers.insert(owning_identity_id.clone());
            }
            added_user_identifiers.insert(owning_identity_id);
        }

        (added_user_identifiers, agent_user_identifiers)
    }

    fn compute_role_proposals(
        room_id: &str,
        mls_group: &MlsGroup<MemKv>,
        added_user_identifiers: HashSet<UserId>,
        agent_user_identifiers: HashSet<UserId>,
    ) -> Result<Vec<ProposalArg>, anyhow::Error> {
        let mut role_proposals = Vec::with_capacity(added_user_identifiers.len());
        let participant_list: HashSet<_> = mls_group
            .participant_list()?
            .map(|l| l.participants.into_iter().map(|p| p.user).collect())
            .unwrap_or_default();
        let epoch = mls_group.epoch();
        for user_identifier in added_user_identifiers {
            let identifier = ProtonMeetIdentityProvider::user_identifier(&user_identifier);
            if participant_list.contains(&identifier) {
                #[cfg(debug_assertions)]
                tracing::debug!("Skipped adding existing user identifier: {:?}", &identifier);
                continue;
            }
            let role = if agent_user_identifiers.contains(&user_identifier) {
                UserRole::Agent
            } else {
                UserRole::Member
            };
            let Some(role_update) = mls_group
                .authorizer()?
                .role_proposal_for_added_user(*epoch, identifier, role)?
                .map(|component| ProposalArg::UpdateComponent {
                    id: component.component_id,
                    data: component.data,
                })
            else {
                tracing::error!(
                    "Failed to compute role for user identifier: {:?}",
                    user_identifier
                );
                continue;
            };
            role_proposals.push(role_update);
        }

        role_proposals.push(ProposalArg::PskExternal {
            id: psk_id_for_commit(room_id, group_has_agent(&mls_group)),
        });

        Ok(role_proposals)
    }

    async fn add_pending_commit(
        &self,
        mls_group: &mut MlsGroup<MemKv>,
        role_proposals: Vec<ProposalArg>,
        proposal_infos: Vec<MlsProposalInfo>,
    ) -> Result<(), anyhow::Error> {
        // process all proposals in the same commit
        let (commit_bundle, ..) = mls_group.new_commit(role_proposals).await?;

        let own_device_id = mls_group.own_device_id()?;
        let mimi_subject = MimiSubject::from_str(own_device_id.to_string().as_str())?;
        let user_token_info = UserTokenInfo {
            user_identifier: mls_group.own_user_id()?,
            device_id: mimi_subject.device_id().to_string(),
        };

        // Update group info to the server
        let group_info = commit_bundle
            .group_info
            .ok_or_else(|| anyhow::anyhow!("Expected commit to have a GroupInfo"))?;
        let group_info_message = convert_mls_types_to_spec(&group_info)?;
        let ratchet_tree_option = commit_bundle
            .ratchet_tree
            .ok_or_else(|| anyhow::anyhow!("Expected commit to have a RatchetTree"))?
            .try_into()
            .map_err(|e| anyhow::anyhow!("Failed to convert ratchet tree: {e}"))?;

        let base64_sd_kbt = self
            .services()?
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_token_info.user_id())
            .await?;

        let welcome = commit_bundle.welcome.map(TryInto::try_into).transpose()?;

        let commit_info = MlsCommitInfo {
            room_id: self.room_id.as_bytes().to_vec(),
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
                Some(proposal_infos),
            )
            .await;

        match result {
            Ok(_) => {
                #[cfg(debug_assertions)]
                tracing::info!("Update group info success for batched proposals");
                Ok(())
            }
            Err(e) => {
                tracing::info!("Update group info failed: {:?}", e);
                // Clean up the stored group's state so MemKv stays consistent
                mls_group.clear_pending_commit();
                mls_group.clear_pending_proposals();
                mls_group.write_to_storage().await?;
                Err(e.into())
            }
        }
    }

    async fn handle_group_update(
        &self,
        old_epoch: Epoch,
        new_epoch: Epoch,
        key_update_reason: GroupKeyUpdateReason,
    ) -> Result<(), anyhow::Error> {
        let services = self.services()?;
        let service = services.user_service.read().await;

        // trigger the mls group update handler to update the meeting room key
        service
            .handlers
            .call_mls_group_update_handler(self.room_id.clone(), key_update_reason)
            .await;

        // Check if epoch advanced and update host role if needed
        if new_epoch > old_epoch {
            if let Err(e) = service.check_and_update_host_role(&self.room_id).await {
                tracing::warn!(
                    "Failed to check and update host role after batched proposals epoch change: {:?}",
                    e
                );
                // Don't fail the operation if role update fails
            }
        }

        Ok(())
    }
}

#[test]
#[allow(unreachable_code)]
#[should_panic]
fn require_fn_to_be_send() {
    fn require_send<T: Send>(_t: T) {}
    require_send(MessageQueue::push_commit(todo!(), todo!()));
    require_send(MessageQueue::push_proposal(todo!(), todo!()));
}
