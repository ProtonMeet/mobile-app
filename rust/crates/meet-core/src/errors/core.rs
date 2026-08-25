//! Error types for the meet-core crate
//!
//! This module defines the primary error type [`MeetCoreError`] that unifies all possible
//! errors that can occur in the meet-core library, providing better error handling and
//! more informative error messages to consumers.

use std::error::Error;

#[cfg(target_family = "wasm")]
use wasm_bindgen::prelude::*;

use crate::{errors::http_client::HttpClientError, service::mls_service::MlsServiceError};

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

    #[error("Join request timed out for room {room_id}: didn't receive welcome message")]
    RoomJoinRequestTimeout { room_id: String },

    #[error("Waiting-room join request not found")]
    WaitingRoomJoinRequestNotFound,

    #[error("Waiting room join cancelled")]
    WaitingRoomJoinCancelled,

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

    #[error("Device clock is not in sync. Please check your device clock and refresh the page to try again.")]
    CheckDeviceClock,

    #[error("Token is expired. Please refresh the page and try again.")]
    TokenIsExpired,

    #[error("Token is invalid. Please refresh the page and try again.")]
    TokenIsInvalid,

    #[error("Meeting is locked. Please try again later.")]
    MeetingLocked,

    #[error("Incorrect meeting password.")]
    IncorrectPassword,

    #[error(transparent)]
    UuidError(#[from] uuid::Error),

    #[error("User is not RoomAdmin")]
    NotRoomAdmin,

    #[error("Unexpected MLS message content: {content_type:?}")]
    UnExpectedMlsMessageContent { content_type: Option<String> },

    #[error("Ratchet tree not found")]
    RatchetTreeNotFound,

    #[error("Mls service error: {0}")]
    MlsServiceError(#[from] MlsServiceError),

    #[error("Chat error: {0}")]
    ChatError(#[from] proton_meet_chat::ChatError),

    #[error("Mls status code: {0}")]
    MlsStatusCode(u32),
}

impl MeetCoreError {
    /// Whether [`crate::app::App::join_room_with_switch_join_type`] should retry the MLS join call.
    pub fn is_retryable_switch_join(&self) -> bool {
        match self {
            Self::MlsStatusCode(422) => true,
            Self::RoomJoinFailed { reason, .. } => {
                reason.contains("didn't receive the welcome message from the server")
            }
            _ => false,
        }
    }
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
        use crate::errors::service::ServiceError;
        // `ServiceError::HttpClientError` (and nested `HttpClientError` in `source()`)
        // must become `MeetCoreError::HttpClientError` so the FRB layer can classify
        // Muon auth/session strings (e.g. "non-existent auth session"). Previously only
        // `ErrorCode` and `MeetingLocked` were lifted; `AuthSession` / `AuthRefresh` / etc.
        // fell through to `ServiceError` and surfaced as generic `BridgeError::MeetCore`.
        match error {
            ServiceError::HttpClientError(http) => Self::from(http),
            other => {
                if let Some(inner_error) = find_error_type::<HttpClientError>(&other) {
                    match inner_error {
                        HttpClientError::MeetingLocked => Self::MeetingLocked,
                        HttpClientError::ErrorCode(_, error_detail) => Self::HttpClientError {
                            status: error_detail.code,
                            message: error_detail.error.clone(),
                            details: Some(format!("{:?}", error_detail.details)),
                        },
                        HttpClientError::MlsStatusCode(status) => Self::MlsStatusCode(*status),
                        HttpClientError::IncorrectPassword => Self::IncorrectPassword,
                        HttpClientError::CheckDeviceClock => Self::CheckDeviceClock,
                        HttpClientError::TokenExpired => Self::TokenIsExpired,
                        HttpClientError::InvalidToken => Self::TokenIsInvalid,
                        _ => Self::HttpClientError {
                            status: 0,
                            message: inner_error.to_string(),
                            details: None,
                        },
                    }
                } else {
                    Self::ServiceError {
                        message: other.to_string(),
                        details: Some(format!("{:?}", other.source())),
                    }
                }
            }
        }
    }
}

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

//TODO:: should remove anyhow::Error
impl From<anyhow::Error> for MeetCoreError {
    fn from(error: anyhow::Error) -> Self {
        // Try to downcast to HttpClientError first
        if let Some(http_error) = error.downcast_ref::<HttpClientError>() {
            return match http_error {
                HttpClientError::MeetingLocked => Self::MeetingLocked,
                HttpClientError::IncorrectPassword => Self::IncorrectPassword,
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

impl From<crate::domain::room::WaitingRoomError> for MeetCoreError {
    fn from(error: crate::domain::room::WaitingRoomError) -> Self {
        match error {
            crate::domain::room::WaitingRoomError::EncryptionError(e) => Self::CryptographicError {
                operation: e.to_string(),
            },
            crate::domain::room::WaitingRoomError::KeyPackageError(e) => Self::MlsProtocolError {
                message: e.to_string(),
            },
            crate::domain::room::WaitingRoomError::InvalidEncryptedKeyPackage => {
                Self::CryptographicError {
                    operation: "Failed to decode encrypted key package".to_string(),
                }
            }
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
            HttpClientError::IncorrectPassword => Self::IncorrectPassword,
            HttpClientError::ErrorCode(_, ref err) => Self::HttpClientError {
                status: err.code,
                message: err.error.clone(),
                details: Some(err.details.to_string()),
            },
            HttpClientError::CheckDeviceClock => Self::CheckDeviceClock,
            HttpClientError::TokenExpired => Self::TokenIsExpired,
            HttpClientError::InvalidToken => Self::TokenIsInvalid,
            HttpClientError::MlsStatusCode(status) => Self::MlsStatusCode(status),
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
    RoomJoinRequestTimeout,
    WaitingRoomJoinRequestNotFound,
    WaitingRoomJoinCancelled,
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
    MeetingLocked,
    IncorrectPassword,
    TokenIsExpired,
    TokenIsInvalid,
    CheckDeviceClock,
    UuidError,
    NotRoomAdmin,
    MlsStatusCode,
    ChatError,
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
            MeetCoreError::RoomJoinRequestTimeout { .. } => Self::RoomJoinRequestTimeout,
            MeetCoreError::WaitingRoomJoinRequestNotFound => Self::WaitingRoomJoinRequestNotFound,
            MeetCoreError::WaitingRoomJoinCancelled => Self::WaitingRoomJoinCancelled,
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
            MeetCoreError::CheckDeviceClock => Self::CheckDeviceClock,
            MeetCoreError::TokenIsExpired => Self::TokenIsExpired,
            MeetCoreError::TokenIsInvalid => Self::TokenIsInvalid,
            MeetCoreError::MeetingLocked => Self::MeetingLocked,
            MeetCoreError::IncorrectPassword => Self::IncorrectPassword,
            MeetCoreError::UuidError(_) => Self::UuidError,
            MeetCoreError::NotRoomAdmin => Self::NotRoomAdmin,
            MeetCoreError::UnExpectedMlsMessageContent { .. } => Self::MlsSpecError,
            MeetCoreError::RatchetTreeNotFound => Self::MlsProtocolError,
            MeetCoreError::MlsServiceError(_) => Self::InternalError,
            MeetCoreError::ChatError(_) => Self::ChatError,
            MeetCoreError::MlsStatusCode(_status) => Self::MlsStatusCode,
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

#[cfg(target_family = "wasm")]
impl MeetCoreError {
    pub fn into_js_error(self) -> JsValue {
        let (message, code) = match &self {
            MeetCoreError::HttpClientError {
                message, status, ..
            } => (message.clone(), Some(*status)),
            other => (other.to_string(), None),
        };
        let kind = MeetCoreErrorEnum::from(self) as u32;

        let js_err = js_sys::Error::new(&message);
        js_err.set_name("MeetCoreError");
        let js_val: JsValue = js_err.into();
        let _ = js_sys::Reflect::set(
            &js_val,
            &JsValue::from_str("kind"),
            &JsValue::from_f64(kind as f64),
        );
        if let Some(code) = code {
            let _ = js_sys::Reflect::set(
                &js_val,
                &JsValue::from_str("code"),
                &JsValue::from_f64(code as f64),
            );
        }
        js_val
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

    #[test]
    fn test_is_retryable_switch_join() {
        assert!(MeetCoreError::MlsStatusCode(422).is_retryable_switch_join());
        assert!(
            MeetCoreError::RoomJoinFailed {
                room_id: "room".into(),
                reason: "Join proposal timeout, didn't receive the welcome message from the server, please try again".into(),
            }
            .is_retryable_switch_join()
        );
        assert!(!MeetCoreError::RoomJoinFailed {
            room_id: "room".into(),
            reason: "Join proposal state is not valid".into(),
        }
        .is_retryable_switch_join());
    }
}
