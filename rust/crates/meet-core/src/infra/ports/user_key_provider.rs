use crate::infra::storage::error::StorageError;
use proton_meet_common::models::ProtonUserKey;
use proton_meet_macro::async_trait_with_mock;

/// Result type alias for user key provider operations
pub type UserKeyProviderResult<T> = std::result::Result<T, StorageError>;

/// Port for user key provider operations
///
/// This is an infrastructure port (not a domain requirement).
/// It abstracts the retrieval of user keys and passphrases,
/// allowing different implementations for WASM and native platforms.
///
/// # Examples
///
/// '''rust
/// use crate::infra::ports::UserKeyProvider;
///
/// async fn example(provider: &dyn UserKeyProvider) {
///     let key = provider.get_default_user_key("user_id".to_string()).await?;
///     let passphrase = provider.get_user_key_passphrase("user_id".to_string()).await?;
/// }
/// ''' no_run
#[async_trait_with_mock]
pub trait UserKeyProvider: Send + Sync + 'static {
    /// Fetches the default user key for a given user ID
    ///
    /// # Arguments
    /// * `user_id` - The user ID to fetch the key for
    ///
    /// # Returns
    /// * `Ok(ProtonUserKey)` if successful
    /// * `Err(StorageError)` if an error occurred
    async fn get_default_user_key(&self, user_id: String) -> UserKeyProviderResult<ProtonUserKey>;

    /// Fetches the user key passphrase for a given user ID
    ///
    /// # Arguments
    /// * `user_id` - The user ID to fetch the passphrase for
    ///
    /// # Returns
    /// * `Ok(String)` if successful
    /// * `Err(StorageError)` if an error occurred
    async fn get_user_key_passphrase(&self, user_id: String) -> UserKeyProviderResult<String>;
}
