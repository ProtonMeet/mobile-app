use serde::{Deserialize, Deserializer};

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

/// Meeting event item containing ID and action
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct UserEventItem {
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

/// User events payload (`Users` in API JSON; inner `Users` holds the list).
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct UserEvent {
    /// List of user events with ID and Action
    pub users: Vec<UserEventItem>,
}

/// Some event-loop payloads include a single `User` object (without `Action`).
/// We only need the user ID to trigger a user-state refresh in existing logic.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct UserPayload {
    #[serde(default, rename = "ID")]
    pub id: Option<String>,
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
    /// User events (null if no user updates)
    pub users: Option<UserEvent>,
    /// Singular user object from event loop payload.
    /// Present in some responses even when `Users` events are omitted.
    pub user: Option<UserPayload>,

    /// Whether there are more events available
    #[serde(deserialize_with = "deserialize_bool_or_zero_one")]
    pub more: bool,
    /// Whether a full refresh is needed
    #[serde(deserialize_with = "deserialize_bool_or_zero_one")]
    pub refresh: bool,
    /// The event ID for this response
    #[serde(rename = "EventID")]
    pub event_id: String,
    /// Response code (e.g., 1000 for success)
    pub code: u32,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(untagged)]
enum BoolOrZeroOne {
    Bool(bool),
    Int(u8),
}

fn deserialize_bool_or_zero_one<'de, D>(deserializer: D) -> Result<bool, D::Error>
where
    D: Deserializer<'de>,
{
    match BoolOrZeroOne::deserialize(deserializer)? {
        BoolOrZeroOne::Bool(v) => Ok(v),
        BoolOrZeroOne::Int(0) => Ok(false),
        BoolOrZeroOne::Int(1) => Ok(true),
        BoolOrZeroOne::Int(other) => Err(serde::de::Error::custom(format!(
            "expected bool or 0/1, got {other}"
        ))),
    }
}

impl EventsResponse {
    /// Extract meeting events (ID and Action) from the response if present
    pub fn meeting_events(&self) -> Option<Vec<MeetingEventItem>> {
        self.meet_meetings
            .as_ref()
            .map(|e| e.meetings.clone())
            .filter(|v| !v.is_empty())
    }

    /// Extract user events (ID and Action) from the response if present
    pub fn users(&self) -> Option<Vec<UserEventItem>> {
        let users_from_events = self
            .users
            .as_ref()
            .map(|e| e.users.clone())
            .filter(|v| !v.is_empty());

        if users_from_events.is_some() {
            return users_from_events;
        }

        // Fallback: if backend sends `User` (without action), treat as an update event.
        self.user.as_ref().map(|u| {
            vec![UserEventItem {
                id: u
                    .id
                    .clone()
                    .filter(|id| !id.is_empty())
                    .unwrap_or_else(|| "current-user".to_string()),
                action: EventAction::Update,
            }]
        })
    }
}

/// Response data for get_events API call
#[derive(Debug, Clone)]
pub struct GetEventsResponse {
    /// Meeting events (ID and Action) if any
    pub meeting_events: Option<Vec<MeetingEventItem>>,
    /// User data if any
    pub users: Option<Vec<UserEventItem>>,
    /// Singular user object from event loop payload.
    /// Present in some responses even when `Users` events are omitted.
    pub user: Option<UserPayload>,
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
            users: response.users(),
            more: response.more,
            refresh: response.refresh,
            event_id: response.event_id,
            user: response.user,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// Mirrors real API payloads: extra top-level keys are ignored; `Users` / `MeetMeetings` null.
    #[test]
    fn events_response_deserializes_sample_with_unknown_fields_and_null_users() {
        let j = json!({
            "Users": null,
            "Addresses": [{"ID": "addr-1", "Action": 0}],
            "UserSettings": null,
            "Domains": null,
            "Members": null,
            "MeetMeetings": null,
            "More": true,
            "Refresh": true,
            "EventID": "evt-sample-1",
            "EventOrder": 0,
            "Code": 1000
        });
        let parsed: EventsResponse = serde_json::from_value(j).expect("deserialize EventsResponse");
        assert!(parsed.users.is_none());
        assert!(parsed.meet_meetings.is_none());
        assert!(parsed.more);
        assert!(parsed.refresh);
        assert_eq!(parsed.event_id, "evt-sample-1");
        assert_eq!(parsed.code, 1000);
        assert!(parsed.meeting_events().is_none());
        assert!(parsed.users().is_none());
    }

