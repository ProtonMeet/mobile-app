use std::fmt;

use muon::{
    client::middleware::AuthErr,
    error::{Error as MuonError, ErrorKind as MuonErrorKind},
};

use crate::infra::dto::realtime::GroupInfoVersionError;

#[derive(Debug, thiserror::Error)]
pub enum HttpClientError {
    #[error("A muon {0} error was caused by a non-existent auth session")]
    AuthSession(MuonErrorKind),
    #[error("A muon {0} error was caused by a failed auth refresh")]
    AuthRefresh(MuonErrorKind),
    #[error("A muon error was caused by a failed auth via forked session")]
    ForkAuthSession,
    #[error("A muon error was caused by a failed fork session")]
    ForkSession,
    // #[error("A muon error was caused by a failed login")]
    // LoginError,
    // #[error("A muon error was caused by unsupported TwoFactor")]
    // UnsupportedTwoFactor,
    // #[error("An error occurred in the Muon App Version parser: \n\t{0}")]
    // MuonAppVersion(#[from] ParseAppVersionErr),
    // #[error("An error from Muon status: \n\t{0}")]
    // MuonStatus(#[from] StatusErr),
    #[error("An error from Muon occurred: \n\t{0}")]
    MuonError(#[source] muon::Error),
    // #[error("Bitcoin deserialize error: \n\t{0}")]
    // BitcoinDeserialize(#[from] BitcoinEncodingError),
    // #[error("An error occurred when decoding hex to array: \n\t{0}")]
    // HexToArrayDecoding(#[from] HexToArrayError),
    // #[error("An error occurred when decoding hex to bytes: \n\t{0}")]
    // HexToBytesErrorDecoding(#[from] HexToBytesError),
    // #[error("HTTP error")]
    // Http,
    #[error("API Response error: {1}")]
    ErrorCode(muon::Status, ResponseError),
    #[error("Response parser error: {0}")]
    Deserialize(String),
    #[error("Parse error: {0}")]
    ParseError(#[from] chrono::ParseError),

    /// Mls errors
    #[error("Mls Response error")]
    MlsResponseError {
        status: reqwest::StatusCode,
        details: Option<String>,
        message: String,
    },

    #[error("Mls Deserialize error")]
    MlsDeserializeError {
        status: reqwest::StatusCode,
        details: Option<String>,
        message: String,
    },
    #[error("Mls Request failed: {0}")]
    MlsRequestFailed(#[from] mls_spec::MlsSpecError),
    #[error("Mls Invalid URL: {url}")]
    MlsInvalidUrl { url: String },
    #[error("Status code: {0}")]
    MlsStatusCode(u32),
    #[error("Mls Network timeout")]
    MlsNetworkTimeout,
    #[error("Mls HTTP error: {message}")]
    MlsHttpError { message: String },
    #[error("GroupInfo is empty")]
    GroupInfoEmpty,
    #[error("GroupInfo summary is empty")]
    GroupInfoSummaryEmpty,
    #[error("Proxy error: {0}")]
    ProxyError(String),

    #[error("GroupInfo version error: {0}")]
    GroupInfoVersionError(#[from] GroupInfoVersionError),

    #[error("Meeting is locked. Please try again later.")]
    MeetingLocked,
}

impl From<url::ParseError> for HttpClientError {
    fn from(error: url::ParseError) -> Self {
        Self::MlsInvalidUrl {
            url: error.to_string(),
        }
    }
}

impl From<reqwest::Error> for HttpClientError {
    fn from(error: reqwest::Error) -> Self {
        #[cfg(not(target_family = "wasm"))]
        if error.is_status() {
            Self::MlsStatusCode(error.status().unwrap().as_u16() as u32)
        } else if error.is_timeout() {
            Self::MlsNetworkTimeout
        } else if error.is_connect() {
            Self::MlsHttpError {
                message: format!("Connection failed: {error}"),
            }
        } else {
            Self::MlsHttpError {
                message: error.to_string(),
            }
        }
        #[cfg(target_family = "wasm")]
        if error.is_status() {
            Self::MlsStatusCode(error.status().unwrap().as_u16() as u32)
        } else if error.is_timeout() {
            Self::MlsNetworkTimeout
        } else {
            Self::MlsHttpError {
                message: error.to_string(),
            }
        }
    }
}

impl From<MuonError> for HttpClientError {
    fn from(err: MuonError) -> Self {
        // Muon may fail before the HTTP stack returns `Ok(HttpRes)` — e.g. auth layer
        // `POST /auth/v4/sessions` returns 4xx/5xx and propagates `StatusErr` (see muon
        // `AuthLayerErr::StatusErr`). Walk the full source chain so we still parse the body.
        let mut cur: Option<&(dyn std::error::Error + 'static)> = Some(&err);
        while let Some(e) = cur {
            if let Some(se) = e.downcast_ref::<muon::StatusErr>() {
                let status = se.0;
                let parsed = response_error_from_api_failure_body(se.1.body(), status.as_u16());
                return HttpClientError::ErrorCode(status, parsed);
            }
            if let Some(AuthErr::Refresh) = e.downcast_ref() {
                return HttpClientError::AuthRefresh(err.kind());
            }
            if let Some(AuthErr::Session) = e.downcast_ref() {
                return HttpClientError::AuthSession(err.kind());
            }
            cur = e.source();
        }

        HttpClientError::MuonError(err)
    }
}

/// Proton API errors are usually PascalCase (`Code`, `Error`, `Details`); some endpoints use camelCase.
#[derive(Debug, Clone, serde::Deserialize, Default)]
#[serde(rename_all = "PascalCase")]
pub struct ResponseError {
    #[serde(default, alias = "code")]
    pub code: u16,
    #[serde(default, alias = "details")]
    pub details: serde_json::Value,
    #[serde(default, alias = "error")]
    pub error: String,
}

impl fmt::Display for ResponseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "code: {}, error: {}, details: {}",
            self.code, self.error, self.details
        )
    }
}

/// Best-effort parse of a failed API response body so callers see a non-zero code when possible.
pub(crate) fn response_error_from_api_failure_body(body: &[u8], http_status: u16) -> ResponseError {
    if let Ok(e) = serde_json::from_slice::<ResponseError>(body) {
        if e.code != 0 || !e.error.is_empty() {
            return e;
        }
    }
    if let Ok(v) = serde_json::from_slice::<serde_json::Value>(body) {
        let code = v
            .get("Code")
            .or(v.get("code"))
            .and_then(|c| {
                if let Some(n) = c.as_u64() {
                    return u16::try_from(n).ok();
                }
                if let Some(n) = c.as_i64() {
                    return u16::try_from(n).ok();
                }
                c.as_str().and_then(|s| s.parse().ok())
            })
            .unwrap_or(0);
        let error = v
            .get("Error")
            .or(v.get("error"))
            .and_then(|e| e.as_str())
            .unwrap_or("")
            .to_string();
        let details = v
            .get("Details")
            .or(v.get("details"))
            .cloned()
            .unwrap_or(serde_json::Value::Null);
        if code != 0 || !error.is_empty() {
            return ResponseError {
                code,
                error,
                details,
            };
        }
    }
    ResponseError {
        code: http_status,
        error: format!("Request failed (HTTP {http_status})"),
        details: serde_json::Value::String(
            String::from_utf8_lossy(body).chars().take(2000).collect(),
        ),
    }
}
