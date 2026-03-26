use std::sync::Arc;

use mls_trait::MlsError;
use proton_meet_macro::async_trait_with_mock;
use proton_meet_mls::{kv::MemKv, MlsGroup};
use tokio::sync::RwLock;

/// Port for MLS group storage operations
///
/// Note: Uses concrete type `MlsGroup<MemKv>` instead of trait object because
/// `MlsGroupTrait` is not object-safe (not dyn compatible).
#[async_trait_with_mock]
pub trait MlsStorePort: Send + Sync {
    async fn get_group(&self, room_id: &str)
        -> Result<Arc<RwLock<MlsGroup<MemKv>>>, anyhow::Error>;

    async fn get_group_epoch(&self, room_id: &str) -> Result<u64, anyhow::Error>;

    async fn save_group(
        &self,
        room_id: &str,
        group: Arc<RwLock<MlsGroup<MemKv>>>,
    ) -> Result<(), MlsError>;

    async fn remove_group(&self, room_id: &str) -> Result<(), MlsError>;
}
