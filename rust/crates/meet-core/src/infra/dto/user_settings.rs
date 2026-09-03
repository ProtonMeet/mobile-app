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
    #[serde(rename = "AddressID")]
    pub address_id: Option<String>,
    #[serde(default)]
    pub waiting_room: u8,
}

impl From<UserSettingsResponse> for UserSettings {
    fn from(response: UserSettingsResponse) -> Self {
        UserSettings {
            address_id: response.user_settings.address_id,
            waiting_room: response.user_settings.waiting_room == 1,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "PascalCase")]
pub struct UpdateUserSettingsWaitingRoomRequest {
    pub waiting_room: u8,
}

impl UpdateUserSettingsWaitingRoomRequest {
    pub fn new(enable: bool) -> Self {
        Self {
            waiting_room: u8::from(enable),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_waiting_room_enabled_as_true() {
        let json = r#"{
            "UserSettings": {
                "AddressID": "address-1",
                "WaitingRoom": 1
            },
            "Code": 1000
        }"#;
        let response: UserSettingsResponse =
            serde_json::from_str(json).expect("parse user settings");
        let settings = UserSettings::from(response);
        assert!(settings.waiting_room);
    }

    #[test]
    fn parses_waiting_room_disabled_as_false() {
        let json = r#"{
            "UserSettings": {
                "AddressID": "address-1",
                "WaitingRoom": 0
            },
            "Code": 1000
        }"#;
        let response: UserSettingsResponse =
            serde_json::from_str(json).expect("parse user settings");
        let settings = UserSettings::from(response);
        assert!(!settings.waiting_room);
    }

    #[test]
    fn update_request_serializes_enable_to_one() {
        let json = serde_json::to_string(&UpdateUserSettingsWaitingRoomRequest::new(true))
            .expect("serialize request");
        assert_eq!(json, r#"{"WaitingRoom":1}"#);
    }

    #[test]
    fn update_request_serializes_disable_to_zero() {
        let json = serde_json::to_string(&UpdateUserSettingsWaitingRoomRequest::new(false))
            .expect("serialize request");
        assert_eq!(json, r#"{"WaitingRoom":0}"#);
    }

    #[test]
    fn defaults_waiting_room_to_false_when_missing() {
        let json = r#"{
            "UserSettings": {
                "AddressID": "address-1"
            },
            "Code": 1000
        }"#;
        let response: UserSettingsResponse =
            serde_json::from_str(json).expect("parse user settings");
        let settings = UserSettings::from(response);
        assert!(!settings.waiting_room);
    }

    #[test]
    fn parses_null_address_id() {
        let json = r#"{
            "UserSettings": {
                "AddressID": null,
                "WaitingRoom": 1
            },
            "Code": 1000
        }"#;
        let response: UserSettingsResponse =
            serde_json::from_str(json).expect("parse user settings");
        let settings = UserSettings::from(response);
        assert_eq!(settings.address_id, None);
        assert!(settings.waiting_room);
    }

    #[test]
    fn ignores_deprecated_meeting_id() {
        for meeting_id in [r#""meeting-1""#, r#""""#, "null"] {
            let json = format!(
                r#"{{
                    "UserSettings": {{
                        "MeetingID": {meeting_id},
                        "AddressID": "address-1",
                        "WaitingRoom": 1
                    }},
                    "Code": 1000
                }}"#
            );
            let response: UserSettingsResponse =
                serde_json::from_str(&json).expect("parse user settings");
            let settings = UserSettings::from(response);
            assert_eq!(settings.address_id, Some("address-1".to_string()));
            assert!(settings.waiting_room);
        }
    }
}
