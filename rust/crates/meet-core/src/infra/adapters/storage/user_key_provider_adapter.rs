use proton_meet_common::models::ProtonUserKey;
use proton_meet_macro::async_trait;
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::infra::adapters::storage::user_key_callbacks::{
    UserKeyFetcher, UserKeyPassphraseFetcher,
};
use crate::infra::ports::user_key_provider::{UserKeyProvider, UserKeyProviderResult};
use crate::infra::storage::error::StorageError;

/// Adapter that implements UserKeyProvider port using Dart/Flutter callbacks
///
/// This adapter bridges the Rust layer to the Dart layer, which has access
/// to secure storage. It uses callbacks to request user keys and passphrases
/// from Dart when needed.
///
/// # Examples
///
/// '''rust
/// // Set up callbacks from Dart
/// let adapter = UserKeyProviderAdapter::new();
/// adapter.set_get_default_user_key_callback(callback).await;
///
/// // Use the port interface
/// let key = adapter.get_default_user_key("user_id".to_string()).await?;
/// ''' no_run
#[derive(Clone)]
pub struct UserKeyProviderAdapter {
    /// Arc-wrapped Mutex to safely manage async access to the fetch callbacks
    pub(crate) get_default_user_key_callback: Arc<Mutex<Option<Arc<UserKeyFetcher>>>>,
    pub(crate) get_user_key_passphrase_callback: Arc<Mutex<Option<Arc<UserKeyPassphraseFetcher>>>>,
}

impl Default for UserKeyProviderAdapter {
    fn default() -> Self {
        Self::new()
    }
}

impl UserKeyProviderAdapter {
    /// Creates a new `UserKeyProviderAdapter` instance
    pub fn new() -> Self {
        UserKeyProviderAdapter {
            get_default_user_key_callback: Arc::new(Mutex::new(None)),
            get_user_key_passphrase_callback: Arc::new(Mutex::new(None)),
        }
    }

    /// Sets the callback for fetching the default user key
    ///
    /// This callback will be invoked when `get_default_user_key` is called.
    /// The callback should be provided by the Dart/Flutter layer.
    pub async fn set_get_default_user_key_callback(&self, callback: Arc<UserKeyFetcher>) {
        let mut cached_callback = self.get_default_user_key_callback.lock().await;
        *cached_callback = Some(callback);
    }

    /// Sets the callback for fetching the user key passphrase
    ///
    /// This callback will be invoked when `get_user_key_passphrase` is called.
    /// The callback should be provided by the Dart/Flutter layer.
    pub async fn set_get_user_key_passphrase_callback(
        &self,
        callback: Arc<UserKeyPassphraseFetcher>,
    ) {
        let mut cached_callback = self.get_user_key_passphrase_callback.lock().await;
        *cached_callback = Some(callback);
    }

    /// Clears all user key fetch callbacks
    pub async fn clear(&self) {
        let mut cb = self.get_default_user_key_callback.lock().await;
        *cb = None;
        let mut cb = self.get_user_key_passphrase_callback.lock().await;
        *cb = None;
    }
}

#[async_trait]
impl UserKeyProvider for UserKeyProviderAdapter {
    /// Fetches the default user key for a given user ID by invoking the callback
    async fn get_default_user_key(&self, user_id: String) -> UserKeyProviderResult<ProtonUserKey> {
        let cb = self.get_default_user_key_callback.lock().await;
        if let Some(callback) = cb.as_ref() {
            let key = callback(user_id).await;
            Ok(key)
        } else {
            // Return an error if the callback is not set
            Err(StorageError::AnyHow(anyhow::anyhow!(
                "Get default user key callback not set"
            )))
        }
    }

    /// Fetches the user key passphrase for a given user ID by invoking the callback
    async fn get_user_key_passphrase(&self, user_id: String) -> UserKeyProviderResult<String> {
        let cb = self.get_user_key_passphrase_callback.lock().await;
        if let Some(callback) = cb.as_ref() {
            let passphrase = callback(user_id).await;
            Ok(passphrase)
        } else {
            // Return an error if the callback is not set
            Err(StorageError::AnyHow(anyhow::anyhow!(
                "Get user key passphrase callback not set"
            )))
        }
    }
}

