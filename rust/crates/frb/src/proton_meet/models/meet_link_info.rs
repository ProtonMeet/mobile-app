use proton_meet_core::domain::user::models::meet_link_info::MeetLinkInfo;
use proton_meet_core::domain::user::models::meeting::CustomPasswordSetting;

/// FFI-friendly handshake info returned by `/meet/v1/meetings/links/{token}/info`.
///
/// Flutter inspects [`Self::custom_password`] to decide whether to prompt the
/// user for a custom password before SRP authentication.
#[derive(Debug, Clone)]
pub struct FrbMeetLinkInfo {
    pub modulus: String,
    pub salt: String,
    pub server_ephemeral: String,
    pub srp_session: String,
    pub version: u32,
    /// `true` when the meeting requires a custom password in addition to the URL
    /// password. When `true`, Flutter must show the password prompt and combine
    /// the user input with the URL password before calling `authenticate_meeting_link`.
    pub requires_custom_password: bool,
}

impl From<MeetLinkInfo> for FrbMeetLinkInfo {
    fn from(info: MeetLinkInfo) -> Self {
        Self {
            modulus: info.modulus,
            salt: info.salt,
            server_ephemeral: info.server_ephemeral,
            srp_session: info.srp_session,
            version: info.version,
            requires_custom_password: matches!(
                info.custom_password,
                CustomPasswordSetting::PasswordSet
            ),
        }
    }
}
