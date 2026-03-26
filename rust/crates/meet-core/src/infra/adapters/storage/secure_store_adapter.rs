use proton_meet_macro::async_trait;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::infra::ports::secure_store::{SecureStore, SecureStoreResult};

/// In-memory adapter implementation of SecureStore port
///
/// This adapter provides an in-memory implementation of SecureStore,
/// useful for testing and development.
///
/// # Examples
///
/// '''rust
/// use crate::infra::adapters::storage::InMemorySecureStoreAdapter;
/// use crate::infra::ports::SecureStore;
///
/// #[tokio::test]
/// async fn test_example() {
///     let store = InMemorySecureStoreAdapter::new();
///     store.put("key", "value").await.unwrap();
///     assert_eq!(store.get("key").await.unwrap(), Some("value".to_string()));
/// }
/// ''' no_run
#[derive(Clone)]
pub struct InMemorySecureStoreAdapter {
    data: Arc<Mutex<HashMap<String, String>>>,
}

impl InMemorySecureStoreAdapter {
    /// Creates a new in-memory secure store adapter
    pub fn new() -> Self {
        Self {
            data: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

impl Default for InMemorySecureStoreAdapter {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl SecureStore for InMemorySecureStoreAdapter {
    async fn get(&self, key: &str) -> SecureStoreResult<Option<String>> {
        let data = self.data.lock().await;
        Ok(data.get(key).cloned())
    }

    async fn put(&self, key: &str, value: &str) -> SecureStoreResult<()> {
        let mut data = self.data.lock().await;
        data.insert(key.to_string(), value.to_string());
        Ok(())
    }

    async fn remove(&self, key: &str) -> SecureStoreResult<()> {
        let mut data = self.data.lock().await;
        data.remove(key);
        Ok(())
    }

    async fn clear(&self) -> SecureStoreResult<()> {
        let mut data = self.data.lock().await;
        data.clear();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use proton_meet_macro::unified_test;

    use super::*;
    use crate::infra::ports::SecureStore;

    #[unified_test]
    async fn test_get_put_remove() {
        let store = InMemorySecureStoreAdapter::new();

        // Test put
        assert!(store.put("key1", "value1").await.is_ok());

        // Test get
        let value = store.get("key1").await.unwrap();
        assert_eq!(value, Some("value1".to_string()));

        // Test remove
        assert!(store.remove("key1").await.is_ok());

        // Verify removed
        let value = store.get("key1").await.unwrap();
        assert_eq!(value, None);
    }

    #[unified_test]
    async fn test_contains_key() {
        let store = InMemorySecureStoreAdapter::new();

        assert!(!store.contains_key("key1").await.unwrap());
        store.put("key1", "value1").await.unwrap();
        assert!(store.contains_key("key1").await.unwrap());
    }

    #[unified_test]
    async fn test_clear() {
        let store = InMemorySecureStoreAdapter::new();

        store.put("key1", "value1").await.unwrap();
        store.put("key2", "value2").await.unwrap();

        assert!(store.contains_key("key1").await.unwrap());
        assert!(store.contains_key("key2").await.unwrap());

        store.clear().await.unwrap();

        assert!(!store.contains_key("key1").await.unwrap());
        assert!(!store.contains_key("key2").await.unwrap());
    }

    #[unified_test]
    async fn test_save_alias() {
        let store = InMemorySecureStoreAdapter::new();

        assert!(store.save("key1", "value1").await.is_ok());
        let value = store.get("key1").await.unwrap();
        assert_eq!(value, Some("value1".to_string()));
    }

    #[unified_test]
    async fn test_get_put_remove_wasm() {
        let store = InMemorySecureStoreAdapter::new();

        assert!(store.put("key1", "value1").await.is_ok());
        let value = store.get("key1").await.unwrap();
        assert_eq!(value, Some("value1".to_string()));

        assert!(store.remove("key1").await.is_ok());
        let value = store.get("key1").await.unwrap();
        assert_eq!(value, None);
    }
}
