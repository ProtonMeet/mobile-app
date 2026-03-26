/// FFI-friendly version of MeetInfo
#[derive(Debug, Clone)]
pub struct FrbMeetInfo {
    pub meet_name: String,
    pub meet_link_name: String,
    pub access_token: String,
    pub websocket_url: String,
    pub participants_count: u32,
    pub is_locked: bool,
    pub max_duration: u32,
    pub max_participants: u32,
    /// Unix timestamp in seconds (Option<i64>)
    pub expiration_time: Option<i64>,
}

impl From<proton_meet_core::domain::user::models::meet_link_info::MeetInfo> for FrbMeetInfo {
    fn from(meet_info: proton_meet_core::domain::user::models::meet_link_info::MeetInfo) -> Self {
        Self {
            meet_name: meet_info.meet_name,
            meet_link_name: meet_info.meet_link_name,
            access_token: meet_info.access_token,
            websocket_url: meet_info.websocket_url,
            participants_count: meet_info.participants_count,
            is_locked: meet_info.is_locked,
            max_duration: meet_info.max_duration,
            max_participants: meet_info.max_participants,
            expiration_time: meet_info.expiration_time,
        }
    }
}
