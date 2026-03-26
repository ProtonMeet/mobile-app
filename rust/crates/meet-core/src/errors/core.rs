//! Error types for the meet-core crate
//!
//! This module defines the primary error type [`MeetCoreError`] that unifies all possible
//! errors that can occur in the meet-core library, providing better error handling and
//! more informative error messages to consumers.

use std::error::Error;

#[cfg(target_family = "wasm")]
use wasm_bindgen::prelude::*;

use crate::errors::http_client::HttpClientError;

/// The primary error type for the meet-core crate.
///
/// This enum represents all possible errors that can occur during meet-core operations,
/// providing a unified interface for error handling across different layers of the application.
// #[derive(Debug, Error)]
#[derive(Debug, thiserror::Error)]
pub enum MeetCoreError {
    // Authentication and User errors
    #[error("Authentication failed: {message}")]
    AuthenticationFailed { message: String },

    #[error("No active user")]
    NoActiveUser,

    #[error("No user keys found")]
    NoUserKeys,

    #[error("No key salt")]
    NoKeySalt,

    #[error("No primary address found")]
    NoPrimaryAddress,

    #[error("Livekit access token not found")]
    LivekitAccessTokenNotFound,

    #[error("Livekit websocket url not found")]
    LivekitWebsocketUrlNotFound,

    #[error("Two-factor authentication required")]
    MissingTwoFactor,

    #[error("Two-factor code is invalid: {message}")]
    TwoFactorCodeInvalid { message: String },

    #[error("Password too short for SRP authentication")]
    PasswordTooShort,

    // Network and Communication errors
    #[error("HTTP request failed: {message}")]
    HttpError { message: String },

    #[error("WebSocket connection failed: {message}")]
    WebSocketError { message: String },

    #[error("Network timeout occurred")]
    NetworkTimeout,

    #[error("Invalid URL: {url}")]
    InvalidUrl { url: String },

    #[error("MLS protocol error: {message}")]
    MlsProtocolError { message: String },

    #[error("MLS spec error: {message}")]
    MlsSpecError { message: String },

    #[error("Participant not found")]
    ParticipantNotFound,

    #[error("Failed to join room: {room_id}, reason: {reason}")]
    RoomJoinFailed { room_id: String, reason: String },

    // Storage and Database errors
    #[error("Database operation failed: {operation}")]
    DatabaseError { operation: String },

    #[error("Data serialization failed: {context}")]
    SerializationError { context: String },

    #[error("Data not found in storage: {key}")]
    DataNotFound { key: String },

    // Cryptographic errors
    #[error("Cryptographic operation failed: {operation}")]
    CryptographicError { operation: String },

    #[error("Key generation failed")]
    KeyGenerationFailed,

    #[error("Signature verification failed")]
    SignatureVerificationFailed,

    #[error("Internal error: {message} - {details:?}")]
    InternalError {
        message: String,
        details: Option<String>,
    },

    // Validation errors
    #[error("Invalid input: {field} - {reason}")]
    InvalidInput { field: String, reason: String },

    #[error("HttpClientError: {message} - {details:?}")]
    HttpClientError {
        status: u16,
        details: Option<String>,
        message: String,
    },

    #[error("AuthStoreError: {message}")]
    AuthStoreError { message: String },

    #[error("MLS server version not supported")]
    MlsServerVersionNotSupported,

    #[error("Max retries reached")]
    MaxRetriesReached,

    #[error("StorageError: {message} - {details:?}")]
    StorageError {
        message: String,
        details: Option<String>,
    },

    #[error("ServiceError: {message} - {details:?}")]
    ServiceError {
        message: String,
        details: Option<String>,
    },

    #[error("Time drift error")]
    TimeDriftError,

    #[error("Meeting is locked. Please try again later.")]
    MeetingLocked,

