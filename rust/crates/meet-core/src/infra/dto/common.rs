use serde::Deserialize;

use crate::errors::http_client::HttpClientError;

/// Standard Proton API response structure for endpoints that return no data
/// Only contains the status code to verify the operation succeeded (code should be 1000)
#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
#[allow(dead_code)]
pub struct ProtonEmptyResponse {
    pub code: u32,
}

#[derive(Debug, Deserialize)]
pub struct ApiResponse<T> {
    pub success: bool,
    pub data: Option<T>,
    pub error: Option<String>,
}

impl<T> ApiResponse<T> {
    pub(crate) fn into_data(self) -> Result<T, HttpClientError> {
        if !self.success {
            return Err(HttpClientError::MlsHttpError {
                message: self.error.unwrap_or_else(|| "request failed".to_string()),
            });
        }
        self.data.ok_or_else(|| HttpClientError::MlsHttpError {
            message: "response missing data".to_string(),
        })
    }
}
