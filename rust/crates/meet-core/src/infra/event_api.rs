use proton_meet_macro::async_trait;

use crate::domain::user::ports::event_api::EventApi;
use crate::errors::http_client::HttpClientError;
use crate::infra::dto::event::{EventsResponse, GetEventsResponse, LatestEventIdResponse};
use crate::infra::http_client::ProtonHttpClient;
use crate::infra::http_client_util::HttpClientUtil;
use crate::infra::proton_response_ext::ProtonResponseExt;

#[async_trait]
impl EventApi for ProtonHttpClient {
    async fn get_latest_event_id(&self) -> Result<String, HttpClientError> {
        let req = self.get("/meet/v1/events/latest");
        let res = self.get_session().send(req).await?;
        let latest_event_res = res.parse_response::<LatestEventIdResponse>()?;
        Ok(latest_event_res.event_id)
    }

    async fn get_events(&self, event_id: &str) -> Result<GetEventsResponse, HttpClientError> {
        let req = self.get(format!("/meet/v1/events/{event_id}"));
        let res = self.get_session().send(req).await?;
        let events_res = res.parse_response::<EventsResponse>()?;
        Ok(events_res.into())
    }
}
