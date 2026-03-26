use std::error::Error;

use reqwest::Response;
use serde::de::DeserializeOwned;

use crate::{errors::http_client::HttpClientError, infra::http_client::ApiResponse};

#[cfg_attr(not(target_family = "wasm"), async_trait::async_trait)]
#[cfg_attr(target_family = "wasm", async_trait::async_trait(?Send))]
pub trait MlsResponseExt {
    async fn parse_response<T>(self) -> Result<T, HttpClientError>
    where
        T: DeserializeOwned + std::fmt::Debug;
}

#[cfg_attr(not(target_family = "wasm"), async_trait::async_trait)]
#[cfg_attr(target_family = "wasm", async_trait::async_trait(?Send))]
impl MlsResponseExt for Response {
    async fn parse_response<T>(self) -> Result<T, HttpClientError>
    where
        T: DeserializeOwned + std::fmt::Debug,
    {
        let status = self.status();
        let body_bytes =
            self.bytes()
                .await
                .map_err(|err| HttpClientError::MlsDeserializeError {
                    details: Some(err.source().map(|e| e.to_string()).unwrap_or_default()),
                    message: err.to_string(),
                    status,
                })?;

        // Try to parse as ApiResponse<T>
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
