use std::cmp::Ordering;
use std::sync::Arc;

use mls_trait::{types::ReceivedMessage, MlsGroupTrait};
use mls_types::MlsMessage;
use tracing;

use crate::domain::mls::ports::{MessageCachePort, MlsStorePort, StateRepositoryPort};
use crate::errors::service::ServiceError;
use crate::infra::message_cache::CachedMessageType;

/// Core MLS message processing service
///
/// This service handles MLS commit and proposal processing logic
/// without depending on WebSocket or other infrastructure concerns.
pub struct MlsMessageService {
    mls_store: Arc<dyn MlsStorePort>,
    message_cache: Arc<dyn MessageCachePort>,
    state_repository: Arc<dyn StateRepositoryPort>,
}

impl MlsMessageService {
    pub fn new(
        mls_store: Arc<dyn MlsStorePort>,
        message_cache: Arc<dyn MessageCachePort>,
        state_repository: Arc<dyn StateRepositoryPort>,
    ) -> Self {
        Self {
            mls_store,
            message_cache,
            state_repository,
        }
    }

    /// Process a commit message
    ///
    /// Returns Ok(()) if the commit was processed successfully or skipped (old epoch).
    /// Returns Err if there was an error processing the commit.
    pub async fn process_commit(
        &self,
        commit_message: MlsMessage,
        room_id: &str,
    ) -> Result<(), anyhow::Error> {
        let epoch_of_commit = commit_message
            .epoch()
            .ok_or(anyhow::anyhow!("Expected commit to have an epoch"))?;

        let mls_group_epoch = self.mls_store.get_group_epoch(room_id).await?;

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
                // Return ok to avoid showing error on client side since we already handle it
                return Ok(());
            }
            Ordering::Equal => {}
            Ordering::Greater => {
                tracing::info!(
                    "Received commit message with future epoch. epoch: {:?}",
                    epoch_of_commit
                );
                self.cache_commit_message(room_id, commit_message).await?;
                // Return ok to avoid showing error on client side since we already handle it
                return Ok(());
            }
        }

        // Get the MLS group and decrypt the commit message
        let mls_group = self.mls_store.get_group(room_id).await?;
        let mut group_guard = mls_group.write().await;

        let result = group_guard.decrypt_message(commit_message.clone()).await;
        let (received_message, _reinit) = match result {
            Ok((received_message, reinit)) => (received_message, reinit),
            Err(e) => {
                tracing::error!("Failed to decrypt commit message: {:?}", e);
                return Err(anyhow::Error::from(e));
            }
        };

        match received_message {
            ReceivedMessage::Commit { .. } => {}
            ReceivedMessage::Error(mls_types::MlsTypesError::MlsClientError(
                mls_rs::client::MlsError::ProposalNotFound,
            )) => {
                tracing::error!("Proposal not found in commit message");
                self.cache_commit_message(room_id, commit_message).await?;
                return Err(anyhow::Error::from(ServiceError::ProposalNotFound));
            }
            _ => {
                tracing::error!("Received message is not a commit: {:?}", received_message);
                return Err(anyhow::Error::from(ServiceError::InvalidMlsMessageType));
            }
        }

        tracing::info!("Commit message processed. epoch: {:?}", group_guard.epoch());

        // Update state to success
        self.state_repository
            .set_mls_state(
                room_id,
                crate::service::service_state::MlsGroupState::Success,
            )
            .await?;

        Ok(())
    }

    /// Process a proposal message
    ///
    /// Returns Ok(()) if the proposal was processed successfully or queued.
    /// Returns Err if there was an error processing the proposal.
    pub async fn process_proposal(
        &self,
        proposal_message: MlsMessage,
        room_id: &str,
    ) -> Result<(), anyhow::Error> {
        let epoch_of_proposal = proposal_message
            .epoch()
            .ok_or(anyhow::anyhow!("Expected proposal to have an epoch"))?;

        let mls_group_epoch = self.mls_store.get_group_epoch(room_id).await?;

        match epoch_of_proposal.cmp(&mls_group_epoch) {
            Ordering::Less => {
                tracing::info!(
                    "Received proposal message with old epoch. proposal epoch: {:?}, group epoch: {:?}",
                    epoch_of_proposal,
                    mls_group_epoch
                );
                return Err(ServiceError::OldEpochProposal.into());
            }
            Ordering::Equal => {}
            Ordering::Greater => {
                tracing::info!(
                    "Received proposal message with future epoch. proposal epoch: {:?}, group epoch: {:?}",
                    epoch_of_proposal,
                    mls_group_epoch
                );
                self.cache_proposal_message(room_id, proposal_message)
                    .await?;
                return Err(ServiceError::FutureEpochProposal.into());
            }
        }

        // Get the MLS group and decrypt the proposal message
        let mls_group = self.mls_store.get_group(room_id).await?;
        let mut group_guard = mls_group.write().await;

        let (received_message, _) = group_guard.decrypt_message(proposal_message).await?;
        match received_message {
            ReceivedMessage::Proposal => {
                tracing::debug!(
                    "Received proposal is processed. epoch: {:?}",
                    epoch_of_proposal
                );
            }
            _ => {
                #[cfg(debug_assertions)]
                tracing::error!("Received message is not a proposal: {:?}", received_message);
                return Err(ServiceError::ProposalDecryptionFailed.into());
            }
        }

        Ok(())
    }

    /// Cache a commit message for future processing
    pub async fn cache_commit_message(
        &self,
        room_id: &str,
        commit_message: MlsMessage,
    ) -> Result<(), anyhow::Error> {
        let epoch = commit_message
            .epoch()
            .ok_or(anyhow::anyhow!("Expected commit to have an epoch"))?;
        self.message_cache
            .cache_message(room_id, epoch, CachedMessageType::Commit, commit_message)
            .await?;
        Ok(())
    }

    /// Cache a proposal message for future processing
    pub async fn cache_proposal_message(
        &self,
        room_id: &str,
        proposal_message: MlsMessage,
    ) -> Result<(), anyhow::Error> {
        let epoch = proposal_message
            .epoch()
            .ok_or(anyhow::anyhow!("Expected proposal to have an epoch"))?;
        self.message_cache
            .cache_message(
                room_id,
                epoch,
                CachedMessageType::Proposal,
                proposal_message,
            )
            .await?;
        Ok(())
    }

    /// Get cached messages for a specific epoch
    pub async fn get_cached_messages(
        &self,
        room_id: &str,
        epoch: u64,
    ) -> Result<
        Option<
            Vec<(
                CachedMessageType,
                crate::infra::message_cache::CachedMlsMessage,
            )>,
        >,
        anyhow::Error,
    > {
        self.message_cache.get_cached_messages(room_id, epoch).await
    }
}
