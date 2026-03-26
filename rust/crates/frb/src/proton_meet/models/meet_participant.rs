use flutter_rust_bridge::frb;
pub use proton_meet_core::domain::user::models::meet_link_info::MeetParticipant;

#[frb(mirror(MeetParticipant))]
pub struct _MeetParticipant {
    pub participant_uuid: String,
    pub display_name: String,
    pub encrypted_display_name: Option<String>,
    pub can_subscribe: Option<u8>,
    pub can_publish: Option<u8>,
    pub can_publish_data: Option<u8>,
    pub is_admin: Option<u8>,
    pub is_host: Option<u8>,
}
