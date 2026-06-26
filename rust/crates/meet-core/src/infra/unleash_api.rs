use proton_meet_macro::async_trait;

use crate::domain::user::models::UnleashResponse;
use crate::domain::user::ports::UnleashApi;
use crate::errors::http_client::{response_error_from_api_failure_body, HttpClientError};
use crate::infra::http_client::ProtonHttpClient;
use crate::infra::http_client_util::HttpClientUtil;

#[async_trait]
impl UnleashApi for ProtonHttpClient {
    async fn fetch_toggles(&self) -> Result<UnleashResponse, HttpClientError> {
        let req = self.get("feature/v2/frontend");
        let res = self.get_session().send(req).await?;
        let status_code = res.status();
        let body = res.body().to_vec();
        if status_code.is_success() {
            return Ok(UnleashResponse {
                status_code: status_code.as_u16(),
                body,
            });
        }
        let parsed = response_error_from_api_failure_body(&body, status_code.as_u16());
        Err(HttpClientError::ErrorCode(status_code, parsed))
    }
}
