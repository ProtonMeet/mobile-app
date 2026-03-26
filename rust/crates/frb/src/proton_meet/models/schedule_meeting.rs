use proton_meet_calendar::RecurrenceFrequency;

#[derive(Debug, Clone)]
pub struct ScheduleMeetingRequest {
    pub title: String,
    pub start_timestamp: i64, // Unix timestamp in seconds
    pub end_timestamp: i64,   // Unix timestamp in seconds
    pub recurrence: Option<RecurrenceFrequency>,
    pub location: Option<String>,
    pub description: Option<String>,
    pub time_zone: Option<String>,
}
