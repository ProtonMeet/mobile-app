use std::borrow::Borrow;
use std::hash::Hash;
use std::{collections::HashMap, sync::Arc};

use kv::MemKv;
pub use mls_trait::MlsClientTrait;
pub use mls_trait::{
    CommitBundle, CommonMlsGroupConfig, MlsClient, MlsClientConfig, MlsGroup, MlsGroupConfig,
    MlsGroupTrait,
};
pub use mls_types::CipherSuite;
use tokio::sync::RwLock;

pub mod kv;
pub mod mls;

/// Single account MLS group map
type GroupMap = HashMap<String, Arc<RwLock<MlsGroup<MemKv>>>>;
/// Single identity MLS client map
type ClientMap = HashMap<CipherSuite, MlsClient<MemKv>>;

/// MLS store for the entire account.
///
/// Will store all the identities mls clients and groups
pub struct MlsStore {
    /// Map of each of the account's identity to the available MLS clients
    /// indexed by ciphersuites
    pub clients: HashMap<String, ClientMap>,
    /// The account active MLS groups
    pub group_map: GroupMap,
    /// Global client config
    pub config: MlsClientConfig,
}

#[derive(Debug, thiserror::Error)]
pub enum MlsStoreError {
    #[error("Mls client not found")]
    MlsClientNotFound,
    #[error("Mls group not found")]
    MlsGroupNotFound,
}

impl MlsStore {
    /// Retrieves the MLS client of the given `user_id` and `ciphersuite`
    pub fn find_client(
        &self,
        user_id: &String,
        cs: &CipherSuite,
    ) -> Result<&MlsClient<MemKv>, MlsStoreError> {
        self.clients
            .get(user_id)
            .and_then(|m| m.get(cs))
            .ok_or(MlsStoreError::MlsClientNotFound)
    }

    pub fn find_group<Q>(&self, room_id: &Q) -> Result<Arc<RwLock<MlsGroup<MemKv>>>, MlsStoreError>
    where
        Q: Hash + Eq + ?Sized,
        String: Borrow<Q>,
    {
        self.group_map
            .get(room_id)
            .cloned()
            .ok_or(MlsStoreError::MlsGroupNotFound)
    }
}
