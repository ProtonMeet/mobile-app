#[derive(Debug, Clone)]
pub struct UserSettings {
    pub meeting_id: String,
    pub address_id: Option<String>,
    pub waiting_room: bool,
}
