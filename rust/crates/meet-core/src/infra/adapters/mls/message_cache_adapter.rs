use std::sync::Arc;

use mls_types::MlsMessage;
use proton_meet_macro::async_trait;
use tokio::sync::Mutex;

use crate::domain::mls::ports::MessageCachePort;
use crate::infra::message_cache::{CachedMessageType, CachedMlsMessage, MlsMessageCache};

/// Adapter that implements MessageCachePort using existing MlsMessageCache
pub struct MessageCacheAdapter {
    message_cache: Arc<Mutex<MlsMessageCache>>,
}

impl MessageCacheAdapter {
    pub fn new(message_cache: Arc<Mutex<MlsMessageCache>>) -> Self {
        Self { message_cache }
    }
}

#[async_trait]
impl MessageCachePort for MessageCacheAdapter {
    async fn cache_message(
        &self,
        room_id: &str,
        epoch: u64,
        message_type: CachedMessageType,
        message: MlsMessage,
    ) -> Result<(), anyhow::Error> {
        let mut guard = self.message_cache.lock().await;
        guard.cache_message(room_id.to_string(), epoch, message_type, message);
        Ok(())
    }

    async fn get_cached_messages(
        &self,
        room_id: &str,
        epoch: u64,
    ) -> Result<Option<Vec<(CachedMessageType, CachedMlsMessage)>>, anyhow::Error> {
        let guard = self.message_cache.lock().await;
        Ok(guard.get_messages_for_epoch(room_id, epoch))
    }

    async fn remove_processed_messages(
        &self,
        room_id: &str,
        epoch: u64,
    ) -> Result<(), anyhow::Error> {
        let mut guard = self.message_cache.lock().await;
        guard.remove_processed_messages(room_id, epoch);
        Ok(())
    }
}
