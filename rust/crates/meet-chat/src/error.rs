#[derive(Debug, thiserror::Error)]
pub enum ChatError {
    #[error("invalid message id: {0}")]
    InvalidMessageId(String),
    #[error("emoji must be a single grapheme cluster")]
    InvalidEmoji,
    #[error("invalid MIMI content: {0}")]
    InvalidMimiContent(String),
    #[error("legacy envelope parse error: {0}")]
    LegacyEnvelope(String),
    #[error("unsupported media type: {0}")]
    UnsupportedMediaType(String),
    #[error("reaction removal author mismatch")]
    ReactionAuthorMismatch,
    #[error("serialization error: {0}")]
    SerializationError(#[from] serde_json::Error),
    #[error("UTF-8 conversion error: {0}")]
    Utf8ConversionError(#[from] std::str::Utf8Error),
}
