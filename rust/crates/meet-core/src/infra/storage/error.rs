#[derive(Debug, thiserror::Error)]
pub enum StorageError {
    #[error("Failed to lock db cache")]
    FailedToLockDbCache,
    #[error("Database Error: `{source}`")]
    Db {
        #[cfg(target_family = "wasm")]
        source: idb::Error,
        #[cfg(not(target_family = "wasm"))]
        source: rusqlite::Error,
    },
    #[error("Ser/De Error: `{0}`")]
    Serde(String),
    #[error("Not Found: `{table}` with key `{key}`")]
    NotFound { table: String, key: String },
    #[error("Database not found")]
    DbNotFound { name: String },

    #[error("Database name cannot be empty")]
    DatabaseNameEmpty,
    #[error("Database name contains only invalid characters")]
    DatabaseNameInvalidCharacters,

    #[error("Failed to open file: {0}")]
    FailedOpenFile(#[from] std::io::Error),

    #[error("Anyhow other error: {0}")]
    AnyHow(#[from] anyhow::Error),
}

/// rclock mutex lock error
impl<T> From<std::sync::PoisonError<T>> for StorageError {
    fn from(_: std::sync::PoisonError<T>) -> Self {
        StorageError::FailedToLockDbCache
    }
}

#[cfg(target_family = "wasm")]
impl From<idb::Error> for StorageError {
    fn from(error: idb::Error) -> Self {
        StorageError::Db { source: error }
    }
}

#[cfg(not(target_family = "wasm"))]
impl From<rusqlite::Error> for StorageError {
    fn from(error: rusqlite::Error) -> Self {
        StorageError::Db { source: error }
    }
}

#[cfg(not(target_family = "wasm"))]
impl From<serde_json::Error> for StorageError {
    fn from(value: serde_json::Error) -> Self {
        Self::Serde(value.to_string())
    }
}

#[cfg(target_family = "wasm")]
impl From<serde_wasm_bindgen::Error> for StorageError {
    fn from(value: serde_wasm_bindgen::Error) -> Self {
        Self::Serde(value.to_string())
    }
}

// Explicitly mark that StorageError shouldn't be used across threads in WASM
#[cfg(target_family = "wasm")]
unsafe impl Send for StorageError {}

#[cfg(target_family = "wasm")]
unsafe impl Sync for StorageError {}