    #[error(transparent)]
    UuidError(#[from] uuid::Error),

    #[error("User is not RoomAdmin")]
    NotRoomAdmin,
}

impl From<crate::infra::storage::error::StorageError> for MeetCoreError {
    fn from(error: crate::infra::storage::error::StorageError) -> Self {
        Self::StorageError {
            message: error.to_string(),
            details: Some(format!("{:?}", error.source())),
        }
    }
}

impl From<crate::errors::service::ServiceError> for MeetCoreError {
    fn from(error: crate::errors::service::ServiceError) -> Self {
        if let Some(inner_error) = find_error_type::<HttpClientError>(&error) {
            match inner_error {
                HttpClientError::MeetingLocked => {
                    return Self::MeetingLocked;
                }
                HttpClientError::ErrorCode(_, error) => {
                    return Self::HttpClientError {
                        status: error.code,
                        message: error.error.clone(),
                        details: Some(format!("{:?}", error.details)),
                    };
                }
                _ => {}
            }
        }

        Self::ServiceError {
            message: error.to_string(),
            details: Some(format!("{:?}", error.source())),
        }
    }
}

// impl MeetCoreError {
//     /// Creates a new authentication failed error
//     pub fn auth_failed<S: Into<String>>(message: S) -> Self {
//         Self::AuthenticationFailed {
//             message: message.into(),
//         }
//     }

//     /// Creates a new HTTP error
//     pub fn http_error<S: Into<String>>(message: S) -> Self {
//         Self::HttpError {
//             message: message.into(),
//         }
//     }

//     /// Creates a new WebSocket error
//     pub fn websocket_error<S: Into<String>>(message: S) -> Self {
//         Self::WebSocketError {
//             message: message.into(),
//         }
//     }

//     /// Creates a new database error
//     pub fn database_error<S: Into<String>>(operation: S) -> Self {
//         Self::DatabaseError {
//             operation: operation.into(),
//         }
//     }

//     /// Creates a new internal error
//     pub fn internal_error<S: Into<String>>(message: S) -> Self {
//         Self::InternalError {
//             message: message.into(),
//             details: None,
//         }
//     }

//     /// Creates a new MLS protocol error
//     pub fn mls_protocol_error<S: Into<String>>(message: S) -> Self {
//         Self::MlsProtocolError {
//             message: message.into(),
//         }
//     }

//     /// Creates a new MLS spec error
//     pub fn mls_spec_error<S: Into<String>>(message: S) -> Self {
//         Self::MlsSpecError {
//             message: message.into(),
//         }
//     }
// }

// Conversion implementations for existing error types
impl From<crate::errors::login::LoginError> for MeetCoreError {
    fn from(error: crate::errors::login::LoginError) -> Self {
        match error {
            crate::errors::login::LoginError::LoginFailed(msg) => {
                Self::AuthenticationFailed { message: msg }
            }
            crate::errors::login::LoginError::SrpPasswordTooShort => Self::PasswordTooShort,
            crate::errors::login::LoginError::Unknown(e) => Self::InternalError {
                message: e.to_string(),
                details: Some(format!("{:?}", e.source())),
            },
            crate::errors::login::LoginError::SrpHashError(e) => Self::CryptographicError {
                operation: e.to_string(),
            },
            crate::errors::login::LoginError::MissingTwoFactor => Self::MissingTwoFactor,
            crate::errors::login::LoginError::TwoFactorCodeInvalid(e) => {
                Self::TwoFactorCodeInvalid {
                    message: e.to_string(),
                }
            }
            crate::errors::login::LoginError::HttpClientError(e) => Self::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: Some(format!("{:?}", e.source())),
            },
            crate::errors::login::LoginError::NoUserKeys => Self::NoUserKeys,
            crate::errors::login::LoginError::NoKeySalt => Self::NoKeySalt,
            crate::errors::login::LoginError::StorageError(e) => Self::StorageError {
                message: format!("{:?}", e.source()),
                details: Some(format!("{:?}", e.source())),
            },
        }
    }
}

