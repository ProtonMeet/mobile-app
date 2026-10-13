use flutter_rust_bridge::frb;
// errors.rs
use proton_meet_app::server::errors::AccessTokenError;
use proton_meet_chat::error::ChatError;
use proton_meet_core::{
    domain::user::models::meet_link::MeetLinkError,
    errors::{core::MeetCoreError, login::LoginError},
};
use std::{error::Error, fmt, sync::PoisonError};

#[derive(thiserror::Error, Debug)]
pub enum BridgeError {
    #[error("Mutex lock error: {0}")]
    MutexLock(String),

    #[error("An error occurred in meet core: {0}")]
    MeetCore(String),

    #[error("Missing two factor")]
    MissingTwoFactor,

    #[error("Any error occurred in meet core: {0}")]
    MeetCoreAny(String),

    #[error("A Login error occurred: {0}")]
    Login(String),

    #[error("An error occurred in api lock: {0}")]
    ApiLock(String),

    /// this is livekit access token error
    #[error("An error occurred in access token: {0}")]
    AccessToken(String),

    /// Muon auth session error
    #[error("A muon auth session error occurred: {0}")]
    MuonAuthSession(String),
    /// Muon auth refresh error
    #[error("A muon auth refresh error occurred: {0}")]
    MuonAuthRefresh(String),
    /// Muon client error
    #[error("An error occurred in muon client: {0}")]
    MuonClient(String),
    /// Muon session error
    #[error("An error occurred in muon session: {0}")]
    MuonSession(String),

    /// Fork error
    #[error("A Fork error occurred: {0}")]
    Fork(String),

    #[error("String encoding error: {0}")]
    Encoding(String),

    #[error("Parse error: {0}")]
    ParseError(String),

    #[error("String error: {0}")]
    Std(String),

    #[error("Failed to set global subscriber: {0}")]
    TracingsSubscriber(String),

    #[error("Meet link error: {0}")]
    MeetLink(String),

    #[error("Chat error: {0}")]
    Chat(String),

    #[error("Task join error: {0}")]
    TaskJoin(String),

    /// api response error
    #[error("An error occurred in api response: {0}")]
    ApiResponse(ResponseError),

    /// Meeting locked error (error code 2502)
    #[error("Meeting is locked. Please try again later.")]
    MeetingLocked,

    /// SRP authentication rejected the supplied password (API error code 2026).
    #[error("Incorrect meeting password.")]
    IncorrectPassword,

    /// MLS server version is newer than this client supports.
    #[error("MLS server version not supported. Please update the app.")]
    MlsServerVersionNotSupported,

    /// Host tried to admit a waiting-room join request that is no longer pending.
    #[error("Waiting-room join request not found")]
    WaitingRoomJoinRequestNotFound,

    /// Join proposal timed out waiting for welcome message.
    #[error("Join request timed out waiting for welcome message")]
    RoomJoinRequestTimeout,

    /// Guest cancelled an outstanding waiting-room join request.
    #[error("Waiting room join cancelled")]
    WaitingRoomJoinCancelled,

    #[error("Token is invalid. Please refresh the page and try again.")]
    TokenIsInvalid,

    #[error("Token is expired. Please refresh the page and try again.")]
    TokenIsExpired,

    #[error(
        "Device clock is not in sync. Please check your device clock and refresh the page to try again."
    )]
    CheckDeviceClock,
}

#[derive(Debug)]
pub struct ResponseError {
    pub code: u16,
    pub error: String,
    pub details: String,
}
impl ResponseError {
    #[frb(sync)]
    pub fn to_detail_string(&self) -> String {
        format!(
            "ResponseError:\n  Code: {}\n  Error: {}\n  Details: {}",
            self.code, self.error, self.details
        )
    }
}
impl fmt::Display for ResponseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "ResponseError:\n  Code: {}\n  Error: {}\n  Details: {}",
            self.code, self.error, self.details
        )
    }
}

impl From<ChatError> for BridgeError {
    fn from(value: ChatError) -> Self {
        BridgeError::Chat(format!(
            "ChatError: message: {:?}, source: {:?}",
            value.to_string(),
            value.source()
        ))
    }
}

