use proton_meet_core::domain::user::models::UserSettings;

pub struct FrbUserSettings {
    pub address_id: Option<String>,
    pub waiting_room: bool,
}

impl From<UserSettings> for FrbUserSettings {
    fn from(user_settings: UserSettings) -> Self {
        Self {
            address_id: user_settings.address_id,
            waiting_room: user_settings.waiting_room,
        }
    }
}
