use serde::{Deserialize, Serialize};

use super::{
    email_settings::EmailSettings, flags_settings::FlagsSettings,
    high_security_settings::HighSecuritySettings, password_settings::PasswordSettings,
    phone_settings::PhoneSettings, referral_settings::ReferralSettings,
    two_fa_settings::TwoFASettings,
};

/// Proton User Settings model matching the API response
#[derive(Debug, Serialize, Deserialize, Default, Clone, PartialEq)]
#[serde(rename_all = "PascalCase")]
pub struct ProtonUserSettings {
    pub email: EmailSettings,
    pub password: Option<PasswordSettings>,
    pub phone: Option<PhoneSettings>,
    #[serde(rename = "2FA")]
    pub two_fa: Option<TwoFASettings>,
    pub news: u32,
    pub locale: String,
    pub log_auth: u32,
    pub invoice_text: String,
    pub density: u32,
    pub week_start: u32,
    pub date_format: u32,
    pub time_format: u32,
    pub welcome: u32,
    pub welcome_flag: u32,
    pub early_access: u32,
    pub flags: Option<FlagsSettings>,
    pub referral: Option<ReferralSettings>,
    pub device_recovery: Option<u32>,
    pub telemetry: u32,
    pub crash_reports: u32,
    pub hide_side_panel: u32,
    pub high_security: Option<HighSecuritySettings>,
    pub session_account_recovery: u32,
}
