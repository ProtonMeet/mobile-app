use crate::infra::storage::error::StorageError;
use proton_meet_macro::async_trait_with_mock;

/// Result type alias for secure store operations
pub type SecureStoreResult<T> = std::result::Result<T, StorageError>;

/// Port for secure key-value storage operations
///
/// **Note**: This port is not currently in use, but is designed for future integration
/// with platform-native secure storage (e.g., iOS Keychain, Android Keystore).
/// Using this port abstraction instead of directly using Rust secure storage libraries
/// allows implementations to leverage platform-specific security features such as
/// biometric authentication, hardware-backed encryption, and secure enclave integration.
///
/// This is an infrastructure port (not a domain requirement).
/// It abstracts secure storage, allowing different implementations
/// for WASM and native platforms.
///
/// # Examples
///
/// '''rust
/// use crate::infra::ports::SecureStore;
///
/// async fn example(store: &dyn SecureStore) {
///     store.put("key", "value").await?;
///     let value = store.get("key").await?;
/// }
/// ''' no_run
#[async_trait_with_mock]
pub trait SecureStore: Send + Sync {
    /// Gets a value from secure storage by key
    ///
    /// # Arguments
    /// * `key` - The key to retrieve the value for
    ///
    /// # Returns
    /// * `Ok(Some(value))` if the key exists
    /// * `Ok(None)` if the key does not exist
    /// * `Err(StorageError)` if an error occurred
    async fn get(&self, key: &str) -> SecureStoreResult<Option<String>>;

    /// Puts a value into secure storage with the given key
    ///
    /// # Arguments
    /// * `key` - The key to store the value under
    /// * `value` - The value to store
    ///
    /// # Returns
    /// * `Ok(())` if successful
    /// * `Err(StorageError)` if an error occurred
    async fn put(&self, key: &str, value: &str) -> SecureStoreResult<()>;

    /// Saves a value into secure storage (alias for put)
    ///
    /// # Arguments
    /// * `key` - The key to store the value under
    /// * `value` - The value to store
    ///
    /// # Returns
    /// * `Ok(())` if successful
    /// * `Err(StorageError)` if an error occurred
    async fn save(&self, key: &str, value: &str) -> SecureStoreResult<()> {
        self.put(key, value).await
    }

    /// Removes a value from secure storage by key
    ///
    /// # Arguments
    /// * `key` - The key to remove
    ///
    /// # Returns
    /// * `Ok(())` if successful
    /// * `Err(StorageError)` if an error occurred
    async fn remove(&self, key: &str) -> SecureStoreResult<()>;

    /// Checks if a key exists in secure storage
    ///
    /// # Arguments
    /// * `key` - The key to check
    ///
    /// # Returns
    /// * `Ok(true)` if the key exists
    /// * `Ok(false)` if the key does not exist
    /// * `Err(StorageError)` if an error occurred
    async fn contains_key(&self, key: &str) -> SecureStoreResult<bool> {
        match self.get(key).await {
            Ok(Some(_)) => Ok(true),
            Ok(None) => Ok(false),
            Err(e) => Err(e),
        }
    }

    /// Clears all values from secure storage
    ///
    /// # Returns
    /// * `Ok(())` if successful
    /// * `Err(StorageError)` if an error occurred
    async fn clear(&self) -> SecureStoreResult<()>;
}
