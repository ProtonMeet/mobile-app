use muon::{Error as MuonError, ProtonResponse};
use serde::de::DeserializeOwned;

use crate::errors::http_client::{HttpClientError, ResponseError};

pub trait ProtonResponseExt {
    fn parse_response<T>(&self) -> Result<T, HttpClientError>
    where
        T: DeserializeOwned + std::fmt::Debug;
}

impl ProtonResponseExt for ProtonResponse {
    fn parse_response<T>(&self) -> Result<T, HttpClientError>
    where
        T: DeserializeOwned + std::fmt::Debug,
    {
        let response_status = self.status();

        let type_name = std::any::type_name::<T>();
        let handle_error = |response_parse_error: Option<MuonError>| -> Result<T, HttpClientError> {
            // Attempt to parse the response into the error type.
            if let Ok(parsed_error_payload) = self.body_json::<ResponseError>() {
                return Err(HttpClientError::ErrorCode(
                    response_status,
                    parsed_error_payload,
                ));
            }

            match response_parse_error {
                Some(parsing_error) => {
                    // If parsing the known error type fails, check if the body can be read as a
                    // string.
                    let body = self.body().to_vec();

                    // We either return details about the parsing error with the body as string
                    // Only include body in debug builds to prevent leaking sensitive data in production
                    let error_details = match String::from_utf8(body) {
                        Ok(text) => {
                            #[cfg(debug_assertions)]
                            {
                                format!(
                                    "Failed to parse response as {type_name}: Error: {parsing_error}, Body: {text}"
                                )
                            }
                            #[cfg(not(debug_assertions))]
                            {
                                format!(
                                    "Failed to parse response as {type_name}: Error: {parsing_error}"
                                )
                            }
                        }
                        // Or just the parsing error
                        Err(_) => {
                            format!("Failed to parse response as {type_name}: {parsing_error}",)
                        }
                    };

                    Err(HttpClientError::Deserialize(error_details))
                }
                None => Err(HttpClientError::ErrorCode(
                    response_status,
                    ResponseError::default(),
                )),
            }
        };

        if response_status.is_client_error() || response_status.is_server_error() {
            return handle_error(None);
        }

        match self.body_json::<T>() {
            Ok(res) => Ok(res),
            Err(response_parse_error) => handle_error(Some(response_parse_error)),
        }
    }
}
