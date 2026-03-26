use crate::infra::storage::error::StorageError;
use proton_meet_common::models::{ProtonUser, ProtonUserKey};
use proton_meet_macro::async_trait_with_mock;
use std::sync::Arc;

#[cfg(not(target_family = "wasm"))]
pub type ArcUserRepository = Arc<dyn UserRepository + Send + Sync + 'static>;
#[cfg(target_family = "wasm")]
pub type ArcUserRepository = Arc<dyn UserRepository + 'static>;

#[async_trait_with_mock]
pub trait UserRepository {
    async fn init_tables(&self, user_id: &str) -> Result<(), StorageError>;

    async fn get_user(&self, user_id: &str) -> Result<Option<ProtonUser>, StorageError>;

    async fn save_user(&self, user: &ProtonUser) -> Result<(), StorageError>;

    async fn delete_user(&self, user_id: &str) -> Result<usize, StorageError>;

    async fn save_user_keys(
        &self,
        user_id: &str,
        keys: &[ProtonUserKey],
    ) -> Result<(), StorageError>;

    async fn get_user_keys(&self, user_id: &str) -> Result<Vec<ProtonUserKey>, StorageError>;

    async fn delete_user_keys(&self, user_id: &str) -> Result<(), StorageError>;
}