// impl From<crate::infra::storage::error::StorageError> for MeetCoreError {
//     fn from(error: crate::infra::storage::error::StorageError) -> Self {
//         match error {
//             crate::infra::storage::error::StorageError::FailedToLockDbCache => {
//                 Self::InternalError {
//                     message: "Failed to lock db cache".to_string(),
//                 }
//             }
//             crate::infra::storage::error::StorageError::DbNotFound { name } => Self::DataNotFound {
//                 key: name.to_string(),
//             },
//             crate::infra::storage::error::StorageError::Db { source } => Self::DatabaseError {
//                 operation: source.to_string(),
//             },
//             crate::infra::storage::error::StorageError::Serde(msg) => {
//                 Self::SerializationError { context: msg }
//             }
//             crate::infra::storage::error::StorageError::NotFound { table, key } => {
//                 Self::DataNotFound {
//                     key: format!("{table}.{key}"),
//                 }
//             }
//             crate::infra::storage::error::StorageError::DatabaseNameEmpty => Self::InternalError {
//                 message: "Database name cannot be empty".to_string(),
//             },
//             crate::infra::storage::error::StorageError::DatabaseNameInvalidCharacters => {
//                 Self::InternalError {
//                     message: "Database name contains only invalid characters".to_string(),
//                 }
//             }
//         }
//     }
// }

//TODO:: should remove anyhow::Error
impl From<anyhow::Error> for MeetCoreError {
    fn from(error: anyhow::Error) -> Self {
        // Try to downcast to HttpClientError first
        if let Some(http_error) = error.downcast_ref::<HttpClientError>() {
            return match http_error {
                HttpClientError::MeetingLocked => Self::MeetingLocked,
                HttpClientError::ErrorCode(_, ref error_detail) => Self::HttpClientError {
                    status: error_detail.code,
                    message: error_detail.error.clone(),
                    details: Some(format!("{:?}", error_detail.details)),
                },
                _ => Self::HttpClientError {
                    status: 0,
                    message: http_error.to_string(),
                    details: None,
                },
            };
        }

        // Try to downcast to known error types first
        if let Some(login_error) = error.downcast_ref::<crate::errors::login::LoginError>() {
            return match login_error {
                crate::errors::login::LoginError::LoginFailed(msg) => Self::AuthenticationFailed {
                    message: msg.clone(),
                },
                crate::errors::login::LoginError::SrpPasswordTooShort => Self::PasswordTooShort,
                crate::errors::login::LoginError::Unknown(_) => Self::InternalError {
                    message: login_error.to_string(),
                    details: Some(format!("{:?}", login_error.source())),
                },
                crate::errors::login::LoginError::SrpHashError(e) => Self::CryptographicError {
                    operation: e.to_string(),
                },
                crate::errors::login::LoginError::MissingTwoFactor => Self::MissingTwoFactor,
                crate::errors::login::LoginError::TwoFactorCodeInvalid(e) => {
                    Self::TwoFactorCodeInvalid {
                        message: e.to_string(),
                    }
                }
                crate::errors::login::LoginError::HttpClientError(e) => Self::HttpClientError {
                    status: 0,
                    message: e.to_string(),
                    details: e.source().map(|e| format!("{:?}", e.source())),
                },
                crate::errors::login::LoginError::NoUserKeys => Self::NoUserKeys,
                crate::errors::login::LoginError::NoKeySalt => Self::NoKeySalt,
                crate::errors::login::LoginError::StorageError(e) => Self::StorageError {
                    message: e.to_string(),
                    details: Some(format!("{:?}", e.source())),
                },
            };
        }

        // if let Some(storage_error) =
        //     error.downcast_ref::<crate::infra::storage::error::StorageError>()
        // {
        //     // Prefer the source() message if present; otherwise use Display of the error itself.
        //     let fallback_msg = storage_error.to_string();
        //     let src_msg = storage_error
        //         .source()
        //         .map(|e| e.to_string())
        //         .unwrap_or(fallback_msg);

        //     return match storage_error {
        //         crate::infra::storage::error::StorageError::DatabaseNameEmpty => {
        //             Self::InternalError {
        //                 message: storage_error.source(),
        //             }
        //         }
        //         crate::infra::storage::error::StorageError::DatabaseNameInvalidCharacters => {
        //             Self::InternalError {
        //                 message: storage_error.source(),
        //             }
        //         }
        //         crate::infra::storage::error::StorageError::FailedToLockDbCache => {
        //             Self::InternalError {
        //                 message: storage_error.source() ? storage_error.source().to_string()? "Failed to lock db cache".to_string(),
        //             }
        //         }
        //         crate::infra::storage::error::StorageError::DbNotFound { name } => {
        //             Self::DataNotFound {
        //                 key: name.to_string(),
        //             }
        //         }
        //         crate::infra::storage::error::StorageError::Db { source } => Self::DatabaseError {
        //             operation: source.to_string(),
        //         },
        //         crate::infra::storage::error::StorageError::Serde(msg) => {
        //             Self::SerializationError {
        //                 context: msg.clone(),
        //             }
        //         }
        //         crate::infra::storage::error::StorageError::NotFound { table, key } => {
        //             Self::DataNotFound {
        //                 key: format!("{table}.{key}"),
        //             }
        //         }
        //     };
        // }

        // Check for specific error types in the error chain
        let error_string = error.to_string().to_lowercase();

        if error_string.contains("network") || error_string.contains("connection") {
            return Self::HttpError {
                message: error.to_string(),
            };
        }

        if error_string.contains("websocket") || error_string.contains("ws") {
            return Self::WebSocketError {
                message: error.to_string(),
            };
        }

        if error_string.contains("mls") {
            tracing::error!("MLS error: {:?}", error.source());
            return Self::MlsProtocolError {
                message: error.to_string(),
            };
        }

        if error_string.contains("database") || error_string.contains("sql") {
            return Self::DatabaseError {
                operation: error.to_string(),
            };
        }

        if error_string.contains("serializ") || error_string.contains("deserializ") {
            return Self::SerializationError {
                context: error.to_string(),
            };
        }

        // Default case
        Self::InternalError {
            message: error.to_string(),
            details: Some(format!("{:?}", error.source())),
        }
    }
}

