use flutter_rust_bridge::frb;
pub use proton_meet_core::domain::user::models::meeting::MeetingType;

#[frb(mirror(MeetingType))]
pub enum _MeetingType {
    Instant = 0,
    Personal = 1,
    Scheduled = 2,
    Recurring = 3,
    Permanent = 4,
}
