use flutter_rust_bridge::frb;
pub use proton_meet_core::domain::user::models::meet_link::MeetLink;

#[frb(mirror(MeetLink))]
pub struct _MeetLink {
    pub id: String,
    pub pwd: String,
}
