
#[derive(Debug, thiserror::Error)]
pub enum AccessTokenError {
    #[error("Invalid API Key or Secret Key")]
    InvalidKeys,
    // #[error("Invalid environment")]
    // InvalidEnv(#[from] env::VarError),
    #[error("invalid claims: {0}")]
    InvalidClaims(&'static str),

    #[error("failed to encode jwt")]
    Encoding(#[from] jsonwebtoken::errors::Error),
}
