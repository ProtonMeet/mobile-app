use mls_types::MlsMessage;
use proton_meet_macro::async_trait_with_mock;

use crate::infra::message_cache::{CachedMessageType, CachedMlsMessage};

/// Port for message caching operations
#[async_trait_with_mock]
pub trait MessageCachePort: Send + Sync {
    async fn cache_message(
        &self,
        room_id: &str,
        epoch: u64,
        message_type: CachedMessageType,
        message: MlsMessage,
    ) -> Result<(), anyhow::Error>;

    async fn get_cached_messages(
        &self,
        room_id: &str,
        epoch: u64,
    ) -> Result<Option<Vec<(CachedMessageType, CachedMlsMessage)>>, anyhow::Error>;

    async fn remove_processed_messages(
        &self,
        room_id: &str,
        epoch: u64,
    ) -> Result<(), anyhow::Error>;
}
