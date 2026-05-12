#[cfg(target_family = "wasm")]
use wasm_bindgen::prelude::wasm_bindgen;

/// Fragment prefix used by Proton Meet share links, e.g. `#pwd-XXXXXXXXXXXX`.
pub const URL_PASSWORD_PREFIX: &str = "#pwd-";
/// Number of password characters that follow [`URL_PASSWORD_PREFIX`].
pub const URL_PASSWORD_LENGTH: usize = 12;

/// Validates a URL fragment of the form `#pwd-XXXXXXXXXXXX`, where the password
/// is exactly [`URL_PASSWORD_LENGTH`] ASCII alphanumeric characters.
///
/// Returns `false` for `None`, missing prefix, wrong length, or non-alphanumeric
/// characters. Mirrors the previous Dart-side `isUrlPasswordValid` so Flutter
/// and Web can share a single source of truth.
pub fn is_url_password_valid(hash: Option<&str>) -> bool {
    let Some(hash) = hash else { return false };
    let Some(pw) = hash.strip_prefix(URL_PASSWORD_PREFIX) else {
        return false;
    };
    pw.len() == URL_PASSWORD_LENGTH && pw.bytes().all(|b| b.is_ascii_alphanumeric())
}

#[cfg(target_family = "wasm")]
#[wasm_bindgen(js_name = isUrlPasswordValid)]
pub fn is_url_password_valid_wasm(hash: Option<String>) -> bool {
    is_url_password_valid(hash.as_deref())
}

#[derive(Debug, thiserror::Error)]
pub enum MeetLinkError {
    #[error("Parse missing id- prefix")]
    ParseMissingId,
    #[error("Parse missing pwd- prefix")]
    ParseMissingPwd,
    #[error("Parse empty id")]
    ParseEmptyId,
    #[error("Parse empty pwd")]
    ParseEmptyPwd,
}

#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct MeetLink {
    pub id: String,
    pub pwd: String,
}

impl MeetLink {
    /// Parse the *last* `id-XXX#pwd-YYY` pair found anywhere in the input.
    /// Works for full URLs or raw tails like `id-...#pwd-...`.
    pub fn parse(input: &str) -> Result<Self, MeetLinkError> {
        let s = input.trim();

        // If it's a URL, keep the full string; we only need the last tail anyway.
        // Strategy: find the *last* "id-" then require "#pwd-" after it.
        let id_pos = s.rfind("id-").ok_or(MeetLinkError::ParseMissingId)?;

        let after_id = &s[id_pos + 3..]; // skip "id-"
        let pwd_rel = after_id
            .find("#pwd-")
            .ok_or(MeetLinkError::ParseMissingPwd)?;

        let id = &after_id[..pwd_rel];
        if id.is_empty() {
            return Err(MeetLinkError::ParseEmptyId);
        }

        let after_pwd = &after_id[pwd_rel + 5..]; // skip "#pwd-"
        if after_pwd.is_empty() {
            return Err(MeetLinkError::ParseEmptyPwd);
        }

        // Take pwd until the string ends (fragment is already the end in URLs).
        // If you ever expect trailing junk, you can stop at the next delimiter.
        let pwd = after_pwd;

        Ok(MeetLink {
            id: id.to_string(),
            pwd: pwd.to_string(),
        })
    }

    /// Helper to format the canonical tail.
    pub fn to_tail(&self) -> String {
        format!("id-{}#pwd-{}", self.id, self.pwd)
    }
}

/// Async wrapper that returns Option<MeetLink> like your original:
pub async fn parse_meeting_link(link: String) -> Result<Option<MeetLink>, MeetLinkError> {
    match MeetLink::parse(&link) {
        Ok(m) => Ok(Some(m)),
        Err(e) => Err(e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_full_guest_join_url() {
        let s = "https://xxxxxx.xxxx.xxxx/guest/join/id-9B3FF26AN1#pwd-ODqAJEoaAaZX";
        let ml = MeetLink::parse(s).unwrap();
        assert_eq!(ml.id, "9B3FF26AN1");
        assert_eq!(ml.pwd, "ODqAJEoaAaZX");
    }

    #[test]
    fn parses_full_u_join_url() {
        let s = "https://xxxxxx.xxxx.xxxx/u/7/join/id-9B3FF26AN1#pwd-ODqAJEoaAaZX";
        let ml = MeetLink::parse(s).unwrap();
        assert_eq!(ml.id, "9B3FF26AN1");
        assert_eq!(ml.pwd, "ODqAJEoaAaZX");
    }

    #[test]
    fn parses_raw_tail_only() {
        let s = "id-9B3FF26AN1#pwd-ODqAJEoaAaZX";
        let ml = MeetLink::parse(s).unwrap();
        assert_eq!(ml.id, "9B3FF26AN1");
        assert_eq!(ml.pwd, "ODqAJEoaAaZX");
    }

    #[test]
    fn takes_last_pair_if_multiple_present() {
        let s = "https://host/a/join/id-OLD#pwd-OLD_MORE  some text  id-NEW#pwd-NEWPWD";
        let ml = MeetLink::parse(s).unwrap();
        assert_eq!(ml.id, "NEW");
        assert_eq!(ml.pwd, "NEWPWD");
    }

    #[test]
    fn errors_when_missing_parts() {
        assert!(MeetLink::parse("nope").is_err());
        assert!(MeetLink::parse("id-ONLY_NO_PWD").is_err());
        assert!(MeetLink::parse("#pwd-ONLY_NO_ID").is_err());
        assert!(MeetLink::parse("id-#pwd-abc").is_err()); // empty id
        assert!(MeetLink::parse("id-abc#pwd-").is_err()); // empty pwd
    }

    #[test]
    fn url_password_valid_accepts_canonical_fragment() {
        assert!(is_url_password_valid(Some("#pwd-ODqAJEoaAaZX")));
        assert!(is_url_password_valid(Some("#pwd-aaaaaaaaaaaa")));
        assert!(is_url_password_valid(Some("#pwd-000000000000")));
        assert!(is_url_password_valid(Some("#pwd-AbCdEf123456")));
    }

    #[test]
    fn url_password_invalid_rejects_bad_input() {
        assert!(!is_url_password_valid(None));
        assert!(!is_url_password_valid(Some("")));
        assert!(!is_url_password_valid(Some("ODqAJEoaAaZX"))); // missing prefix
        assert!(!is_url_password_valid(Some("pwd-ODqAJEoaAaZX"))); // missing '#'
        assert!(!is_url_password_valid(Some("#pwd-"))); // empty pwd
        assert!(!is_url_password_valid(Some("#pwd-short"))); // < 12
        assert!(!is_url_password_valid(Some("#pwd-ODqAJEoaAaZXX"))); // > 12
        assert!(!is_url_password_valid(Some("#pwd-ODqAJEoaAa-X"))); // non-alphanumeric
        assert!(!is_url_password_valid(Some("#pwd-ODqAJEoaAa X"))); // space
        assert!(!is_url_password_valid(Some("#pwd-ODqAJEoaAaZé"))); // non-ASCII
    }
}
