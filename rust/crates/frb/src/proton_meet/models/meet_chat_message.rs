use flutter_rust_bridge::frb;
pub use proton_meet_chat::domain::models::chat_message::MeetChatMessage;

#[frb(mirror(MeetChatMessage))]
pub struct _MeetChatMessage {
    pub id: String,
    pub timestamp: i64,
    pub identity: String,
    pub name: String,
    pub seen: bool,
    pub message: String,
}
