use proton_meet_crypto::CryptoError;

#[derive(Debug, thiserror::Error)]
pub enum ChatError {
    #[error("Proton crypto error: {0}")]
    CryptoError(#[from] CryptoError),

    #[error("Invalid data format: {0}")]
    InvalidDataFormat(String),

    #[error("Serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),

    #[error("Key not found for index: {0}")]
    KeyNotFound(u32),

    #[error("No current key available")]
    NoCurrentKey,

    #[error("History is empty")]
    EmptyHistory,

    #[error("UTF-8 conversion error: {0}")]
    Utf8ConversionError(String),
}
