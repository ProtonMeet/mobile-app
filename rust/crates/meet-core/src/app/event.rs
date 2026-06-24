use super::App;
use crate::errors::core::MeetCoreError;
use crate::infra::dto::event::GetEventsResponse;

impl App {
    /// Get the latest event ID from the server
    pub async fn get_latest_event_id(&self) -> Result<String, MeetCoreError> {
        let event_id = self.event_api.get_latest_event_id().await.map_err(|e| {
            MeetCoreError::HttpClientError {
                status: 0,
                message: e.to_string(),
                details: None,
            }
        })?;
        Ok(event_id)
    }

    /// Get events starting from a given event ID
    /// Returns GetEventsResponse containing meeting event items, flags, and new event ID
    pub async fn get_events(&self, event_id: String) -> Result<GetEventsResponse, MeetCoreError> {
        let response = self
            .event_api
            .get_events(&event_id)
            .await
            .map_err(MeetCoreError::from)?;
        Ok(response)
    }

    /// Get core events starting from a given event ID
    /// Returns GetEventsResponse containing core event items, flags, and new event ID
    pub async fn get_core_events(
        &self,
        event_id: String,
    ) -> Result<GetEventsResponse, MeetCoreError> {
        let response = self
            .event_api
            .get_core_events(&event_id)
            .await
            .map_err(MeetCoreError::from)?;
        Ok(response)
    }
}