impl From<reqwest::Error> for MeetCoreError {
    fn from(error: reqwest::Error) -> Self {
        #[cfg(not(target_family = "wasm"))]
        if error.is_timeout() {
            Self::NetworkTimeout
        } else if error.is_connect() {
            Self::HttpError {
                message: format!("Connection failed: {error}"),
            }
        } else {
            Self::HttpError {
                message: error.to_string(),
            }
        }

        #[cfg(target_family = "wasm")]
        if error.is_timeout() {
            Self::NetworkTimeout
        } else {
            Self::HttpError {
                message: error.to_string(),
            }
        }
    }
}

impl From<url::ParseError> for MeetCoreError {
    fn from(error: url::ParseError) -> Self {
        Self::InvalidUrl {
            url: error.to_string(),
        }
    }
}

impl From<base64::DecodeError> for MeetCoreError {
    fn from(error: base64::DecodeError) -> Self {
        Self::SerializationError {
            context: format!("Base64 decode error: {error}"),
        }
    }
}

impl From<serde_json::Error> for MeetCoreError {
    fn from(error: serde_json::Error) -> Self {
        Self::SerializationError {
            context: format!("JSON error: {error}"),
        }
    }
}

impl From<tls_codec::Error> for MeetCoreError {
    fn from(error: tls_codec::Error) -> Self {
        Self::SerializationError {
            context: format!("TLS encoding error: {error}"),
        }
    }
}

