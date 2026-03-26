use serde::Deserialize;

/// Event action type indicating what happened to the model
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(from = "u8")]
pub enum EventAction {
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

impl From<u8> for EventAction {
    fn from(value: u8) -> Self {
        match value {
            0 => EventAction::Delete,
            1 => EventAction::Create,
            2 => EventAction::Update,
            3 => EventAction::UpdateFlags,
            _ => EventAction::Update, // Default to Update for unknown values
        }
    }
}

/// Meeting event item containing ID and action
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct MeetingEventItem {
    /// Meeting ID
    #[serde(rename = "ID")]
    pub id: String,
    /// Action that occurred
    pub action: EventAction,
}

/// Meeting events payload
/// The API returns MeetMeetings as a direct array: [{"ID":"...","Action":1}]
/// This is a wrapper to handle the array format
#[derive(Debug, Clone, Deserialize)]
#[serde(transparent)]
pub struct MeetMeetingsEvent {
    /// List of meeting events with ID and Action
    pub meetings: Vec<MeetingEventItem>,
}

/// Response payload for getting the latest event ID
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct LatestEventIdResponse {
    /// The latest event ID
    #[serde(rename = "EventID")]
    pub event_id: String,
    /// Response code (e.g., 1000 for success)
    pub code: u32,
}

/// Response payload for getting events
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct EventsResponse {
    /// Meeting events (null if no meeting updates)
    pub meet_meetings: Option<MeetMeetingsEvent>,

    /// Whether there are more events available
    pub more: bool,
    /// Whether a full refresh is needed
    pub refresh: bool,
    /// The event ID for this response
    #[serde(rename = "EventID")]
    pub event_id: String,
    /// Response code (e.g., 1000 for success)
    pub code: u32,
}

impl EventsResponse {
    /// Extract meeting events (ID and Action) from the response if present
    pub fn meeting_events(&self) -> Option<Vec<MeetingEventItem>> {
        self.meet_meetings
            .as_ref()
            .map(|e| e.meetings.clone())
            .filter(|v| !v.is_empty())
    }
}

/// Response data for get_events API call
#[derive(Debug, Clone)]
pub struct GetEventsResponse {
    /// Meeting events (ID and Action) if any
    pub meeting_events: Option<Vec<MeetingEventItem>>,
    /// Whether there are more events available
    pub more: bool,
    /// Whether a full refresh is needed
    pub refresh: bool,
    /// The new event ID
    pub event_id: String,
}

impl From<EventsResponse> for GetEventsResponse {
    fn from(response: EventsResponse) -> Self {
        Self {
            meeting_events: response.meeting_events(),
            more: response.more,
            refresh: response.refresh,
            event_id: response.event_id,
        }
    }
}
