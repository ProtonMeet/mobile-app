use serde::Deserialize;

/// `GET /core/v4/settings` response envelope.
///
/// The API returns many fields under `UserSettings` (Email, Locale, CrashReports,
/// DeviceRecovery, etc.). We intentionally deserialize only what Meet needs today.
/// See [`crate::domain::user::models::ProtonUserSettings`] for a fuller account-settings model.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "PascalCase")]
pub struct ProtonSettingsResponse {
    pub code: u32,
    pub user_settings: ProtonSettingsUserSettingsDto,
}

/// Subset of `UserSettings` from `/core/v4/settings`.
///
/// Extra JSON fields are ignored by serde. Add fields here when Meet starts
/// consuming them; until then keep this minimal to avoid maintaining unused bindings.
#[derive(Debug, Clone, Deserialize, Default)]
#[serde(rename_all = "PascalCase")]
pub struct ProtonSettingsUserSettingsDto {
    /// Account telemetry opt-in (`1` = enabled, `0` = disabled). Used to gate Sentry.
    #[serde(default)]
    pub telemetry: u32,
}

#[cfg(test)]
mod tests {
    use super::ProtonSettingsResponse;

    #[test]
    fn proton_settings_response_parses_telemetry_enabled() {
        let json = r#"{
            "Code": 1000,
            "UserSettings": {
                "Telemetry": 1,
                "CrashReports": 1
            }
        }"#;
        let response: ProtonSettingsResponse =
            serde_json::from_str(json).expect("parse proton settings");
        assert_eq!(response.code, 1000);
        assert_eq!(response.user_settings.telemetry, 1);
    }

    #[test]
    fn proton_settings_response_defaults_telemetry_when_missing() {
        let json = r#"{
            "Code": 1000,
            "UserSettings": {}
        }"#;
        let response: ProtonSettingsResponse =
            serde_json::from_str(json).expect("parse proton settings");
        assert_eq!(response.user_settings.telemetry, 0);
    }
}