impl From<tokio_tungstenite_wasm::Error> for MeetCoreError {
    fn from(error: tokio_tungstenite_wasm::Error) -> Self {
        Self::WebSocketError {
            message: error.to_string(),
        }
    }
}

impl From<mls_rs_codec::Error> for MeetCoreError {
    fn from(error: mls_rs_codec::Error) -> Self {
        Self::MlsProtocolError {
            message: error.to_string(),
        }
    }
}

impl From<mls_types::MlsTypesError> for MeetCoreError {
    fn from(error: mls_types::MlsTypesError) -> Self {
        Self::MlsProtocolError {
            message: error.to_string(),
        }
    }
}

impl From<mls_spec::MlsSpecError> for MeetCoreError {
    fn from(error: mls_spec::MlsSpecError) -> Self {
        Self::MlsSpecError {
            message: error.to_string(),
        }
    }
}

impl From<mls_trait::MlsError> for MeetCoreError {
    fn from(error: mls_trait::MlsError) -> Self {
        Self::MlsProtocolError {
            message: error.to_string(),
        }
    }
}

impl From<HttpClientError> for MeetCoreError {
    fn from(error: HttpClientError) -> Self {
        match error {
            HttpClientError::MeetingLocked => Self::MeetingLocked,
            HttpClientError::ErrorCode(_, ref err) => Self::HttpClientError {
                status: err.code,
                message: err.error.clone(),
                details: Some(err.details.to_string()),
            },
            _ => Self::HttpClientError {
                status: 0,
                message: error.to_string(),
                details: None,
            },
        }
    }
}

fn find_error_type<T: 'static + Error>(error: &dyn Error) -> Option<&T> {
    let mut current_error = error;
    while let Some(source) = current_error.source() {
        if let Some(specific_error) = source.downcast_ref::<T>() {
            return Some(specific_error);
        }
        current_error = source;
    }
    None
}

// WASM-specific error enum
#[cfg(target_family = "wasm")]
#[wasm_bindgen]
pub enum MeetCoreErrorEnum {
    AuthenticationFailed,
    NoActiveUser,
    NoUserKeys,
    NoKeySalt,
    NoPrimaryAddress,
    LivekitAccessTokenNotFound,
    LivekitWebsocketUrlNotFound,
    MissingTwoFactor,
    TwoFactorCodeInvalid,
    PasswordTooShort,
    HttpError,
    WebSocketError,
    NetworkTimeout,
    InvalidUrl,
    MlsProtocolError,
    MlsSpecError,
    ParticipantNotFound,
    RoomJoinFailed,
    DatabaseError,
    SerializationError,
    DataNotFound,
    CryptographicError,
    KeyGenerationFailed,
    SignatureVerificationFailed,
    InternalError,
    InvalidInput,
    HttpClientError,
    AuthStoreError,
    MlsServerVersionNotSupported,
    MaxRetriesReached,
    StorageError,
    ServiceError,
    TimeDriftError,
    MeetingLocked,
    UuidError,
    NotRoomAdmin,
}

