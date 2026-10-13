use std::error::Error;

use meet_type::error::ServerError;
use reqwest::{Response, StatusCode};
use serde::de::DeserializeOwned;

use crate::errors::http_client::{HttpClientError, response_error_from_api_failure_body};
use crate::infra::dto::common::ApiResponse;

pub(crate) fn mls_error_for_status(status: StatusCode, body: &[u8]) -> HttpClientError {
    if status != StatusCode::UNAUTHORIZED {
        return HttpClientError::MlsStatusCode(status.as_u16() as u32);
    }

    let parsed = response_error_from_api_failure_body(body, status.as_u16());
    match ServerError::try_from(parsed.code) {
        Ok(ServerError::InvalidToken) => HttpClientError::InvalidToken,
        Ok(ServerError::CheckDeviceClock) => HttpClientError::CheckDeviceClock,
        Ok(ServerError::TokenExpired) => HttpClientError::TokenExpired,
        Err(_) => HttpClientError::MlsResponseError {
            status,
            details: (cfg!(debug_assertions) && !parsed.details.is_null())
                .then(|| parsed.details.to_string()),
            message: if parsed.error.is_empty() {
                format!(
                    "Unauthorized response with unknown server error code {}",
                    parsed.code
                )
            } else {
                parsed.error
            },
        },
    }
}

#[cfg_attr(not(target_family = "wasm"), async_trait::async_trait)]
#[cfg_attr(target_family = "wasm", async_trait::async_trait(?Send))]
pub trait MlsResponseExt {
    async fn body_bytes(self) -> Result<Vec<u8>, HttpClientError>;

    async fn success_bytes(self) -> Result<Vec<u8>, HttpClientError>;

    async fn ensure_success(self) -> Result<(), HttpClientError>;

    async fn parse_api_response<T>(self) -> Result<T, HttpClientError>
    where
        T: DeserializeOwned;

    async fn parse_response<T>(self) -> Result<T, HttpClientError>
    where
        T: DeserializeOwned;
}

#[cfg_attr(not(target_family = "wasm"), async_trait::async_trait)]
#[cfg_attr(target_family = "wasm", async_trait::async_trait(?Send))]
impl MlsResponseExt for Response {
    async fn body_bytes(self) -> Result<Vec<u8>, HttpClientError> {
        let status = self.status();
        self.bytes()
            .await
            .map(|bytes| bytes.to_vec())
            .map_err(|err| HttpClientError::MlsDeserializeError {
                details: Some(err.source().map(|e| e.to_string()).unwrap_or_default()),
                message: err.to_string(),
                status,
            })
    }

    async fn success_bytes(self) -> Result<Vec<u8>, HttpClientError> {
        let status = self.status();
        let body = self.body_bytes().await?;
        if !status.is_success() {
            return Err(mls_error_for_status(status, &body));
        }
        Ok(body)
    }

    async fn ensure_success(self) -> Result<(), HttpClientError> {
        self.success_bytes().await.map(|_| ())
    }

    async fn parse_api_response<T>(self) -> Result<T, HttpClientError>
    where
        T: DeserializeOwned,
    {
        let status = self.status();
        let body = self.success_bytes().await?;
        let response = serde_json::from_slice::<ApiResponse<T>>(&body).map_err(|err| {
            let details = if cfg!(debug_assertions) {
                Some(String::from_utf8_lossy(&body).into_owned())
            } else {
                None
            };
            HttpClientError::MlsDeserializeError {
                details,
                message: err.to_string(),
                status,
            }
        })?;
        response.into_data()
    }

    async fn parse_response<T>(self) -> Result<T, HttpClientError>
    where
        T: DeserializeOwned,
    {
        let status = self.status();
        let body_bytes = self.body_bytes().await?;

        if !status.is_success() {
            return Err(mls_error_for_status(status, &body_bytes));
        }

        match serde_json::from_slice::<ApiResponse<T>>(&body_bytes) {
            Ok(api_response) => {
                if !api_response.success {
                    return Err(HttpClientError::MlsResponseError {
                        status,
                        details: None,
                        message: api_response
                            .error
                            .unwrap_or_else(|| "Unknown API error".into()),
                    });
                }
                if let Some(data) = api_response.data {
                    return Ok(data);
                } else {
                    return Err(HttpClientError::MlsResponseError {
                        status,
                        details: None,
                        message: "API returned success but no data field".into(),
                    });
                }
            }
            Err(err) => {
                // Could not parse either, give raw body only in debug builds
                // to prevent leaking sensitive data in production
                let details = if cfg!(debug_assertions) {
                    Some(
                        String::from_utf8(body_bytes.to_vec())
                            .unwrap_or_else(|_| "<non-utf8 body>".into()),
                    )
                } else {
                    None
                };

                return Err(HttpClientError::MlsDeserializeError {
                    details,
                    message: err.to_string(),
                    status,
                });
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_invalid_token_server_error_from_unauthorized_body() {
        let error = mls_error_for_status(
            StatusCode::UNAUTHORIZED,
            br#"{"Code":4000,"Error":"InvalidToken"}"#,
        );
        assert!(matches!(error, HttpClientError::InvalidToken));
    }

    #[test]
    fn parses_check_device_clock_server_error_from_unauthorized_body() {
        let error = mls_error_for_status(
            StatusCode::UNAUTHORIZED,
            br#"{"Code":4001,"Error":"CheckDeviceClock"}"#,
        );
        assert!(matches!(error, HttpClientError::CheckDeviceClock));
    }

    #[test]
    fn parses_token_expired_server_error_from_unauthorized_body() {
        let error = mls_error_for_status(
            StatusCode::UNAUTHORIZED,
            br#"{"Code":4002,"Error":"TokenExpired"}"#,
        );
        assert!(matches!(error, HttpClientError::TokenExpired));
    }

    #[test]
    fn preserves_unknown_unauthorized_server_error() {
        let error = mls_error_for_status(
            StatusCode::UNAUTHORIZED,
            br#"{"Code":4999,"Error":"UnknownError"}"#,
        );
        assert!(matches!(
            error,
            HttpClientError::MlsResponseError {
                status: StatusCode::UNAUTHORIZED,
                message,
                ..
            } if message == "UnknownError"
        ));
    }

    #[test]
    fn handles_malformed_unauthorized_body_without_panicking() {
        let error = mls_error_for_status(StatusCode::UNAUTHORIZED, b"not json");
        assert!(matches!(
            error,
            HttpClientError::MlsResponseError {
                status: StatusCode::UNAUTHORIZED,
                ..
            }
        ));
    }

    #[test]
    fn preserves_status_code_for_non_unauthorized_errors() {
        let error = mls_error_for_status(StatusCode::UNPROCESSABLE_ENTITY, b"{}");
        assert!(matches!(error, HttpClientError::MlsStatusCode(422)));
    }
}
