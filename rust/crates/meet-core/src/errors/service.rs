#[derive(Debug, thiserror::Error)]
pub enum ServiceError {
    #[error("Received commit message with old epoch")]
    OldEpochCommit,
    #[error("Received commit message with future epoch")]
    FutureEpochCommit,
    #[error("Received proposal message with old epoch")]
    OldEpochProposal,
    #[error("Received proposal message with future epoch")]
    FutureEpochProposal,
    #[error("Proposal not found in commit message")]
    ProposalNotFound,
    #[error("Invalid MLS message type")]
    InvalidMlsMessageType,
    /// Returned when an incoming commit does not contain a PSK proposal with the
    /// expected ID (`room_id.as_bytes()`). Covers both the case where no PSK proposal
    /// is present at all, and the case where one is present but with the wrong ID.
    #[error("Commit is missing required PSK proposal")]
    PskProposalMissing,
    #[error("Proposal decryption failed")]
    ProposalDecryptionFailed,

    #[error("User not found")]
    UserNotFound,
    #[error("User private keys not found")]
    UserPrivateKeysNotFound,
    #[error("Private key passphrase not found")]
    PrivateKeyPassphraseNotFound,
    #[error("Address ID is required")]
    AddressIdRequired,

    #[error("repository error: {0}")]
    StorageError(#[from] crate::infra::storage::error::StorageError),
    #[error("http client error: {0}")]
    HttpClientError(#[from] crate::errors::http_client::HttpClientError),
    #[error("login error: {0}")]
    LoginError(#[from] crate::errors::login::LoginError),
    #[error("crypto error: {0}")]
    CryptoError(#[from] proton_meet_crypto::CryptoError),

    /// create meeting errors
    #[error("Start time is required for recurring meetings")]
    StartTimeRequired,
}
