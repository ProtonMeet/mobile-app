use proton_meet_macro::async_trait_with_mock;

use crate::errors::http_client::HttpClientError;
use crate::infra::dto::event::GetEventsResponse;

/// Event API trait for polling meeting events
#[async_trait_with_mock]
pub trait EventApi: Send + Sync {
    /// Get the latest event ID from the server
    ///
    /// # Returns
    /// The latest event ID string
    async fn get_latest_event_id(&self) -> Result<String, HttpClientError>;

    /// Get events starting from a given event ID
    ///
    /// # Arguments
    /// * `event_id` - The event ID to start fetching from
    ///
    /// # Returns
    /// GetEventsResponse containing meeting events, flags, and new event ID
    async fn get_events(&self, event_id: &str) -> Result<GetEventsResponse, HttpClientError>;
}

#[cfg(test)]
mod tests {
    use proton_meet_macro::unified_test;

    use super::*;
    use crate::errors::http_client::HttpClientError;

    #[unified_test]
    async fn test_get_latest_event_id_success() {
        let mut mock = MockEventApi::new();

        mock.expect_get_latest_event_id()
            .returning(|| Box::pin(async { Ok("event-id-123".to_string()) }));

        let result = mock.get_latest_event_id().await.unwrap();
        assert_eq!(result, "event-id-123");
    }

    #[unified_test]
    async fn test_get_latest_event_id_failure() {
        let mut mock = MockEventApi::new();

        mock.expect_get_latest_event_id().returning(|| {
            Box::pin(async {
                Err(HttpClientError::MlsHttpError {
                    message: "fetch failed".into(),
                })
            })
        });

        let result = mock.get_latest_event_id().await;
        assert!(matches!(
            result,
            Err(HttpClientError::MlsHttpError { message: _ })
        ));
    }

    #[unified_test]
    async fn test_get_events_success() {
        use crate::infra::dto::event::{EventAction, GetEventsResponse, MeetingEventItem};
        let mut mock = MockEventApi::new();
        let events = vec![MeetingEventItem {
            id: "id-1".to_string(),
            action: EventAction::Update,
        }];

        mock.expect_get_events()
            .withf(|id| id == "event-id-123")
            .returning(move |_| {
                let events = events.clone();
                Box::pin(async {
                    Ok(GetEventsResponse {
                        meeting_events: Some(events),
                        more: false,
                        refresh: false,
                        event_id: "event-id-124".to_string(),
                    })
                })
            });

        let response = mock.get_events("event-id-123").await.unwrap();
        assert_eq!(response.meeting_events.unwrap().len(), 1);
        assert!(!response.more);
        assert!(!response.refresh);
        assert_eq!(response.event_id, "event-id-124");
    }

    #[unified_test]
    async fn test_get_events_no_meetings() {
        use crate::infra::dto::event::GetEventsResponse;
        let mut mock = MockEventApi::new();

        mock.expect_get_events()
            .withf(|id| id == "event-id-123")
            .returning(|_| {
                Box::pin(async {
                    Ok(GetEventsResponse {
                        meeting_events: None,
                        more: true,
                        refresh: false,
                        event_id: "event-id-124".to_string(),
                    })
                })
            });

        let response = mock.get_events("event-id-123").await.unwrap();
        assert!(response.meeting_events.is_none());
        assert!(response.more);
        assert!(!response.refresh);
        assert_eq!(response.event_id, "event-id-124");
    }
}
