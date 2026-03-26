use flutter_rust_bridge::frb;
use proton_meet_core::domain::user::models::meeting::{MeetingType, UpcomingMeeting};

pub struct FrbUpcomingMeeting {
    pub id: String,
    pub address_id: Option<String>,
    pub meeting_link_name: String,
    pub meeting_name: String,
    pub meeting_password: String,
    pub meeting_type: MeetingType,
    pub start_time: Option<i64>,
    pub end_time: Option<i64>,
    pub r_rule: Option<String>,
    pub time_zone: Option<String>,
    pub calendar_id: Option<String>,
    pub proton_calendar: u8,
    pub create_time: Option<i64>,
    pub last_used_time: Option<i64>,
    pub calendar_event_id: Option<String>,
}

impl FrbUpcomingMeeting {
    #[frb(sync)]
    pub fn default_values() -> Self {
        Self {
            id: String::new(),
            address_id: None,
            meeting_link_name: String::new(),
            meeting_name: String::new(),
            meeting_password: String::new(),
            meeting_type: MeetingType::Instant,
            start_time: None,
            end_time: None,
            r_rule: None,
            time_zone: None,
            calendar_id: None,
            proton_calendar: 0,
            create_time: None,
            last_used_time: None,
            calendar_event_id: None,
        }
    }
    #[frb(sync)]
    pub fn new_for_join(meeting_link_name: String, meeting_password: String) -> Self {
        Self {
            id: String::new(),
            address_id: None,
            meeting_link_name,
            meeting_name: String::new(),
            meeting_password: meeting_password,
            meeting_type: MeetingType::Instant,
            start_time: None,
            end_time: None,
            r_rule: None,
            time_zone: None,
            calendar_id: None,
            proton_calendar: 0,
            create_time: None,
            last_used_time: None,
            calendar_event_id: None,
        }
    }
}

impl From<UpcomingMeeting> for FrbUpcomingMeeting {
    fn from(upcoming_meeting: UpcomingMeeting) -> Self {
        Self {
            id: upcoming_meeting.id,
            address_id: upcoming_meeting.address_id,
            meeting_link_name: upcoming_meeting.meeting_link_name.clone(),
            meeting_name: upcoming_meeting.meeting_name.clone(),
            meeting_password: upcoming_meeting.meeting_password.clone(),
            meeting_type: upcoming_meeting.meeting_type,
            start_time: upcoming_meeting.start_time.map(|t| t.timestamp()),
            end_time: upcoming_meeting.end_time.map(|t| t.timestamp()),
            r_rule: upcoming_meeting.r_rule,
            time_zone: upcoming_meeting.time_zone,
            calendar_id: upcoming_meeting.calendar_id,
            proton_calendar: upcoming_meeting.proton_calendar,
            create_time: upcoming_meeting.create_time.map(|t| t.timestamp()),
            last_used_time: upcoming_meeting.last_used_time.map(|t| t.timestamp()),
            calendar_event_id: upcoming_meeting.calendar_event_id,
        }
    }
}
