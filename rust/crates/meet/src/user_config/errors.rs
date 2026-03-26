#[derive(Debug, thiserror::Error)]
pub enum UserConfigError {
    #[error("Failed to save config")]
    SaveConfigError,
    #[error("Failed to read config")]
    ReadConfigError,
}
