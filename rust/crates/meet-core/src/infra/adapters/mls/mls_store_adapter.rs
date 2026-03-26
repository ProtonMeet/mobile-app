use std::sync::Arc;

use mls_trait::{MlsError, MlsGroupTrait};
use proton_meet_macro::async_trait;
use proton_meet_mls::{kv::MemKv, MlsGroup, MlsStore};
use tokio::sync::RwLock;

use crate::domain::mls::ports::MlsStorePort;

/// Adapter that implements MlsStorePort using existing MlsStore
pub struct MlsStoreAdapter {
    mls_store: Arc<RwLock<MlsStore>>,
}

impl MlsStoreAdapter {
    pub fn new(mls_store: Arc<RwLock<MlsStore>>) -> Self {
        Self { mls_store }
    }
}

#[async_trait]
impl MlsStorePort for MlsStoreAdapter {
    async fn get_group(
        &self,
        room_id: &str,
    ) -> Result<Arc<RwLock<MlsGroup<MemKv>>>, anyhow::Error> {
        let store = self.mls_store.read().await;
        let group = store
            .group_map
            .get(room_id)
            .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
            .clone();
        Ok(group)
    }

    async fn get_group_epoch(&self, room_id: &str) -> Result<u64, anyhow::Error> {
        let store = self.mls_store.read().await;
        let mls_group = store
            .group_map
            .get(room_id)
            .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
            .read()
            .await;
        Ok(*mls_group.epoch())
    }

    async fn save_group(
        &self,
        room_id: &str,
        group: Arc<RwLock<MlsGroup<MemKv>>>,
    ) -> Result<(), MlsError> {
        let mut store = self.mls_store.write().await;
        store.group_map.insert(room_id.to_string(), group);
        Ok(())
    }

    async fn remove_group(&self, room_id: &str) -> Result<(), MlsError> {
        let mut store = self.mls_store.write().await;
        store.group_map.remove(room_id);
        Ok(())
    }
}
