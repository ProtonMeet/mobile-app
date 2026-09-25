use std::sync::Arc;

use mls_types::MlsMessage;

use crate::domain::mls::ports::MessageCachePort;
use crate::infra::message_cache::CachedMessageType;

/// Core MLS message processing service
///
/// This service handles MLS commit and proposal processing logic
/// without depending on WebSocket or other infrastructure concerns.
pub struct MlsMessageService {
    message_cache: Arc<dyn MessageCachePort>,
}

impl MlsMessageService {
    pub fn new(message_cache: Arc<dyn MessageCachePort>) -> Self {
        Self { message_cache }
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
            .await;
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
            .await;
        Ok(())
    }
}
