use serde::Deserialize;

/// Standard Proton API response structure for endpoints that return no data
/// Only contains the status code to verify the operation succeeded (code should be 1000)
#[derive(Debug, Deserialize)]
#[serde(rename_all = "PascalCase")]
#[allow(dead_code)]
pub struct ProtonEmptyResponse {
    pub code: u32,
}