#[cfg(target_family = "wasm")]
impl From<MeetCoreError> for MeetCoreErrorEnum {
    fn from(error: MeetCoreError) -> Self {
        match error {
            MeetCoreError::AuthenticationFailed { .. } => Self::AuthenticationFailed,
            MeetCoreError::NoActiveUser => Self::NoActiveUser,
            MeetCoreError::NoUserKeys => Self::NoUserKeys,
            MeetCoreError::NoKeySalt => Self::NoKeySalt,
            MeetCoreError::NoPrimaryAddress => Self::NoPrimaryAddress,
            MeetCoreError::LivekitAccessTokenNotFound => Self::LivekitAccessTokenNotFound,
            MeetCoreError::LivekitWebsocketUrlNotFound => Self::LivekitWebsocketUrlNotFound,
            MeetCoreError::MissingTwoFactor => Self::MissingTwoFactor,
            MeetCoreError::TwoFactorCodeInvalid { .. } => Self::TwoFactorCodeInvalid,
            MeetCoreError::PasswordTooShort => Self::PasswordTooShort,
            MeetCoreError::HttpError { .. } => Self::HttpError,
            MeetCoreError::WebSocketError { .. } => Self::WebSocketError,
            MeetCoreError::NetworkTimeout => Self::NetworkTimeout,
            MeetCoreError::InvalidUrl { .. } => Self::InvalidUrl,
            MeetCoreError::MlsProtocolError { .. } => Self::MlsProtocolError,
            MeetCoreError::MlsSpecError { .. } => Self::MlsSpecError,
            MeetCoreError::ParticipantNotFound => Self::ParticipantNotFound,
            MeetCoreError::RoomJoinFailed { .. } => Self::RoomJoinFailed,
            MeetCoreError::DatabaseError { .. } => Self::DatabaseError,
            MeetCoreError::SerializationError { .. } => Self::SerializationError,
            MeetCoreError::DataNotFound { .. } => Self::DataNotFound,
            MeetCoreError::CryptographicError { .. } => Self::CryptographicError,
            MeetCoreError::KeyGenerationFailed => Self::KeyGenerationFailed,
            MeetCoreError::SignatureVerificationFailed => Self::SignatureVerificationFailed,
            MeetCoreError::InternalError { .. } => Self::InternalError,
            MeetCoreError::InvalidInput { .. } => Self::InvalidInput,
            MeetCoreError::HttpClientError { .. } => Self::HttpClientError,
            MeetCoreError::AuthStoreError { .. } => Self::AuthStoreError,
            MeetCoreError::MlsServerVersionNotSupported => Self::MlsServerVersionNotSupported,
            MeetCoreError::MaxRetriesReached => Self::MaxRetriesReached,
            MeetCoreError::StorageError { .. } => Self::StorageError,
            MeetCoreError::ServiceError { .. } => Self::ServiceError,
            MeetCoreError::TimeDriftError => Self::TimeDriftError,
            MeetCoreError::MeetingLocked => Self::MeetingLocked,
            MeetCoreError::UuidError(_) => Self::UuidError,
            MeetCoreError::NotRoomAdmin => Self::NotRoomAdmin,
        }
    }
}

#[cfg(target_family = "wasm")]
impl From<MeetCoreError> for JsValue {
    fn from(error: MeetCoreError) -> Self {
        let error_enum = MeetCoreErrorEnum::from(error);
        JsValue::from(error_enum)
    }
}

// Type alias for non-WASM environments
#[cfg(not(target_family = "wasm"))]
pub type MeetCoreErrorEnum = MeetCoreError;

#[cfg(target_family = "wasm")]
impl From<JsValue> for MeetCoreError {
    fn from(js_value: JsValue) -> Self {
        Self::InternalError {
            message: format!(
                "JavaScript error: {}",
                js_value
                    .as_string()
                    .unwrap_or_else(|| "Unknown JavaScript error".to_string())
            ),
            details: None,
        }
    }
}
// Thread safety markers for WASM
#[cfg(target_family = "wasm")]
unsafe impl Send for MeetCoreError {}

#[cfg(target_family = "wasm")]
unsafe impl Sync for MeetCoreError {}

/// Type alias for Results using MeetCoreError
pub type Result<T> = std::result::Result<T, MeetCoreError>;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_creation() {
        let auth_error = MeetCoreError::AuthenticationFailed {
            message: "Invalid password".to_string(),
        };
        assert!(matches!(
            auth_error,
            MeetCoreError::AuthenticationFailed { .. }
        ));
    }

    #[test]
    fn test_error_conversion() {
        let anyhow_error = anyhow::anyhow!("Test error");
        let meet_error: MeetCoreError = anyhow_error.into();
        assert!(matches!(meet_error, MeetCoreError::InternalError { .. }));
    }
}