#[cfg(test)]
mod tests {
    use proton_meet_macro::unified_test;

    use super::*;
    use crate::infra::ports::UserKeyProvider;

    /// Helper function to create a mock user key for testing
    fn create_mock_user_key() -> ProtonUserKey {
        ProtonUserKey {
            id: "test_key_id".to_string(),
            version: 0,
            private_key: "test_private_key".to_string(),
            recovery_secret: None,
            recovery_secret_signature: None,
            token: Some("test_token".to_string()),
            fingerprint: "test_fingerprint".to_string(),
            signature: Some("test_signature".to_string()),
            primary: 1,
            active: 1,
        }
    }

    /// Test case for fetching the default user key successfully
    #[unified_test]
    async fn test_get_default_user_key_success() {
        let adapter = UserKeyProviderAdapter::new();
        let user_id = "test_user_id".to_string();
        let mock_key = create_mock_user_key();

        let default_key_callback: Arc<UserKeyFetcher> = Arc::new(move |_| {
            let key = mock_key.clone();
            Box::pin(async move { key })
        });

        adapter
            .set_get_default_user_key_callback(default_key_callback)
            .await;

        let result = adapter.get_default_user_key(user_id.clone()).await;
        assert!(result.is_ok());
        let key = result.unwrap();
        assert_eq!(key.id, "test_key_id");
        assert_eq!(key.private_key, "test_private_key");
        assert!(key.primary == 1);
        assert!(key.active == 1);
    }

    /// Test case for fetching the user key passphrase successfully
    #[unified_test]
    async fn test_get_user_key_passphrase_success() {
        let adapter = UserKeyProviderAdapter::new();
        let user_id = "test_user_id".to_string();
        let test_passphrase = "test_passphrase_123".to_string();

        let passphrase_callback: Arc<UserKeyPassphraseFetcher> = Arc::new(move |_| {
            let passphrase = test_passphrase.clone();
            Box::pin(async move { passphrase })
        });

        adapter
            .set_get_user_key_passphrase_callback(passphrase_callback)
            .await;

        let result = adapter.get_user_key_passphrase(user_id.clone()).await;
        assert!(result.is_ok());
        let passphrase = result.unwrap();
        assert_eq!(passphrase, "test_passphrase_123");
    }

    /// Test case for error when default user key callback is not set
    #[unified_test]
    async fn test_get_default_user_key_callback_not_set() {
        let adapter = UserKeyProviderAdapter::default();
        let user_id = "test_user_id".to_string();
        let result = adapter.get_default_user_key(user_id).await;
        assert!(result.is_err());
        assert!(result
            .err()
            .unwrap()
            .to_string()
            .contains("callback not set"));
    }

    /// Test case for error when passphrase callback is not set
    #[unified_test]
    async fn test_get_user_key_passphrase_callback_not_set() {
        let adapter = UserKeyProviderAdapter::default();
        let user_id = "test_user_id".to_string();
        let result = adapter.get_user_key_passphrase(user_id).await;
        assert!(result.is_err());
        assert!(result
            .err()
            .unwrap()
            .to_string()
            .contains("callback not set"));
    }

    /// Test case for clearing all callbacks
    #[unified_test]
    async fn test_clear_callbacks() {
        let adapter = UserKeyProviderAdapter::new();
        let user_id = "test_id".to_string();
        let mock_key = create_mock_user_key();

        let default_key_callback: Arc<UserKeyFetcher> = Arc::new(move |_| {
            let key = mock_key.clone();
            Box::pin(async move { key })
        });

        adapter
            .set_get_default_user_key_callback(default_key_callback)
            .await;

        let result = adapter.get_default_user_key(user_id.clone()).await;
        assert!(result.is_ok());
        let key = result.unwrap();
        assert_eq!(key.id, "test_key_id");

        // Clear the callbacks
        adapter.clear().await;

        // After clearing, the callbacks should return an error
        let result = adapter.get_default_user_key(user_id.clone()).await;
        assert!(result.is_err());

        let result = adapter.get_user_key_passphrase(user_id).await;
        assert!(result.is_err());
    }
}