    #[test]
    fn events_response_deserializes_meet_meetings_as_direct_array() {
        let j = json!({
            "MeetMeetings": [
                {"ID": "meet-a", "Action": 1},
                {"ID": "meet-b", "Action": 2}
            ],
            "Users": null,
            "More": false,
            "Refresh": false,
            "EventID": "evt-2",
            "Code": 1000
        });
        let parsed: EventsResponse = serde_json::from_value(j).unwrap();
        let meetings = parsed.meeting_events().expect("meetings");
        assert_eq!(meetings.len(), 2);
        assert_eq!(meetings[0].id, "meet-a");
        assert_eq!(meetings[0].action, EventAction::Create);
        assert_eq!(meetings[1].id, "meet-b");
        assert_eq!(meetings[1].action, EventAction::Update);
    }

    /// `UserEvent` is an object with a `Users` array (PascalCase on both levels).
    #[test]
    fn events_response_deserializes_nested_users_wrapper() {
        let j = json!({
            "Users": {
                "Users": [
                    {"ID": "user-1", "Action": 0},
                    {"ID": "user-2", "Action": 3}
                ]
            },
            "MeetMeetings": null,
            "More": false,
            "Refresh": true,
            "EventID": "evt-3",
            "Code": 1000
        });
        let parsed: EventsResponse = serde_json::from_value(j).unwrap();
        let users = parsed.users().expect("user events");
        assert_eq!(users.len(), 2);
        assert_eq!(users[0].id, "user-1");
        assert_eq!(users[0].action, EventAction::Delete);
        assert_eq!(users[1].id, "user-2");
        assert_eq!(users[1].action, EventAction::UpdateFlags);
    }

    #[test]
    fn get_events_response_from_combines_meet_and_users() {
        let j = json!({
            "MeetMeetings": [{"ID": "m1", "Action": 1}],
            "Users": {"Users": [{"ID": "u1", "Action": 2}]},
            "More": true,
            "Refresh": false,
            "EventID": "evt-4",
            "Code": 1000
        });
        let parsed: EventsResponse = serde_json::from_value(j).unwrap();
        let ge: GetEventsResponse = parsed.into();
        let m = ge.meeting_events.as_ref().unwrap();
        let u = ge.users.as_ref().unwrap();
        assert_eq!(m.len(), 1);
        assert_eq!(m[0].id, "m1");
        assert_eq!(u.len(), 1);
        assert_eq!(u[0].id, "u1");
        assert_eq!(u[0].action, EventAction::Update);
    }

    #[test]
    fn meeting_events_omitted_when_meet_meetings_empty_array() {
        let j = json!({
            "MeetMeetings": [],
            "Users": null,
            "More": false,
            "Refresh": false,
            "EventID": "evt-5",
            "Code": 1000
        });
        let parsed: EventsResponse = serde_json::from_value(j).unwrap();
        assert!(parsed.meeting_events().is_none());
    }

    #[test]
    fn users_fallback_to_singular_user_payload_when_users_wrapper_missing() {
        let j = json!({
            "MeetMeetings": null,
            "Users": null,
            "User": {"ID": "user-single-1", "Name": "feng"},
            "More": false,
            "Refresh": false,
            "EventID": "evt-6",
            "Code": 1000
        });
        let parsed: EventsResponse = serde_json::from_value(j).unwrap();
        let users = parsed.users().expect("fallback user event");
        assert_eq!(users.len(), 1);
        assert_eq!(users[0].id, "user-single-1");
        assert_eq!(users[0].action, EventAction::Update);
    }

    #[test]
    fn events_response_deserializes_more_refresh_as_zero_one() {
        let j = json!({
            "MeetMeetings": null,
            "Users": null,
            "More": 1,
            "Refresh": 0,
            "EventID": "evt-7",
            "Code": 1000
        });
        let parsed: EventsResponse = serde_json::from_value(j).unwrap();
        assert!(parsed.more);
        assert!(!parsed.refresh);
    }
}
