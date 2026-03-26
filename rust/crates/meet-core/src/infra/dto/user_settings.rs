use serde::{Deserialize, Serialize};

use crate::domain::user::models::user_settings::UserSettings;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct UserSettingsResponse {
    pub user_settings: UserSettingsDto,
    pub code: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct UserSettingsDto {
    #[serde(rename = "MeetingID")]
    pub meeting_id: String,
    #[serde(rename = "AddressID")]
    pub address_id: String,
}


impl From<UserSettingsResponse> for UserSettings {
    fn from(response: UserSettingsResponse) -> Self {
        UserSettings {
            meeting_id: response.user_settings.meeting_id,
            address_id: response.user_settings.address_id,
        }
    }
}
