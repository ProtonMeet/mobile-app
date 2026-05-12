use flutter_rust_bridge::frb;
use proton_meet_core::domain::user::models::meet_link::is_url_password_valid as is_url_password_valid_impl;

/// Validate a URL fragment of the form `#pwd-XXXXXXXXXXXX` (12 ASCII
/// alphanumeric characters). Returns `false` for `null`, missing prefix,
/// wrong length, or non-alphanumeric characters.
#[frb(sync)]
pub fn is_url_password_valid(hash: Option<String>) -> bool {
    is_url_password_valid_impl(hash.as_deref())
}
