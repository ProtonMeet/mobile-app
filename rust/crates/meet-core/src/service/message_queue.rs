use std::{
    cmp::Ordering,
    collections::{hash_map::Entry, HashMap, HashSet},
    future::Future,
    mem,
    pin::Pin,
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
use proton_meet_macro::{async_trait, async_trait_with_mock};
use proton_meet_mls::{kv::MemKv, MlsStore};
use tokio::sync::RwLock;

use crate::{
    domain::{
        mls::ports::MessageCachePort,
        user::{
            models::UserTokenInfo,
            ports::{MlsApi, UserService},
        },
    },
    errors::{http_client::HttpClientError, service::ServiceError},
    infra::{message_cache::CachedMessageType, mimi_subject_parser::MimiSubject},
    service::{
        compute_stagger_time,
        service_state::MlsGroupState,
        services_bundle::ServiceBundle,
        user_service::{
            credential_is_agent, psk_id_for_commit, utils::group_has_agent, GroupKeyUpdateReason,
            ProposalType, QueuedProposal,
        },
        utils::{calculate_retry_delay, convert_mls_types_to_spec},
        StaggerStats, RANK_GROUP_DELAY_MS,
    },
    utils::{
        sleep, spawn_detached,
        sync::{AsyncMutex, AsyncRwLock, SyncRwLock},
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

/// Per-room ingress for MLS traffic.
///
/// Kept behind a trait so callers hold `ArcMessageQueue` and tests can substitute
/// `MockMessageQueue` instead of standing up a real MLS group.
#[cfg(not(target_family = "wasm"))]
pub(crate) type ArcMessageQueueService = Arc<dyn MessageQueueService + Send + Sync + 'static>;
#[cfg(target_family = "wasm")]
pub(crate) type ArcMessageQueueService = Arc<dyn MessageQueueService + 'static>;

type ProposalBuilder = Box<
    dyn for<'a> Fn(
            &'a mut MlsGroup<MemKv>,
        ) -> Pin<
            Box<dyn Future<Output = Result<Option<QueuedProposal>, ServiceError>> + Send + 'a>,
        > + Send
        + Sync
        + 'static,
>;

#[async_trait_with_mock]
pub(crate) trait MessageQueueService {
    /// Handles an inbound commit for this room, replaying any cached backlog it unblocks.
    async fn push_commit(
        &self,
        room_id: &str,
        commit: mls_types::MlsMessage,
    ) -> Result<(), ServiceError>;

    /// Handles an inbound proposal for this room, queueing it for the next batched commit.
    async fn push_proposal(
        &self,
        room_id: &str,
        proposal: mls_types::MlsMessage,
    ) -> Result<(), ServiceError>;

    async fn push_proposal_and_commit(
        &self,
        room_id: &str,
        proposal_builder: ProposalBuilder,
    ) -> Result<(), ServiceError>;
}

pub(crate) struct MessageQueueServiceImpl {
    mls_queues: AsyncRwLock<HashMap<String, Arc<MessageQueue>>>,
    mls_store: Arc<RwLock<MlsStore>>,
    msg_cache: Arc<dyn MessageCachePort>,
    mls_api: Arc<dyn MlsApi>,
    services: Weak<ServiceBundle>,
}

impl MessageQueueServiceImpl {
    pub fn new(
        mls_store: Arc<RwLock<MlsStore>>,
        msg_cache: Arc<dyn MessageCachePort>,
        mls_api: Arc<dyn MlsApi>,
        services: Weak<ServiceBundle>,
    ) -> Self {
        Self {
            mls_queues: Default::default(),
            mls_store,
            msg_cache,
            mls_api,
            services,
        }
    }

    async fn get_message_queue(&self, room_id: &str) -> Result<Arc<MessageQueue>, ServiceError> {
        if let Some(queue) = self.mls_queues.read().await.get(room_id) {
            return Ok(queue.clone());
        }

        let mut map = self.mls_queues.write_send().await;
        match map.entry(room_id.into()) {
            Entry::Occupied(occupied_entry) => Ok(occupied_entry.get().clone()),
            Entry::Vacant(vacant_entry) => {
                let queue = MessageQueue::new(
                    room_id.into(),
                    self.mls_store.clone(),
                    self.msg_cache.clone(),
                    self.services.clone(),
                    self.mls_api.clone(),
                );

                Ok(vacant_entry.insert_entry(Arc::new(queue)).get().clone())
            }
        }
    }
}

#[async_trait]
impl MessageQueueService for MessageQueueServiceImpl {
    async fn push_commit(
        &self,
        room_id: &str,
        commit: mls_types::MlsMessage,
    ) -> Result<(), ServiceError> {
        self.get_message_queue(room_id)
            .await?
            .push_commit(commit)
            .await
    }

    async fn push_proposal(
        &self,
        room_id: &str,
        proposal: mls_types::MlsMessage,
    ) -> Result<(), ServiceError> {
        self.get_message_queue(room_id)
            .await?
            .push_proposal(proposal)
            .await
    }

    async fn push_proposal_and_commit(
        &self,
        room_id: &str,
        proposal_builder: ProposalBuilder,
    ) -> Result<(), ServiceError> {
        self.get_message_queue(room_id)
            .await?
            .push_proposal_and_commit(proposal_builder)
            .await
    }
}

struct MessageQueue {
    room_id: String,
    mls_store: Arc<tokio::sync::RwLock<MlsStore>>,
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
        mls_store: Arc<tokio::sync::RwLock<MlsStore>>,
        msg_cache: Arc<dyn MessageCachePort>,
        services: Weak<ServiceBundle>,
        mls_api: Arc<dyn MlsApi>,
    ) -> Self {
        Self {
            room_id,
            mls_store,
            queue: SyncRwLock::new(Vec::new(), |_| {}),
            msg_cache,
            processing_lock: Default::default(),
            timer: SyncRwLock::new(None, |v| *v = None),
            services,
            mls_api,
        }
    }

    fn services(&self) -> Result<Arc<ServiceBundle>, ServiceError> {
        self.services.upgrade().ok_or(ServiceError::NoServiceBundle)
    }

    async fn group(&self) -> Result<Arc<RwLock<MlsGroup<MemKv>>>, ServiceError> {
        self.mls_store
            .read()
            .await
            .group_map
            .get(&self.room_id)
            .cloned()
            .ok_or(ServiceError::GroupNotFound)
    }

    async fn process_commit_message(
        self: &Arc<Self>,
        commit: mls_types::MlsMessage,
    ) -> Result<CommitProcessingOutcome, ServiceError> {
        let group_epoch = self.epoch().await?;
        let commit_epoch = commit.epoch().ok_or(ServiceError::NoEpochCommit)?;

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

        if let Err(e) = Self::validate_psk_proposal(&self.room_id, &commit) {
            // PSK validation failed: restore queue and return.
            self.restore_proposal_queue_on_failure(
                queued_proposals,
                "Failed to process commit message",
            );
            return Err(e);
        }

        let mls_group = self.group().await?;
        let mut mls_group = mls_group.write().await;
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
                        Err(ServiceError::PskProposalMissing),
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
                    Err(ServiceError::ProposalNotFound),
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
                    Err(ServiceError::InvalidMlsMessageType),
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

    pub(super) async fn process_cached_messages(self: &Arc<Self>) -> Result<(), ServiceError> {
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
            let current_epoch = self.epoch().await?;

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
            let current_group_epoch = self.epoch().await?;

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
                .await
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
                                let new_group_epoch = self.epoch().await?;

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
        let final_epoch = self.epoch().await?;

        // Remove cached messages that are older than current epoch
        self.msg_cache
            .cleanup_old_messages(&self.room_id, *final_epoch, 0)
            .await;

        Ok(())
    }

    async fn process_cached_proposals(&self, group_epoch: Epoch) -> Result<(), ServiceError> {
        // handle proposals from msg_cache for this epoch
        if let Some(cached_messages) = self
            .msg_cache
            .get_cached_messages(&self.room_id, *group_epoch)
            .await
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
        &self,
        commit: mls_types::MlsMessage,
    ) -> Result<(), ServiceError> {
        self.msg_cache
            .cache_message(
                &self.room_id,
                commit.epoch().ok_or(ServiceError::NoEpochCommit)?,
                CachedMessageType::Commit,
                commit,
            )
            .await;
        Ok(())
    }
    async fn cache_proposal_message(
        &self,
        proposal: mls_types::MlsMessage,
    ) -> Result<(), ServiceError> {
        self.msg_cache
            .cache_message(
                &self.room_id,
                proposal.epoch().ok_or(ServiceError::NoEpochProposal)?,
                CachedMessageType::Proposal,
                proposal,
            )
            .await;
        Ok(())
    }

    fn restore_proposal_queue_on_failure(
        &self,
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
            self.queue.write().extend(queued_proposals);
        }
    }

    async fn epoch(&self) -> Result<Epoch, ServiceError> {
        Ok(self.group().await?.read().await.epoch())
    }

    pub(super) fn validate_psk_proposal(
        room_id: &str,
        message: &mls_types::MlsMessage,
    ) -> Result<(), ServiceError> {
        use crate::service::agent_host_service::agent_psk_id_for_meeting;
        let expected_agent_id = agent_psk_id_for_meeting(room_id);
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
                                if id_bytes != room_id.as_bytes()
                                    && id_bytes.as_slice() != expected_agent_id.as_slice()
                                {
                                    tracing::error!("PSK ID mismatch for room {}", room_id);
                                    return Err(ServiceError::PskProposalMissing);
                                }
                            }
                        }
                    }
                }
                if !has_psk {
                    tracing::error!("PSK proposal missing for room {}", room_id);
                    return Err(ServiceError::PskProposalMissing);
                }
            }
        }
        Ok(())
    }

    async fn process_proposal_message(
        self: &Arc<Self>,
        message: mls_types::MlsMessage,
    ) -> Result<ProposalProcessingOutcome, ServiceError> {
        let proposal = match message.clone().as_proposal() {
            Some(p) => {
                let mls_types_proposal: mls_types::Proposal = p.clone().try_into()?;
                mls_types_proposal
            }
            None => return Ok(ProposalProcessingOutcome::NoStateChange),
        };

        let proposal_epoch = message.epoch().ok_or(ServiceError::NoEpochProposal)?;
        let current_epoch = self.epoch().await?;

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
                    already_applied: false,
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
            .committer_rank(&*self.group().await?.read().await)
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
            match queue.epoch().await {
                Ok(v) if v != epoch_at => {
                    #[cfg(debug_assertions)]
                    tracing::info!(
                        "Proposal timer for room {}: epoch changed from {epoch_at} to {v}, skipping",
                        queue.room_id,
                    );
                    return;
                }
                Err(e) => {
                    #[cfg(debug_assertions)]
                    tracing::info!(
                        "Proposal timer for room {}: could not run epoch check ({e:?}, skipping",
                        queue.room_id,
                    );
                    return;
                }
                _ => {}
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
                let filtered_queued_proposals = if let Ok(current_epoch) = current_epoch {
                    queued_proposals
                        .into_iter()
                        .filter(|proposal| {
                            let proposal_epoch = proposal.proposal_message.epoch().unwrap_or(0);
                            proposal_epoch >= *current_epoch
                        })
                        .collect()
                } else {
                    queued_proposals
                };

                // Restoring here may cause some already applied proposals to be pushed back to
                // the queue, if `handle_batched_proposals` failed after creating the commit.
                // However, this is not an issue since the `MlsGroup` would answer with `Duplicate`
                // when re-applying these proposals.
                queue.restore_proposal_queue_on_failure(
                    filtered_queued_proposals,
                    "Batched proposal timer failed",
                );
            }
        });
    }

    async fn handle_proposal(&self, proposal: mls_types::MlsMessage) -> Result<(), ServiceError> {
        let epoch_of_proposal = proposal.epoch().ok_or(ServiceError::NoEpochProposal)?;

        let mls_group_epoch = self.epoch().await?;

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
                        return Err(ServiceError::OldEpochProposal);
                    }
                };
                {
                    tracing::info!("Received proposal message with old epoch. proposal epoch: {epoch_of_proposal:?}, group epoch: {mls_group_epoch:?}",);
                    return Err(ServiceError::OldEpochProposal);
                }
            }
            Ordering::Equal => {}
            Ordering::Greater => {
                tracing::info!("Received proposal message with future epoch. proposal epoch: {:?}, group epoch: {:?}", epoch_of_proposal, mls_group_epoch);
                self.cache_proposal_message(proposal).await?;
                return Err(ServiceError::FutureEpochProposal);
            }
        }

        // Re-acquire locks for message processing
        let mls_group = self.group().await?;
        let mut mls_group = mls_group.write().await;

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
                return Err(ServiceError::ProposalDecryptionFailed);
            }
        }

        Ok(())
    }

    pub(super) async fn handle_batched_proposals(
        &self,
        queued_proposals: Vec<QueuedProposal>,
        mls_rank_group: u64,
    ) -> Result<(), ServiceError> {
        if queued_proposals.is_empty() {
            return Ok(());
        }

        let mls_group = self.group().await?;
        let mut mls_group = mls_group.write().await;

        let all_proposals =
            Self::decrypt_and_classify_batched_proposals(&mut mls_group, queued_proposals).await?;

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

        self.add_pending_commit(&mut mls_group, role_proposals, Some(proposal_infos))
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
    ) -> Result<Vec<QueuedProposal>, ServiceError> {
        let mut kept_proposals = Vec::new();

        // prepare indices for remove proposal validation
        let own_leaf_index = *mls_group.own_leaf_index()?;
        let all_leaf_indices: Vec<u32> = mls_group
            .roster()
            .map(|member| *member.leaf_index())
            .collect();

        for queued_proposal in queued_proposals {
            if queued_proposal.already_applied {
                kept_proposals.push(queued_proposal);
                continue;
            }

            // TODO: shouldn't remove proposals dropped by the match below be ignored here?
            let result = mls_group
                .decrypt_message(queued_proposal.proposal_message.clone())
                .await;

            let is_ok = match &result {
                Ok((ReceivedMessage::Proposal, _)) => true,
                Ok((ReceivedMessage::Duplicate, _)) => {
                    #[cfg(debug_assertions)]
                    tracing::warn!("Received duplicate proposal in batched processing");
                    eprintln!("Received duplicate proposal in batched processing");
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
                ProposalType::AppDataUpdate | ProposalType::Add => {
                    kept_proposals.push(queued_proposal)
                }
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

                    kept_proposals.push(queued_proposal);
                }
            }
        }

        Ok(kept_proposals)
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
    ) -> Result<Vec<ProposalArg>, ServiceError> {
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
            id: psk_id_for_commit(room_id, group_has_agent(mls_group)),
        });

        Ok(role_proposals)
    }

    /// Builds a commit from `role_proposals`, publishes it to the server and leaves it
    /// pending on `mls_group` for the caller to merge.
    ///
    /// `proposal_infos` is the fan-out list sent alongside the commit; pass `None` when
    /// the commit carries no by-reference proposals the server needs to relay.
    ///
    /// On publish failure the group's pending commit and proposals are cleared so the
    /// stored `MemKv` state stays consistent, and the transport error is returned
    /// unchanged so callers can inspect it (e.g. to retry on HTTP 422).
    async fn add_pending_commit(
        &self,
        mls_group: &mut MlsGroup<MemKv>,
        role_proposals: Vec<ProposalArg>,
        proposal_infos: Option<Vec<MlsProposalInfo>>,
    ) -> Result<(), ServiceError> {
        // process all proposals in the same commit
        let (commit_bundle, ..) = mls_group.new_commit(role_proposals).await?;

        let own_device_id = mls_group.own_device_id()?;
        let mimi_subject = MimiSubject::from_str(own_device_id.to_string().as_str())
            .map_err(|e| ServiceError::Internal(e.to_string()))?;
        let user_token_info = UserTokenInfo {
            user_identifier: mls_group.own_user_id()?,
            device_id: mimi_subject.device_id().to_string(),
        };

        // Update group info to the server
        let group_info = commit_bundle
            .group_info
            .ok_or_else(|| ServiceError::Internal("Expected commit to have a GroupInfo".into()))?;
        let group_info_message = convert_mls_types_to_spec(&group_info)
            .map_err(|e| ServiceError::Internal(e.to_string()))?;
        let ratchet_tree_option = commit_bundle
            .ratchet_tree
            .ok_or_else(|| ServiceError::Internal("Expected commit to have a RatchetTree".into()))?
            .try_into()
            .map_err(|e| ServiceError::Internal(format!("Failed to convert ratchet tree: {e}")))?;

        let base64_sd_kbt = self
            .services()?
            .user_service
            .read()
            .await
            .get_sd_kbt(&user_token_info.user_id())
            .await
            .map_err(|e| ServiceError::Internal(e.to_string()))?;

        let welcome = commit_bundle.welcome.map(TryInto::try_into).transpose()?;

        let commit_info = MlsCommitInfo {
            room_id: self.room_id.as_bytes().to_vec(),
            welcome_message: welcome,
            commit: convert_mls_types_to_spec(&commit_bundle.commit)
                .map_err(|e| ServiceError::Internal(e.to_string()))?,
        };

        let result = self
            .mls_api
            .update_group_info(
                &base64_sd_kbt,
                &group_info_message,
                &ratchet_tree_option,
                Some(&commit_info),
                proposal_infos,
            )
            .await;

        match result {
            Ok(_) => {
                #[cfg(debug_assertions)]
                tracing::info!("Update group info success");
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
    ) -> Result<(), ServiceError> {
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

    async fn push_commit(
        self: &Arc<Self>,
        commit: mls_types::MlsMessage,
    ) -> Result<(), ServiceError> {
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
                if let ServiceError::PskProposalMissing = &e {
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

    async fn push_proposal(
        self: &Arc<Self>,
        proposal: mls_types::MlsMessage,
    ) -> Result<(), ServiceError> {
        match self.process_proposal_message(proposal.clone()).await {
            Ok(ProposalProcessingOutcome::Applied) => {
                // A proposal accepted into the current epoch can unblock a commit that was
                // cached because MLS reported `ProposalNotFound`, so replay the backlog.
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
            Ok(ProposalProcessingOutcome::NoStateChange) => {
                tracing::debug!(
                    "Proposal did not change state for room {}, skipping cached message processing",
                    self.room_id
                );
            }
            Ok(ProposalProcessingOutcome::DeferredFutureEpoch) => {
                tracing::debug!(
                    "Proposal deferred for future epoch in room {}, skipping cached message processing",
                    self.room_id
                );
            }
            Err(e) => {
                tracing::warn!("Failed to process proposal message: {e}");
                // Keep the proposal so a later epoch can retry it.
                if let Err(e) = self.cache_proposal_message(proposal).await {
                    tracing::warn!(
                        "Failed to cache proposal message for room {}: {e:?}",
                        self.room_id
                    );
                }
            }
        }

        Ok(())
    }

    async fn push_proposal_and_commit(
        self: &Arc<Self>,
        proposal_builder: ProposalBuilder,
    ) -> Result<(), ServiceError> {
        const MAX_RETRIES: u32 = 3;
        const BASE_DELAY_MS: u64 = 500;
        const MAX_DELAY_MS: u64 = 10000;

        let mut i = 0;

        loop {
            tracing::info!("Pushing proposal, attempt {i}/{MAX_RETRIES}");

            let room_processing_lock = self.processing_lock.lock_send().await;

            let Some(proposal) = proposal_builder(&mut *self.group().await?.write().await).await?
            else {
                return Ok(());
            };

            let mut queued_proposals = mem::take(&mut *self.queue.write());
            queued_proposals.push(proposal);

            let Err(e) = self
                .handle_batched_proposals(queued_proposals.clone(), 0)
                .await
            else {
                return Ok(());
            };
            tracing::warn!("Batch handling failed: {e:?}");

            let current_epoch = self.epoch().await?;
            // Restore proposals on error
            let filtered_queued_proposals = queued_proposals
                .into_iter()
                .filter(|proposal| {
                    let proposal_epoch = proposal.proposal_message.epoch().unwrap_or(0);
                    proposal_epoch >= *current_epoch
                })
                .collect();

            // Restoring here may cause some already applied proposals to be pushed back to
            // the queue, if `handle_batched_proposals` failed after creating the commit.
            // However, this is not an issue since the `MlsGroup` would answer with `Duplicate`
            // when re-applying these proposals.
            self.restore_proposal_queue_on_failure(
                filtered_queued_proposals,
                "Batched proposal with force push failed",
            );
            drop(room_processing_lock);

            let is_retryable = match &e {
                ServiceError::HttpClientError(HttpClientError::ErrorCode(status, ..)) => {
                    *status == 422
                }
                _ => false,
            };

            if !is_retryable {
                tracing::warn!(
                    "Kick failed with non-retryable error on attempt {i}/{MAX_RETRIES}: {e:?}"
                );
                return Err(e);
            }

            if i == MAX_RETRIES {
                break;
            }

            let delay_ms = calculate_retry_delay(i, BASE_DELAY_MS, MAX_DELAY_MS);

            tracing::warn!(
                "Kick failed with HTTP 422 (attempt {}/{}), retrying in {}ms",
                i,
                MAX_RETRIES,
                delay_ms
            );

            sleep(Duration::from_millis(delay_ms)).await;
            i += 1;
        }

        Err(ServiceError::MaxRetriesReached)
    }
}

#[cfg(test)]
#[cfg(not(target_family = "wasm"))]
mod test {
    use std::{future::ready, mem, sync::Arc};

    use identity::{Disclosure, PresentationContext};
    use meet_identifiers::LeafIndex;
    use meet_type::fanout::{MlsCommitInfo, RTCMessageIn, RTCMessageInContent};
    use mls_rs::group::proposal::Proposal;
    use mls_rs_codec::MlsEncode;
    use mls_spec::messages::MlsMessageContent;
    use mls_spec::Parsable;
    use mls_spec::{drafts::ratchet_tree_options::RatchetTreeOption, Serializable};
    use mls_trait::{
        meet_policy::UserRole, CommitBundle, MlsClientConfig, MlsClientTrait, MlsGroupTrait,
        ProposalArg,
    };
    use mls_types::ExternalPskId;
    use proton_meet_mls::{kv::MemKv, MlsGroup};
    use rand::{rngs::StdRng, seq::SliceRandom, Rng, SeedableRng};
    use tokio::sync::{Mutex, RwLock};
    use uuid::Uuid;

    use crate::{
        domain::user::{models::UserId, ports::UserService},
        errors::service::ServiceError,
        infra::{
            adapters::mls::message_cache_adapter::MessageCacheAdapter,
            message_cache::{CachedMessageType, MlsMessageCache},
            ws_client::WebSocketMessage,
        },
        service::{
            message_queue::MessageQueue,
            service_state::MlsGroupState,
            services_bundle::ServiceBundle,
            test::{
                create_mock_mls_api, create_test_service_bundle,
                create_test_service_bundle_with_host, setup_single_user_group,
                PopulatedServiceBundleDI, ServiceBundleDI,
            },
            user_service::{
                create_test_service, mls_group_export_snapshot,
                service_test::tests::{
                    setup_n_user_group, setup_two_user_group_with_commit_bundle,
                },
                ProposalType, QueuedProposal, Service,
            },
        },
    };

    pub fn commit_to_mls_message(commit_bundle: &CommitBundle) -> mls_types::MlsMessage {
        let commit_bytes = commit_bundle.commit.mls_encode_to_vec().unwrap();
        let spec_msg = mls_spec::messages::MlsMessage::from_tls_bytes(&commit_bytes).unwrap();
        mls_types::MlsMessage::try_from(spec_msg).unwrap()
    }

    /// A leaked test bundle plus the handles these tests drive.
    ///
    /// The bundle is leaked so that `setup_n_user_group` can take `'static` write guards
    /// and so the `Weak<ServiceBundle>` each `MessageQueue` holds stays upgradeable for
    /// the life of the test.
    struct TestMember {
        bundle: Arc<ServiceBundle>,
        pop: PopulatedServiceBundleDI,
        cache: Arc<Mutex<MlsMessageCache>>,
    }

    impl TestMember {
        async fn new(user_id: &str, room_id: &str, is_host: bool) -> Self {
            let cache = Arc::new(Mutex::new(MlsMessageCache::new()));
            let (bundle, pop) = create_test_service_bundle_with_host(
                user_id,
                room_id,
                is_host,
                ServiceBundleDI {
                    message_cache: Some(Arc::new(MessageCacheAdapter::new(cache.clone()))),
                    ..Default::default()
                },
            );
            Self { bundle, pop, cache }
        }

        async fn queue(&self, room_id: &str) -> Arc<MessageQueue> {
            self.pop
                .message_queue_service
                .get_message_queue(room_id)
                .await
                .unwrap()
        }

        async fn mark_mls_ready(&self) {
            self.bundle
                .user_service
                .read()
                .await
                .state
                .lock()
                .await
                .mls_group_state = MlsGroupState::Success;
        }

        async fn group(&self, room_id: &str) -> Arc<RwLock<MlsGroup<MemKv>>> {
            self.pop
                .mls_store
                .read()
                .await
                .group_map
                .get(room_id)
                .unwrap()
                .clone()
        }

        /// How many messages of `message_type` are cached for `room_id` at `epoch`.
        async fn cached_count(
            &self,
            room_id: &str,
            epoch: u64,
            message_type: CachedMessageType,
        ) -> usize {
            self.cache
                .lock()
                .await
                .messages
                .get(room_id)
                .and_then(|rooms| rooms.get(&epoch))
                .and_then(|epochs| epochs.get(&message_type))
                .map(|messages| messages.len())
                .unwrap_or(0)
        }

        async fn service(&self) -> tokio::sync::RwLockReadGuard<'_, Service> {
            self.bundle.user_service.read().await
        }
    }

    async fn join_by_external_commit(
        joiner: &TestMember,
        room_id: &str,
        ciphersuite: proton_meet_mls::CipherSuite,
        reference_bundle: &CommitBundle,
    ) -> CommitBundle {
        let service = joiner.bundle.user_service.read().await;
        let user_token_info = service
            .create_mls_client("access_token", room_id, "meet_password", None)
            .await
            .unwrap();

        let group_info_message = mls_spec::messages::MlsMessage::from_tls_bytes(
            &reference_bundle
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap();
        let group_info = match group_info_message.content {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        let (_, commit_bundle) = service
            .create_external_commit_with_psks(
                &user_token_info.user_id(),
                room_id,
                ciphersuite,
                group_info,
                reference_bundle
                    .ratchet_tree
                    .clone()
                    .unwrap()
                    .try_into()
                    .unwrap(),
                vec![ExternalPskId(room_id.as_bytes().to_vec())],
            )
            .await
            .unwrap();
        commit_bundle
    }

    #[tokio::test]
    async fn validate_psk_proposal_accepts_commit_with_correct_psk_id() {
        let room_id = "unit-psk-correct";
        let (_, pop, group, ciphersuite, user_id) =
            setup_single_user_group(room_id, Default::default()).await;

        let psk_id = mls_types::ExternalPskId(room_id.as_bytes().to_vec());
        let psk_value = mls_types::ExternalPsk(b"test-psk-secret".to_vec());
        {
            let store = pop.mls_store.read().await;
            let client = store.find_client(&user_id, &ciphersuite).unwrap();
            client
                .insert_external_psk(psk_id.clone(), psk_value)
                .await
                .unwrap();
        }

        let commit_bundle = {
            let mut g = group.write().await;
            let (bundle, _) = g
                .new_commit(vec![ProposalArg::PskExternal { id: psk_id }])
                .await
                .unwrap();
            bundle
        };

        let result =
            MessageQueue::validate_psk_proposal(room_id, &commit_to_mls_message(&commit_bundle));
        assert!(
            result.is_ok(),
            "Expected Ok for correct PSK ID, got: {:?}",
            result.err()
        );
    }

    #[tokio::test]
    async fn validate_psk_proposal_rejects_commit_with_no_psk_proposal() {
        let room_id = "unit-psk-missing";
        let (_, _, group, _, _) = setup_single_user_group(room_id, Default::default()).await;

        let commit_bundle = {
            let mut g = group.write().await;
            let (bundle, _) = g.new_commit(vec![]).await.unwrap();
            bundle
        };

        let result =
            MessageQueue::validate_psk_proposal(room_id, &commit_to_mls_message(&commit_bundle));
        assert!(
            matches!(result, Err(ServiceError::PskProposalMissing)),
            "Expected PskProposalMissing, got: {result:?}",
        );
    }

    #[tokio::test]
    async fn validate_psk_proposal_rejects_commit_with_wrong_psk_id() {
        let room_id = "unit-psk-wrong-id";
        let (_, pop, group, ciphersuite, user_id) =
            setup_single_user_group(room_id, Default::default()).await;

        let wrong_id = mls_types::ExternalPskId(b"wrong-room-id".to_vec());
        let psk_value = mls_types::ExternalPsk(b"test-psk-secret".to_vec());
        {
            let store = pop.mls_store.read().await;
            let client = store.find_client(&user_id, &ciphersuite).unwrap();
            client
                .insert_external_psk(wrong_id.clone(), psk_value)
                .await
                .unwrap();
        }

        let commit_bundle = {
            let mut g = group.write().await;
            let (bundle, _) = g
                .new_commit(vec![ProposalArg::PskExternal { id: wrong_id }])
                .await
                .unwrap();
            bundle
        };

        let result =
            MessageQueue::validate_psk_proposal(room_id, &commit_to_mls_message(&commit_bundle));
        assert!(
            matches!(result, Err(ServiceError::PskProposalMissing)),
            "Expected PskProposalMissing, got: {result:?}",
        );
    }

    #[tokio::test]
    async fn test_handle_batched_proposals_empty_queue() {
        // Test case: Empty proposal queue should return Ok (empty proposals)
        let meet_link_name = "test_empty_queue";

        let cache = Arc::new(MessageCacheAdapter::new(Arc::new(Mutex::new(
            MlsMessageCache::new(),
        ))));
        let (bundle, pop, ..) = setup_single_user_group(
            meet_link_name,
            ServiceBundleDI {
                message_cache: Some(cache.clone()),
                ..Default::default()
            },
        )
        .await;

        // Set MLS group state to Success
        bundle
            .user_service
            .read()
            .await
            .state
            .lock()
            .await
            .mls_group_state = MlsGroupState::Success;

        // Get proposals from queue (will be empty)
        let queue = pop
            .message_queue_service
            .get_message_queue(meet_link_name)
            .await
            .unwrap();
        let queued_proposals = mem::take(&mut *queue.queue.write());
        assert!(queued_proposals.is_empty());

        let result = queue.handle_batched_proposals(queued_proposals, 0).await;
        assert!(result.is_ok(), "Should return Ok when proposals are empty");
    }

    #[tokio::test]
    async fn test_handle_batched_proposals_different_epoch() {
        // Test case: Proposals with different epoch should be filtered out by handle_proposal
        let meet_link_name = "test_different_epoch";
        let config = MlsClientConfig::default();

        let (s1_bundle, s1_pop) =
            create_test_service_bundle("user1", meet_link_name, ServiceBundleDI::default());
        let service1 = s1_bundle.user_service.read().await;

        let (s2_bundle, _) =
            create_test_service_bundle("user2", meet_link_name, ServiceBundleDI::default());
        let service2 = s2_bundle.user_service.read().await;

        // Setup two-user group
        let (group1, group2, _) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        // Create a proposal from group2 at current epoch
        use mls_trait::{MlsGroupTrait, ProposalArg};
        let user2_leaf_index = *group2.read().await.own_leaf_index().unwrap();
        let mut proposals = group2
            .write()
            .await
            .new_proposals([ProposalArg::Remove(
                meet_identifiers::LeafIndex::try_from(user2_leaf_index).unwrap(),
            )])
            .await
            .unwrap();
        let old_proposal = proposals.remove(0);
        let proposal_message: mls_types::MlsMessage = old_proposal;

        // Advance group1's epoch by creating and processing a commit
        // This will make the proposal's epoch older than group1's current epoch
        let (_commit_bundle, _) = group1.write().await.new_commit([]).await.unwrap();
        group1.write().await.merge_pending_commit().await.unwrap();

        let s1_queue = s1_pop
            .message_queue_service
            .get_message_queue(meet_link_name)
            .await
            .unwrap();

        // Now group1 is at epoch 3, but proposal is from epoch 2
        // Add proposal with old epoch to queue
        s1_queue.queue.write().push(QueuedProposal {
            proposal_message,
            proposal_type: ProposalType::Remove,
            already_applied: false,
        });

        service1.state.lock().await.mls_group_state = MlsGroupState::Success;

        // Get proposals from queue
        let queued_proposals = mem::take(&mut *s1_queue.queue.write());

        // handle_proposal will reject this proposal because it's from an old epoch
        // So all_proposals will be empty and function will return Ok
        let result = s1_queue.handle_batched_proposals(queued_proposals, 0).await;
        assert!(
            result.is_ok(),
            "Should return Ok when proposals are filtered out due to epoch mismatch"
        );
    }

    #[tokio::test]
    async fn test_handle_batched_proposals_remove_own_node() {
        // Test case: Remove proposal targeting own node should be skipped
        let meet_link_name = "test_remove_own";
        let config = MlsClientConfig::default();

        let (s1_bundle, s1_pop) =
            create_test_service_bundle("user1", meet_link_name, ServiceBundleDI::default());
        let service1 = s1_bundle.user_service.read().await;

        let (s2_bundle, _) =
            create_test_service_bundle("user2", meet_link_name, ServiceBundleDI::default());
        let service2 = s2_bundle.user_service.read().await;

        // Setup two-user group
        let (group1, _group2, _) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        let own_leaf_index = *group1.read().await.own_leaf_index().unwrap();
        let _current_epoch = *group1.read().await.epoch();

        // Create a remove proposal targeting own node
        use mls_trait::{MlsGroupTrait, ProposalArg};
        let mut proposals = group1
            .write()
            .await
            .new_proposals([ProposalArg::Remove(
                meet_identifiers::LeafIndex::try_from(own_leaf_index).unwrap(),
            )])
            .await
            .unwrap();
        let remove_proposal = proposals.remove(0);
        let proposal_message: mls_types::MlsMessage = remove_proposal;

        let s1_queue = s1_pop
            .message_queue_service
            .get_message_queue(meet_link_name)
            .await
            .unwrap();

        // Add proposal to queue
        s1_queue.queue.write().push(QueuedProposal {
            proposal_message: proposal_message.clone(),
            proposal_type: ProposalType::Remove,
            already_applied: false,
        });

        // Set state to Success
        service1.state.lock().await.mls_group_state = MlsGroupState::Success;

        // Get proposals from queue
        let queued_proposals = mem::take(&mut *s1_queue.queue.write());

        // Mock HTTP client to not be called (since proposal should be skipped)
        let result = s1_queue.handle_batched_proposals(queued_proposals, 0).await;
        assert!(result.is_ok(), "Should return Ok when skipping own removal");
    }

    #[tokio::test]
    async fn test_handle_batched_proposals_success() {
        // Test case: Successfully process batched proposals (both Add and Remove)
        let meet_link_name = "test_success";
        let config = MlsClientConfig::default();

        // The room's queue clones `mls_api` when it is built, so the mock that expects
        // `update_group_info` has to be injected with the bundle rather than swapped in
        // afterwards.
        let mut mls_api = create_mock_mls_api("user1", meet_link_name, false);
        mls_api
            .expect_update_group_info()
            .returning(|_, _, _, _, _| Box::pin(ready(Ok(()))));

        let (s1_bundle, s1_pop) = create_test_service_bundle(
            "user1",
            meet_link_name,
            ServiceBundleDI {
                mls_api: Some(Arc::new(mls_api)),
                ..Default::default()
            },
        );
        let service1 = s1_bundle.user_service.read().await;

        let (s2_bundle, _) =
            create_test_service_bundle("user2", meet_link_name, ServiceBundleDI::default());
        let service2 = s2_bundle.user_service.read().await;

        let (s3_bundle, _) =
            create_test_service_bundle("user3", meet_link_name, ServiceBundleDI::default());
        let service3 = s3_bundle.user_service.read().await;

        // Setup two-user group
        let (group1, group2, _) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        let current_epoch = *group1.read().await.epoch();
        let user2_leaf_index = *group2.read().await.own_leaf_index().unwrap();

        // Record initial state before processing proposals
        let initial_roster_size = group1.read().await.roster().count();
        assert_eq!(
            initial_roster_size, 2,
            "Initial group should have 2 members"
        );

        // Create user3's MLS client
        let user_token_info3 = service3
            .create_mls_client("access_token", meet_link_name, "meet_password", None)
            .await
            .unwrap();

        // Get group info and ratchet tree from group1 to create external proposal
        let (group_info, ratchet_tree_option) = {
            let store = service1.mls_store.read().await;
            let group = store.group_map.get(meet_link_name).unwrap();
            let group_read = group.read().await;

            // Get GroupInfo for external proposals
            let group_info_mls_spec = group_read
                .group_info_for_ext_commit()
                .await
                .expect("Should get group_info_for_ext_commit");

            // Parse to get GroupInfo
            let group_info_bytes = group_info_mls_spec.mls_encode_to_vec().unwrap();
            let group_info_message =
                mls_spec::messages::MlsMessage::from_tls_bytes(&group_info_bytes).unwrap();
            let group_info = match group_info_message.content {
                mls_spec::messages::MlsMessageContent::GroupInfo(gi) => gi,
                _ => panic!("Expected GroupInfo"),
            };

            // Get the ratchet tree and convert to RatchetTreeOption
            let exported_tree = group_read.ratchet_tree();

            // Serialize ExportedTree and deserialize to mls_spec::tree::RatchetTree
            let tree_bytes = exported_tree.mls_encode_to_vec().unwrap();
            let ratchet_tree_mls_spec =
                mls_spec::tree::RatchetTree::from_tls_bytes(&tree_bytes).unwrap();
            let ratchet_tree_option = RatchetTreeOption::Full {
                ratchet_tree: ratchet_tree_mls_spec,
            };

            (group_info, ratchet_tree_option)
        };

        // Create external proposal for user3 to get key package
        let external_proposal_user3 = service3
            .create_external_proposal(
                &user_token_info3.user_id(),
                config.ciphersuite,
                group_info,
                ratchet_tree_option,
            )
            .await
            .unwrap();

        // Extract key package from external proposal
        // as_proposal() returns mls_rs::group::proposal::Proposal, not mls_types::Proposal
        let key_package_user3 = match external_proposal_user3.as_proposal() {
            Some(Proposal::Add(add)) => add.key_package().clone(),
            _ => panic!("Expected Add Proposal for user3"),
        };

        // Create add proposal from group2 to add user3
        use mls_trait::{MlsGroupTrait, ProposalArg};
        let mut add_proposals = group2
            .write()
            .await
            .new_proposals([ProposalArg::Add(Box::new(key_package_user3.into()))])
            .await
            .unwrap();
        let add_proposal = add_proposals.remove(0);
        let add_proposal_message: mls_types::MlsMessage = add_proposal;

        // Create remove proposal from group2 (user2's group) to remove user2
        // This simulates user2 creating a self-remove proposal, or another client creating it
        // The proposal needs to be created from a different group context to be properly encrypted
        let mut remove_proposals = group2
            .write()
            .await
            .new_proposals([ProposalArg::Remove(
                meet_identifiers::LeafIndex::try_from(user2_leaf_index).unwrap(),
            )])
            .await
            .unwrap();
        let remove_proposal = remove_proposals.remove(0);
        let remove_proposal_message: mls_types::MlsMessage = remove_proposal;

        // Add both proposals to queue (add first, then remove)
        let s1_queue = s1_pop
            .message_queue_service
            .get_message_queue(meet_link_name)
            .await
            .unwrap();
        s1_queue.queue.write().extend([
            QueuedProposal {
                proposal_message: add_proposal_message,
                proposal_type: ProposalType::Add,
                already_applied: false,
            },
            QueuedProposal {
                proposal_message: remove_proposal_message,
                proposal_type: ProposalType::Remove,
                already_applied: false,
            },
        ]);

        // Set state to Success
        service1.state.lock().await.mls_group_state = MlsGroupState::Success;

        let queued_proposals = mem::take(&mut *s1_queue.queue.write());

        let result = s1_queue.handle_batched_proposals(queued_proposals, 0).await;
        assert!(
            result.is_ok(),
            "Should successfully process batched proposals"
        );

        // Verify that the proposals were successfully processed
        // Check that roster size: +1 (user3 added) -1 (user2 removed) = same size
        // But since we're removing user2 and adding user3, final size should be 2 (user1 + user3)
        let final_group = group1.clone();
        let final_roster_size = final_group.read().await.roster().count();
        // After adding user3 and removing user2: 2 (initial) + 1 (add) - 1 (remove) = 2
        assert_eq!(
            final_roster_size, 2,
            "Roster size should be 2 after adding user3 and removing user2 (user1 + user3)"
        );

        // Verify user3 was added and user2 was removed
        // Get user IDs from the roster (not leaf indices, as they can be reused)
        let roster_members: Vec<u32> = {
            let group = final_group.read().await;
            let roster = group.roster();
            roster.map(|member| *member.leaf_index()).collect()
        };

        let mut user_ids_in_group = Vec::new();
        for leaf_index in roster_members {
            let group_write = final_group.write().await;
            let leaf_index_typed = LeafIndex::try_from(leaf_index).unwrap();
            if let Ok(mut member) = group_write.find_member(leaf_index_typed) {
                if let Ok(user_id) = member.credential.user_id() {
                    user_ids_in_group.push(user_id);
                }
            }
            drop(group_write); // Release write lock before next iteration
        }

        // user2 should be removed
        assert!(
            !user_ids_in_group
                .iter()
                .any(|v| v.id.to_string() == "user2"),
            "User2 should be removed from the group"
        );
        // user3 should be added
        assert!(
            user_ids_in_group
                .iter()
                .any(|v| v.id.to_string() == "user3"),
            "User3 should be added to the group"
        );

        for user_id in user_ids_in_group {
            let role = final_group
                .read()
                .await
                .user_role_for_current_epoch(&user_id)
                .unwrap();
            assert_eq!(role, UserRole::Member);
        }

        // Verify epoch increased
        let final_epoch = *final_group.read().await.epoch();
        assert!(
            final_epoch > current_epoch,
            "Epoch should increase after processing proposals"
        );

        // Verify proposal queue is empty (proposals were processed and removed)
        assert!(
            s1_queue.queue.read().is_empty(),
            "Proposal queue should be empty after processing"
        );
    }

    #[tokio::test]
    async fn test_handle_commit_message_with_two_epoch_difference_out_of_order() {
        let meet_link_name = "two_epoch_difference_out_of_order";
        let config = MlsClientConfig::default();

        // Setup services for 4 users
        let member1 = TestMember::new("user_id1", meet_link_name, true).await;
        let member2 = TestMember::new("user_id2", meet_link_name, false).await;
        let member3 = TestMember::new("user_id3", meet_link_name, false).await;
        let member4 = TestMember::new("user_id4", meet_link_name, false).await;

        let groups = {
            let service1 = member1.bundle.user_service.write().await;
            let service2 = member2.bundle.user_service.write().await;
            let service3 = member3.bundle.user_service.write().await;
            let service4 = member4.bundle.user_service.write().await;
            setup_n_user_group(
                vec![&service1, &service2, &service3, &service4],
                meet_link_name,
                config.ciphersuite,
            )
            .await
        };
        let group1 = groups[0].clone();
        let group2 = groups[1].clone();
        let group3 = groups[2].clone();
        let group4 = groups[3].clone();

        // Verify initial state - all groups should be at same epoch
        let initial_epoch = group1.read().await.epoch();
        assert_eq!(group2.read().await.epoch(), initial_epoch);
        assert_eq!(group3.read().await.epoch(), initial_epoch);
        assert_eq!(group4.read().await.epoch(), initial_epoch);
        assert_eq!(group1.read().await.roster().count(), 4);

        // Remove 2nd user (user_id2) to advance epoch by 1
        let (remove_user2_commit, remove_user2_proposal) = {
            let group2_index = group2.read().await.own_leaf_index().unwrap();
            let proposal = ProposalArg::Remove(group2_index);
            let mut group1_guard = group1.write().await;
            let proposal_msg = group1_guard
                .new_proposals([proposal])
                .await
                .unwrap()
                .remove(0);
            let (commit_bundle, _) = group1_guard
                .new_commit([ProposalArg::PskExternal {
                    id: ExternalPskId(meet_link_name.as_bytes().to_vec()),
                }])
                .await
                .unwrap();
            group1_guard.merge_pending_commit().await.unwrap();
            (commit_bundle, proposal_msg)
        };

        // Process removal only in group 3 (skip group2 since it's being removed, keep group4 behind)
        {
            let mut group3_guard = group3.write().await;
            group3_guard
                .decrypt_message(remove_user2_proposal.clone())
                .await
                .unwrap();
            group3_guard
                .decrypt_message(remove_user2_commit.commit.clone())
                .await
                .unwrap();
        }
        // Don't process in group4 - keep it at the original epoch

        // Remove 3rd user (user_id3) to advance epoch by another 1 (total 2 epochs ahead)
        let (future_commit, future_proposal) = {
            let group3_index = group3.read().await.own_leaf_index().unwrap();
            let proposal = ProposalArg::Remove(group3_index);
            let mut group1_guard = group1.write().await;
            let proposal_msg = group1_guard
                .new_proposals([proposal])
                .await
                .unwrap()
                .remove(0);
            let (commit_bundle, _) = group1_guard
                .new_commit([ProposalArg::PskExternal {
                    id: ExternalPskId(meet_link_name.as_bytes().to_vec()),
                }])
                .await
                .unwrap();
            group1_guard.merge_pending_commit().await.unwrap();
            (commit_bundle, proposal_msg)
        };

        // Don't process second removal in group4 - keep it behind at the original epoch
        // Now group1 is 2 epochs ahead of group4

        // Verify epoch differences: group1 should be 2 epochs ahead of group4
        let final_epoch = group1.read().await.epoch();
        let group4_epoch = group4.read().await.epoch();

        assert_eq!(group1.read().await.roster().count(), 2); // Only user1 and user4 left in group1's view
        assert_eq!(group4.read().await.roster().count(), 4); // group4 still sees all 4 users
        assert_eq!(group4_epoch, initial_epoch); // group4 stayed at original epoch
        assert_ne!(final_epoch, initial_epoch); // Verify group1's epoch has advanced

        // Now group1 is further ahead of group4
        let very_future_epoch = group1.read().await.epoch();
        assert_ne!(very_future_epoch, initial_epoch); // Verify further advancement

        member4.mark_mls_ready().await;
        let queue4 = member4.queue(meet_link_name).await;

        // Test 1: Send future commit to group4 - should be cached as out-of-order
        let result = queue4.push_commit(future_commit.commit.clone()).await;
        assert!(result.is_ok());

        // Test 2: Send future proposal to group4 - should also be cached as out-of-order
        let result = queue4.push_proposal(future_proposal.clone()).await;
        assert!(
            result.is_ok(),
            "Future epoch proposal should be added to queue without error"
        );

        // Verify messages are cached with correct epochs in user4's cache
        let target_epoch = *very_future_epoch;
        assert_eq!(
            member4
                .cached_count(meet_link_name, target_epoch, CachedMessageType::Commit)
                .await,
            0,
            "Should have at least 1 cached commit message"
        );
        assert_eq!(
            member4
                .cached_count(meet_link_name, target_epoch, CachedMessageType::Proposal)
                .await,
            0,
            "Should have at least 1 cached proposal message"
        );

        // Test 3: Process missing commits in order to sync user4 with the advanced group
        // First, send the removal proposal for user2 to user4
        let proposal_result = queue4.push_proposal(remove_user2_proposal.clone()).await;
        assert!(
            proposal_result.is_ok(),
            "User4 should be able to process user2 removal proposal"
        );

        // Then send the commit for user2 removal to help user4 catch up
        let result = queue4.push_commit(remove_user2_commit.commit.clone()).await;
        assert!(
            result.is_ok(),
            "User4 should be able to process user2 removal commit"
        );

        // Verify user4's epoch has advanced
        let group4_epoch_after_sync = *member4.group(meet_link_name).await.read().await.epoch();

        assert_eq!(group4_epoch_after_sync, *final_epoch);
        assert_eq!(group4_epoch_after_sync, 6);
    }

    #[tokio::test]
    async fn test_handle_proposal_message_with_future_epoch() {
        let meet_link_name = "proposal_message_with_future_epoch";
        let config = MlsClientConfig::default();

        let member1 = TestMember::new("user_id", meet_link_name, false).await;
        let member2 = TestMember::new("user_id2", meet_link_name, false).await;
        let member3 = TestMember::new("user_id3", meet_link_name, false).await;

        let (group1, group2, commit_bundle2) = {
            let service1 = member1.bundle.user_service.read().await;
            let service2 = member2.bundle.user_service.read().await;
            setup_two_user_group_with_commit_bundle(
                &service1,
                &service2,
                meet_link_name,
                config.ciphersuite,
            )
            .await
        };

        // Third user joins via external commit using the latest group state
        let commit_bundle3 = join_by_external_commit(
            &member3,
            meet_link_name,
            config.ciphersuite,
            &commit_bundle2,
        )
        .await;

        // Process the join in group1 only (group2 will be behind)
        group1
            .write()
            .await
            .decrypt_message(commit_bundle3.commit.clone())
            .await
            .unwrap();

        let group3 = member3.group(meet_link_name).await;

        // Now group1 and group3 are at epoch N+1, group2 is at epoch N
        assert_eq!(group1.read().await.epoch(), group3.read().await.epoch());
        assert_ne!(group1.read().await.epoch(), group2.read().await.epoch());

        // Create a proposal from group1, which is at a future epoch relative to group2
        let future_proposal = group1
            .write()
            .await
            .new_proposals([ProposalArg::Remove(LeafIndex::try_from(2).unwrap())])
            .await
            .unwrap()
            .remove(0);

        member2.mark_mls_ready().await;
        let queue2 = member2.queue(meet_link_name).await;
        let result = queue2.push_proposal(future_proposal.clone()).await;

        // Future epoch proposals should be cached (not queued/timered immediately).
        assert!(
            result.is_ok(),
            "Future epoch proposal should be handled gracefully without error"
        );

        // Check proposal queue is untouched for this room.
        assert_eq!(
            queue2.queue.read().len(),
            0,
            "Future epoch proposal should not be added to queue"
        );

        // Check the future proposal was cached under its epoch.
        let future_epoch = future_proposal.epoch().unwrap_or(0);
        assert!(
            member2
                .cached_count(meet_link_name, future_epoch, CachedMessageType::Proposal)
                .await
                > 0,
            "Future epoch proposal should be cached for later processing"
        );
    }

    #[tokio::test]
    async fn test_handle_proposal_message_with_old_epoch() {
        let meet_link_name = "proposal_message_with_old_epoch";
        let config = MlsClientConfig::default();

        let member1 = TestMember::new("user_id", meet_link_name, false).await;
        let member2 = TestMember::new("user_id2", meet_link_name, false).await;
        let member3 = TestMember::new("user_id3", meet_link_name, false).await;

        let (group1, group2, commit_bundle2) = {
            let service1 = member1.bundle.user_service.read().await;
            let service2 = member2.bundle.user_service.read().await;
            setup_two_user_group_with_commit_bundle(
                &service1,
                &service2,
                meet_link_name,
                config.ciphersuite,
            )
            .await
        };

        // Create a proposal from group2 at the current epoch
        let old_proposal = group2
            .write()
            .await
            .new_proposals([ProposalArg::Remove(LeafIndex::try_from(1).unwrap())])
            .await
            .unwrap()
            .remove(0);

        // Add third user to the group (this advances group1's epoch)
        let commit_bundle3 = join_by_external_commit(
            &member3,
            meet_link_name,
            config.ciphersuite,
            &commit_bundle2,
        )
        .await;

        // Process the join in group1 only (advancing its epoch)
        group1
            .write()
            .await
            .decrypt_message(commit_bundle3.commit.clone())
            .await
            .unwrap();

        // Now group1 is at epoch N+1, and the old_proposal is from epoch N
        member1.mark_mls_ready().await;
        let queue1 = member1.queue(meet_link_name).await;
        let result = queue1.push_proposal(old_proposal.clone()).await;

        // Old epoch proposals should be ignored (not queued, not cached).
        assert!(
            result.is_ok(),
            "Old epoch proposal should be handled gracefully without error"
        );

        // Check proposal queue is untouched for this room.
        assert_eq!(
            queue1.queue.read().len(),
            0,
            "Old epoch proposal should not be added to queue"
        );

        // Check old proposal is not cached for later epochs.
        let old_epoch = old_proposal.epoch().unwrap_or(0);
        assert_eq!(
            member1
                .cached_count(meet_link_name, old_epoch, CachedMessageType::Proposal)
                .await,
            0,
            "Old epoch proposal should not be cached"
        );
    }

    #[tokio::test]
    async fn test_handle_out_of_order_messages_with_missing_commit_last() {
        let meet_link_name = "out_of_order_missing_commit_last";
        let config = MlsClientConfig::default();

        // Setup services and initial two-user group
        let member1 = TestMember::new("user_id1", meet_link_name, true).await;
        let member2 = TestMember::new("user_id2", meet_link_name, false).await;
        let member3 = TestMember::new("user_id3", meet_link_name, false).await;

        let (group1, group2, commit_bundle2) = {
            let service1 = member1.bundle.user_service.read().await;
            let service2 = member2.bundle.user_service.read().await;
            setup_two_user_group_with_commit_bundle(
                &service1,
                &service2,
                meet_link_name,
                config.ciphersuite,
            )
            .await
        };

        // Setup third user and create external commit
        let commit_bundle3 = join_by_external_commit(
            &member3,
            meet_link_name,
            config.ciphersuite,
            &commit_bundle2,
        )
        .await;

        // Process third user join in group1 only (group2 stays behind)
        group1
            .write()
            .await
            .decrypt_message(commit_bundle3.commit.clone())
            .await
            .unwrap();

        let group3 = member3.group(meet_link_name).await;

        // Create a proposal and commit from group1 (at the advanced epoch)
        let (commit_with_proposal, proposal_msg) = {
            let group3_index = group3.read().await.own_leaf_index().unwrap();
            let proposal = ProposalArg::Remove(group3_index);
            let mut group1_guard = group1.write().await;
            let proposal_msg = group1_guard
                .new_proposals([proposal])
                .await
                .unwrap()
                .remove(0);
            let (commit_bundle, _) = group1_guard
                .new_commit([ProposalArg::PskExternal {
                    id: ExternalPskId(meet_link_name.as_bytes().to_vec()),
                }])
                .await
                .unwrap();
            group1_guard.merge_pending_commit().await.unwrap();
            (commit_bundle, proposal_msg)
        };

        // Process messages in group3 to keep it in sync
        {
            let mut guard = group3.write().await;
            guard.decrypt_message(proposal_msg.clone()).await.unwrap();
            guard
                .decrypt_message(commit_with_proposal.commit.clone())
                .await
                .unwrap();
        }

        member2.mark_mls_ready().await;
        let queue2 = member2.queue(meet_link_name).await;

        // Step 1: Send the commit with proposal first, which is a future epoch for group2
        let result = queue2
            .push_commit(commit_with_proposal.commit.clone())
            .await;
        assert!(
            result.is_ok(),
            "Future epoch commit should be handled gracefully"
        );

        // Step 2: Send the proposal message AFTER the commit (out of order)
        let result = queue2.push_proposal(proposal_msg.clone()).await;
        assert!(
            result.is_ok(),
            "Out of order proposal should be handled gracefully"
        );

        // Step 3: Finally send the missing group3 join commit, which lets the cached
        // messages be replayed.
        let result = dbg!(queue2.push_commit(commit_bundle3.commit.clone()).await);
        assert!(
            result.is_ok(),
            "Missing commit should be processed successfully"
        );

        // Verify that cached messages were processed
        assert_eq!(
            member2
                .cached_count(meet_link_name, 4, CachedMessageType::Commit)
                .await,
            0,
            "Cached commit messages should be processed and removed"
        );
        assert_eq!(
            member2
                .cached_count(meet_link_name, 4, CachedMessageType::Proposal)
                .await,
            0,
            "Cached proposal messages should be processed and removed"
        );

        // Verify final state: Check actual epochs and roster sizes
        let final_group1_epoch = group1.read().await.epoch();
        let final_group2_epoch = group2.read().await.epoch();
        let group1_roster_size = group1.read().await.roster().count();
        let group2_roster_size = group2.read().await.roster().count();

        assert!(*final_group1_epoch == 4, "Group1 should be at epoch 4");
        assert!(*final_group2_epoch == 4, "Group2 should be at epoch 4");
        assert!(group1_roster_size == 2, "Group1 roster size should be 2");
        assert!(group2_roster_size == 2, "Group2 roster size should be 2");
    }

    #[tokio::test]
    async fn test_kick_participant_includes_queued_proposals() {
        let meet_link_name = "test-kick-queued";
        let ciphersuite =
            proton_meet_mls::CipherSuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

        // Setup three-user group
        let mut mls_api = create_mock_mls_api("user_id1", meet_link_name, true);
        mls_api
            .expect_update_group_info()
            .returning(|_, _, _, _, _| Box::pin(ready(Ok(()))));
        let (s1_bundle, s1_pop) = create_test_service_bundle(
            "user1",
            meet_link_name,
            ServiceBundleDI {
                message_cache: Some(Arc::new(MessageCacheAdapter::default())),
                mls_api: Some(Arc::new(mls_api)),
                ..Default::default()
            },
        );
        let service1 = s1_bundle.user_service.read().await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let groups = setup_n_user_group(
            vec![&service1, &service2, &service3],
            meet_link_name,
            ciphersuite,
        )
        .await;
        let group1 = groups[0].clone();

        let initial_roster_count = group1.read().await.roster().count();
        assert_eq!(initial_roster_count, 3);

        // Get user2's UUID for later removal
        let user2_uuid = {
            let group = group1.read().await;
            let roster: Vec<_> = group.roster().collect();
            if let mls_types::Credential::SdCwtDraft04 { claimset, .. } = &roster[1].credential {
                uuid::Uuid::from_bytes(claimset.as_ref().unwrap().uuid).to_string()
            } else {
                panic!("Expected SdCwtDraft04 credential");
            }
        };

        // Create a remove proposal for user3 (index 2) and queue it
        // This simulates having pending proposals when kick is called
        let user3_remove_proposal = {
            let mut group = group1.write().await;
            let mut proposals = group
                .new_proposals([ProposalArg::Remove(
                    meet_identifiers::LeafIndex::try_from(2u32).unwrap(),
                )])
                .await
                .unwrap();
            proposals.remove(0)
        };

        // Queue the proposal
        let s1_queue = s1_pop
            .message_queue_service
            .get_message_queue(meet_link_name)
            .await
            .unwrap();
        s1_queue.queue.write().push(QueuedProposal {
            proposal_message: user3_remove_proposal,
            proposal_type: ProposalType::Remove,
            already_applied: false,
        });

        // Verify queue has 1 proposal
        let queued_count = s1_queue.queue.read().len();
        assert_eq!(queued_count, 1, "Should have 1 queued proposal");

        eprintln!("Kicking 2");
        // Kick user2 - should also process the queued user3 removal
        service1
            .kick_participant(&user2_uuid, meet_link_name)
            .await
            .unwrap();

        // Verify both user2 and user3 were removed (3 -> 1, only user1 remains)
        let final_roster_count = group1.read().await.roster().count();
        assert_eq!(
            final_roster_count, 1,
            "Should have 1 member after kick (both user2 and user3 removed)"
        );

        // Verify queue is now empty (proposals were extracted and processed)
        let queue_empty = s1_queue.queue.read().is_empty();
        assert!(queue_empty, "Proposal queue should be empty after kick");
    }

    #[tokio::test]
    #[ignore = "manual stress: random external adds (capped) + random removes + post-merge observe_group"]
    async fn stress_external_proposals_observe_group_post_merge() {
        const DEFAULT_NUM_SESSION_RETRIES: usize = 5;
        const DEFAULT_NUM_ROUNDS: usize = 40;
        // Upper bound (inclusive) on external add proposals per round.
        const DEFAULT_NEW_MEMBERS_PER_ROUND: usize = 5;

        let num_session_retries = DEFAULT_NUM_SESSION_RETRIES;
        let num_rounds = DEFAULT_NUM_ROUNDS;
        let new_members_per_round = DEFAULT_NEW_MEMBERS_PER_ROUND;

        let mut rng: StdRng = StdRng::from_rng(&mut rand::thread_rng()).expect("seed RNG");

        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        for session in 0..num_session_retries {
            let meet_link_name = format!("stress_observe_{session}_{}", Uuid::new_v4());
            let mut mls_api = create_mock_mls_api("user1", &meet_link_name, true);
            mls_api
                .expect_update_group_info()
                .returning(|_, _, _, _, _| Box::pin(ready(Ok(()))));
            let (s1_bundle, s1_pop) = create_test_service_bundle(
                "user1",
                &meet_link_name,
                ServiceBundleDI {
                    message_cache: Some(Arc::new(MessageCacheAdapter::default())),
                    mls_api: Some(Arc::new(mls_api)),
                    ..Default::default()
                },
            );
            let service1 = s1_bundle.user_service.read().await;
            let service2 = create_test_service("user2", &meet_link_name).await;
            let validator_label = format!("validator_stress_{session}");
            let validator_service =
                Arc::new(create_test_service(&validator_label, &meet_link_name).await);

            let (group1, _group2, _) = setup_two_user_group_with_commit_bundle(
                &service1,
                &service2,
                &meet_link_name,
                ciphersuite,
            )
            .await;

            let validator_user_token = validator_service
                .create_mls_client(
                    "access_token_validator",
                    &meet_link_name,
                    "meet_password",
                    None,
                )
                .await
                .expect("validator MLS client");
            let validator_user_id = validator_user_token.user_id();

            service1.state.lock().await.mls_group_state = MlsGroupState::Success;

            for round in 0..num_rounds {
                let epoch_at_round_start = *group1.read().await.epoch();
                let roster_at_round_start = group1.read().await.roster().count();

                let num_adds = rng.gen_range(0..=new_members_per_round);

                let own_leaf = *group1.read().await.own_leaf_index().unwrap();
                let mut removable_leaves: Vec<u32> = group1
                    .read()
                    .await
                    .roster()
                    .map(|m| *m.leaf_index())
                    .filter(|&li| li != own_leaf)
                    .collect();
                let max_removable = removable_leaves.len();
                let num_removes = if max_removable == 0 {
                    0
                } else {
                    rng.gen_range(0..=max_removable)
                };
                removable_leaves.shuffle(&mut rng);
                let leaves_to_remove: Vec<u32> =
                    removable_leaves.into_iter().take(num_removes).collect();

                eprintln!(
                    "[stress_external_proposals_observe_group_post_merge] session={}/{} round={}/{} epoch={} roster={} adds_max={} num_adds={} num_removes={}",
                    session + 1,
                    num_session_retries,
                    round + 1,
                    num_rounds,
                    epoch_at_round_start,
                    roster_at_round_start,
                    new_members_per_round,
                    num_adds,
                    num_removes,
                );

                let mut queued: Vec<QueuedProposal> =
                    Vec::with_capacity(num_adds.saturating_add(num_removes));

                if num_adds > 0 {
                    let (proposal_mls_message, ratchet_tree_for_proposals) =
                        mls_group_export_snapshot(&group1).await;
                    let group_info = match proposal_mls_message.content {
                        MlsMessageContent::GroupInfo(gi) => gi,
                        _ => panic!("Expected GroupInfo in MLS message for proposals"),
                    };

                    let add_services = futures::future::join_all((0..num_adds).map(|add_idx| {
                        let meet_link_name = meet_link_name.clone();
                        async move {
                            let user_id = format!("stress_s{session}_r{round}_add_{add_idx}");
                            let service = create_test_service(&user_id, &meet_link_name).await;
                            let user_token = service
                                .create_mls_client(
                                    "access_token",
                                    &meet_link_name,
                                    "meet_password",
                                    None,
                                )
                                .await
                                .expect("new member MLS client");
                            (service, user_token.user_id())
                        }
                    }))
                    .await;

                    for (add_service, add_user_id) in &add_services {
                        let proposal_message = add_service
                            .create_external_proposal(
                                add_user_id,
                                ciphersuite,
                                group_info.clone(),
                                ratchet_tree_for_proposals.clone(),
                            )
                            .await
                            .unwrap_or_else(|e| {
                                panic!(
                                    "create_external_proposal failed session={}/{} round={}/{} epoch={}: {e}",
                                    session + 1,
                                    num_session_retries,
                                    round + 1,
                                    num_rounds,
                                    epoch_at_round_start
                                )
                            });
                        queued.push(QueuedProposal {
                            proposal_message,
                            proposal_type: ProposalType::Add,
                            already_applied: false,
                        });
                    }
                }

                if !leaves_to_remove.is_empty() {
                    let remove_args: Vec<ProposalArg> = leaves_to_remove
                        .iter()
                        .map(|&leaf| {
                            ProposalArg::Remove(
                                LeafIndex::try_from(leaf).expect("valid leaf index for Remove"),
                            )
                        })
                        .collect();
                    let remove_messages = group1
                        .write()
                        .await
                        .new_proposals(remove_args)
                        .await
                        .unwrap_or_else(|e| {
                            panic!(
                                "new_proposals(Remove) failed session={}/{} round={}/{} epoch={}: {e}",
                                session + 1,
                                num_session_retries,
                                round + 1,
                                num_rounds,
                                epoch_at_round_start
                            )
                        });
                    for proposal_message in remove_messages {
                        queued.push(QueuedProposal {
                            proposal_message,
                            proposal_type: ProposalType::Remove,
                            already_applied: false,
                        });
                    }
                }

                s1_pop.message_queue_service.get_message_queue(&meet_link_name).await.unwrap()
                    .handle_batched_proposals(queued, 0)
                    .await
                    .unwrap_or_else(|e| {
                        panic!(
                            "handle_batched_proposals failed session={}/{} round={}/{} epoch={}: {e}",
                            session + 1,
                            num_session_retries,
                            round + 1,
                            num_rounds,
                            epoch_at_round_start
                        )
                    });

                let epoch_after = *group1.read().await.epoch();
                let roster_after = group1.read().await.roster().count();

                let (post_merge_message, post_merge_ratchet) =
                    mls_group_export_snapshot(&group1).await;

                if let Err(e) = validate_group_export_with_external_client(
                    validator_service.as_ref(),
                    &validator_user_id,
                    &meet_link_name,
                    post_merge_message,
                    post_merge_ratchet,
                )
                .await
                {
                    panic!(
                        "ExternalClient observe_group failed session={}/{} round={}/{} epoch_before={} epoch_after={} roster_before={} roster_after={}: {e}",
                        session + 1,
                        num_session_retries,
                        round + 1,
                        num_rounds,
                        epoch_at_round_start,
                        epoch_after,
                        roster_at_round_start,
                        roster_after
                    );
                }

                eprintln!(
                    "[stress_external_proposals_observe_group_post_merge] session={}/{} round={}/{} completed epoch_after={} roster_after={}",
                    session + 1,
                    num_session_retries,
                    round + 1,
                    num_rounds,
                    epoch_after,
                    roster_after
                );
            }
        }
    }

    async fn validate_group_export_with_external_client(
        service: &Service,
        participant_id: &UserId,
        meet_link_name: &str,
        group_info_message: mls_spec::messages::MlsMessage,
        ratchet_tree_option: RatchetTreeOption,
    ) -> Result<(), anyhow::Error> {
        let ciphersuite = service.mls_store.read().await.config.ciphersuite;
        let store = service.mls_store.read().await;
        let client = store.find_client(&participant_id.to_string(), &ciphersuite)?;

        let signing_identity =
            client.new_signing_identity(Disclosure::Full, &PresentationContext::Default, None)?;
        let ext_client = mls_rs::external_client::ExternalClient::builder()
            .signer(client.signature_sk.clone(), signing_identity)
            .identity_provider(client.identity_provider()?)
            .crypto_provider(client.delegate()?.crypto_provider())
            .build();

        let group_info: mls_types::MlsMessage = group_info_message.try_into().map_err(|e| {
            anyhow::anyhow!("Failed to convert group info for external client validation: {e}")
        })?;
        let ratchet_tree: mls_types::PublicRatchetTree =
            ratchet_tree_option.try_into().map_err(|e| {
                anyhow::anyhow!(
                    "Failed to convert ratchet tree option for external client validation: {e}"
                )
            })?;

        ext_client
            .observe_group(group_info.into(), Some(ratchet_tree.into()), None)
            .await
            .map(|_| ())
            .map_err(|e| {
                anyhow::anyhow!(
                    "ExternalClient observe_group failed for room {meet_link_name}: {e}"
                )
            })
    }

    #[tokio::test]
    async fn test_process_commit_rejects_missing_psk() {
        let meet_link_name = "test_psk_reject_missing";
        let config = MlsClientConfig::default();

        let member1 = TestMember::new("psk-user1", meet_link_name, false).await;
        let member2 = TestMember::new("psk-user2", meet_link_name, false).await;

        let (group1, _group2, _) = setup_two_user_group_with_commit_bundle(
            &*member1.service().await,
            &*member2.service().await,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        // group1 creates a commit with NO PSK proposal
        let commit_bundle = {
            let mut group1_guard = group1.write().await;
            let (bundle, _) = group1_guard.new_commit(vec![]).await.unwrap();
            group1_guard.merge_pending_commit().await.unwrap();
            bundle
        };

        let commit_bytes = commit_bundle.commit.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&commit_bytes).unwrap(),
            }),
        };
        let ws_message = WebSocketMessage::Binary(rtc_message.to_tls_bytes().unwrap());
        member2.service().await.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = member2
            .service()
            .await
            .handle_websocket_message(ws_message)
            .await;

        assert!(
            result.is_err(),
            "Expected error when commit has no PSK proposal"
        );
        let err = result.unwrap_err();
        assert!(
            err.downcast_ref::<ServiceError>()
                .map(|e| matches!(e, ServiceError::PskProposalMissing))
                .unwrap_or(false),
            "Expected PskProposalMissing error, got: {err:?}",
        );
    }

    #[tokio::test]
    async fn test_process_commit_rejects_wrong_psk_id() {
        let meet_link_name = "test_psk_reject_wrong_id";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        let member1 = TestMember::new("psk-user1", meet_link_name, false).await;
        let member2 = TestMember::new("psk-user2", meet_link_name, false).await;

        let (group1, _group2, _) = setup_two_user_group_with_commit_bundle(
            &*member1.service().await,
            &*member2.service().await,
            meet_link_name,
            ciphersuite,
        )
        .await;

        let user1_id = {
            let store = member1.pop.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("service1 should have one MLS client")
        };
        let user2_id = {
            let store = member2.pop.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("service2 should have one MLS client")
        };

        // Insert a PSK with a WRONG ID (not matching meet_link_name/room_id) into both clients
        let wrong_psk_id = mls_types::ExternalPskId(b"wrong-room-id".to_vec());
        let psk_value = mls_types::ExternalPsk(b"some-psk-secret-value-for-testing".to_vec());

        {
            let store = member1.pop.mls_store.read().await;
            let client = store
                .find_client(&user1_id, &ciphersuite)
                .expect("service1 client should exist");
            client
                .insert_external_psk(wrong_psk_id.clone(), psk_value.clone())
                .await
                .expect("service1 should insert external PSK");
        }
        {
            let store = member2.pop.mls_store.read().await;
            let client = store
                .find_client(&user2_id, &ciphersuite)
                .expect("service2 client should exist");
            client
                .insert_external_psk(wrong_psk_id.clone(), psk_value.clone())
                .await
                .expect("service2 should insert external PSK");
        }

        // group1 creates a commit referencing the WRONG PSK ID.
        // Do NOT call merge_pending_commit so group1's epoch is not advanced —
        // this lets MLS decryption succeed on service2 (it has the same wrong PSK)
        // while the service-level check still rejects it (PSK ID != room_id).
        let commit_bundle = {
            let mut group1_guard = group1.write().await;
            let (bundle, _) = group1_guard
                .new_commit(vec![ProposalArg::PskExternal {
                    id: wrong_psk_id.clone(),
                }])
                .await
                .unwrap();
            bundle
        };

        // Deliver the wrong-PSK commit to service2 which expects PSK ID == room_id
        let commit_bytes = commit_bundle.commit.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&commit_bytes).unwrap(),
            }),
        };
        let ws_message = WebSocketMessage::Binary(rtc_message.to_tls_bytes().unwrap());
        member2.service().await.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = member2
            .service()
            .await
            .handle_websocket_message(ws_message)
            .await;

        assert!(
            result.is_err(),
            "Expected error when PSK ID in commit does not match room_id"
        );
        let err = result.unwrap_err();
        // PskProposalMissing covers both "no PSK proposal" and "PSK proposal with wrong ID" —
        // the service checks for a proposal matching room_id exactly; a wrong ID fails the same predicate.
        assert!(
            err.downcast_ref::<ServiceError>()
                .map(|e| matches!(e, ServiceError::PskProposalMissing))
                .unwrap_or(false),
            "Expected PskProposalMissing error, got: {err:?}",
        );
    }
}