/// Wallet maps `AndromedaApiError` variants directly in `From<AndromedaApiError> for BridgeError`.
/// Meet does not: `From<HttpClientError> for MeetCoreError` collapses everything into
/// `MeetCoreError::HttpClientError { message: HttpClientError::to_string(), .. }`, so the FRB
/// layer cannot `match` on variants. We detect cases by substrings from meet-core's `thiserror`
/// text on [`proton_meet_core::errors::http_client::HttpClientError`], then emit the same
/// `BridgeError` **discriminants** as wallet. Payload strings for auth/fork are formatted like
/// wallet where we can; `MuonClient` / `MuonSession` still differ (meet has no `MuonError`
/// value + source like wallet, and no active `MuonAppVersion` / `MuonStatus` arms in meet-core).
fn bridge_error_from_meet_core_http_client(
    status: u16,
    message: String,
    details: Option<String>,
) -> BridgeError {
    if message.contains("non-existent auth session") {
        return BridgeError::MuonAuthSession(format!("AuthSession: {message}"));
    }
    if message.contains("failed auth refresh") {
        return BridgeError::MuonAuthRefresh(format!("AuthRefresh: {message}"));
    }
    if message.contains("failed auth via forked session") {
        return BridgeError::Fork("ForkAuthSession error occurred".to_string());
    }
    if message.contains("failed fork session") {
        return BridgeError::Fork("ForkSession error occurred".to_string());
    }
    if message.contains("An error from Muon occurred") {
        return BridgeError::MuonClient(message);
    }
    BridgeError::ApiResponse(ResponseError {
        code: status,
        error: message,
        details: details.unwrap_or_default(),
    })
}

impl From<MeetCoreError> for BridgeError {
    fn from(value: MeetCoreError) -> Self {
        match value {
            MeetCoreError::MeetingLocked => BridgeError::MeetingLocked,
            MeetCoreError::IncorrectPassword => BridgeError::IncorrectPassword,
            MeetCoreError::MlsServerVersionNotSupported => {
                BridgeError::MlsServerVersionNotSupported
            }
            MeetCoreError::WaitingRoomJoinRequestNotFound => {
                BridgeError::WaitingRoomJoinRequestNotFound
            }
            MeetCoreError::RoomJoinRequestTimeout { .. } => BridgeError::RoomJoinRequestTimeout,
            MeetCoreError::WaitingRoomJoinCancelled => BridgeError::WaitingRoomJoinCancelled,
            MeetCoreError::HttpClientError {
                status,
                message,
                details,
            } => bridge_error_from_meet_core_http_client(status, message, details),
            MeetCoreError::ServiceError { message, details } => BridgeError::MeetCore(format!(
                "MeetCoreError::ServiceError\nmessage: {message}\ndetails: {}",
                details.as_deref().unwrap_or("(none)")
            )),
            MeetCoreError::TokenIsInvalid => BridgeError::TokenIsInvalid,
            MeetCoreError::TokenIsExpired => BridgeError::TokenIsExpired,
            MeetCoreError::CheckDeviceClock => BridgeError::CheckDeviceClock,
            _ => BridgeError::MeetCore(format!(
                "MeetCoreError: message: {:?}, source: {:?}",
                value.to_string(),
                value
                    .source()
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| "(none)".to_string())
            )),
        }
    }
}

impl From<LoginError> for BridgeError {
    fn from(value: LoginError) -> Self {
        BridgeError::Login(format!(
            "LoginError: message: {:?}, source: {:?}",
            value.to_string(),
            value.source()
        ))
    }
}

impl From<anyhow::Error> for BridgeError {
    fn from(value: anyhow::Error) -> Self {
        BridgeError::MeetCoreAny(format!(
            "anyhow::Error: message: {:?}, source: {:?}",
            value.to_string(),
            value.source()
        ))
    }
}

impl From<MeetLinkError> for BridgeError {
    fn from(value: MeetLinkError) -> Self {
        BridgeError::MeetLink(format!(
            "MeetLinkError: message: {:?}, source: {:?}",
            value.to_string(),
            value.source()
        ))
    }
}

impl From<AccessTokenError> for BridgeError {
    fn from(value: AccessTokenError) -> Self {
        BridgeError::AccessToken(format!(
            "AccessTokenError: message: {:?}, source: {:?}",
            value.to_string(),
            value.source()
        ))
    }
}

/// rclock mutex lock error
impl<T> From<PoisonError<T>> for BridgeError {
    fn from(_: PoisonError<T>) -> Self {
        BridgeError::MutexLock("Mutex lock error, please try to restart app".to_string())
    }
}

impl From<std::io::Error> for BridgeError {
    fn from(value: std::io::Error) -> Self {
        BridgeError::Std(format!(
            "IO error: message: {:?}, source: {:?}",
            value.to_string(),
            value.source()
        ))
    }
}

impl From<tokio::task::JoinError> for BridgeError {
    fn from(value: tokio::task::JoinError) -> Self {
        BridgeError::TaskJoin(format!(
            "Task join error: {:?}, is_cancelled: {}, is_panic: {}",
            value,
            value.is_cancelled(),
            value.is_panic()
        ))
    }
}
