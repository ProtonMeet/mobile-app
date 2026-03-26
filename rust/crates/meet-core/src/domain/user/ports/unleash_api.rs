use proton_meet_macro::async_trait_with_mock;

use crate::{domain::user::models::UnleashResponse, errors::http_client::HttpClientError};

#[async_trait_with_mock]
pub trait UnleashApi: Send + Sync {
    async fn fetch_toggles(&self) -> Result<UnleashResponse, HttpClientError>;
}
