use crate::errors::http_client::HttpClientError;

#[derive(Debug, thiserror::Error)]
pub enum LoginError {
    #[error("Login failed")]
    LoginFailed(String),
    #[error("Missing two factor")]
    MissingTwoFactor,

    #[error("No user keys found")]
    NoUserKeys,
    #[error("No key salt")]
    NoKeySalt,

    #[error(transparent)]
    Unknown(#[from] anyhow::Error),
    #[error("SRP password too short")]
    SrpPasswordTooShort,
    #[error("Two factor code is invalid: {0}")]
    TwoFactorCodeInvalid(#[from] muon::Error),
    #[error(transparent)]
    SrpHashError(#[from] proton_meet_crypto::CryptoError),
    #[error(transparent)]
    HttpClientError(#[from] HttpClientError),

    #[error("repository error: {0}")]
    StorageError(#[from] crate::infra::storage::error::StorageError),
}
