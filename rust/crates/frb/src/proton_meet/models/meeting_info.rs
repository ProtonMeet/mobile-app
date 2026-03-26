use proton_meet_core::domain::user::models::MeetingInfo;

pub struct FrbMeetingInfo {
    /// Unique meeting link name
    pub meeting_link_name: String,
    /// Encrypted meeting name with session key
    pub meeting_name: String,
    /// Salt of the password
    pub salt: String,
    /// Encrypted session key of the meeting
    pub session_key: String,
    /// 1 if meeting is locked
    pub locked: u8,
    /// Maximum duration of this meeting in seconds
    pub max_duration: u32,
    /// Maximum number of participants allowed in this meeting
    pub max_participants: u32,
    /// The datetime when the meeting room will be forcefully terminated
    pub expiration_time: Option<i64>,
}

impl From<MeetingInfo> for FrbMeetingInfo {
    fn from(meeting_info: MeetingInfo) -> Self {
        Self {
            meeting_link_name: meeting_info.meeting_link_name,
            meeting_name: meeting_info.meeting_name,
            salt: meeting_info.salt,
            session_key: meeting_info.session_key,
            locked: meeting_info.locked,
            max_duration: meeting_info.max_duration,
            max_participants: meeting_info.max_participants,
            expiration_time: meeting_info.expiration_time.map(|t| t.timestamp()),
        }
    }
}
