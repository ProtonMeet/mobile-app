use proton_meet_macro::async_trait_with_mock;

use crate::domain::user::models::UserId;

#[derive(Debug, thiserror::Error)]
pub enum KeyPackageError {
    #[error("Mls client not found")]
    MlsClientNotFound,
    #[error("Failed to generate key package")]
    FailedToGenerateKeyPackage,
    #[error("Mls store error: {0}")]
    MlsStoreError(String),
    #[error("Mls error: {0}")]
    MlsError(#[from] mls_trait::MlsError),
    #[error("Data serialization error: {0}")]
    DataSerializationError(#[from] mls_rs_codec::Error),
}

#[async_trait_with_mock]
pub trait KeyPackagePort: Send + Sync {
    async fn new_key_package(&self, user_id: &UserId) -> Result<Vec<u8>, KeyPackageError>;
}
