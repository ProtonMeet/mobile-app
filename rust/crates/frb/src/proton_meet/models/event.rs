use flutter_rust_bridge::frb;
pub use proton_meet_core::infra::dto::event::{EventAction, GetEventsResponse, MeetingEventItem};

/// Event action type indicating what happened to the model
#[frb(mirror(EventAction))]
#[repr(i32)]
pub enum _EventAction {
    /// When the model has been deleted since the last event loop poll
    Delete = 0,
    /// When the model has been created since the last event loop poll
    Create = 1,
    /// When the model was already known by the client before the last event loop poll
    /// and was updated since the last event loop poll
    Update = 2,
    /// When the model was already known by the client before the last event loop poll
    /// and only its metadata were updated since the last event loop poll
    UpdateFlags = 3,
}

/// Meeting event item containing ID and action
#[derive(Debug, Clone)]
pub struct FrbMeetingEventItem {
    /// Meeting ID
    pub id: String,
    /// Action that occurred
    pub action: EventAction,
}

impl From<MeetingEventItem> for FrbMeetingEventItem {
    fn from(item: MeetingEventItem) -> Self {
        Self {
            id: item.id,
            action: item.action,
        }
    }
}

/// Response for get_events API call
#[derive(Debug, Clone)]
pub struct FrbGetEventsResponse {
    /// Meeting events (ID and Action) if any
    pub meeting_events: Option<Vec<FrbMeetingEventItem>>,
    /// Whether there are more events available
    pub more: bool,
    /// Whether a full refresh is needed
    pub refresh: bool,
    /// The new event ID
    pub event_id: String,
}

impl From<GetEventsResponse> for FrbGetEventsResponse {
    fn from(response: GetEventsResponse) -> Self {
        Self {
            meeting_events: response
                .meeting_events
                .map(|e| e.into_iter().map(|item| item.into()).collect()),
            more: response.more,
            refresh: response.refresh,
            event_id: response.event_id,
        }
    }
}
