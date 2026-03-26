use std::fmt;

use crate::errors::core::MeetCoreError;

pub const ANONYMOUS_USER_IDENTIFIER: &str = "anonymous@anonymous.invalid";

/// Represents a parsed mimi subject with its components
/// Format: mimi://{host}/d/{user_identifier}/{device_id}
/// where user_identifier is:
/// - Primary email for Proton users with email
/// - Username for Proton users without email
/// - "{device_id}@anonymous.invalid" for guest users (device_id is embedded in identifier)
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MimiSubject {
    pub mimi_host: String,
    pub user_identifier: String,
    pub mimi_device_id: String,
}

impl MimiSubject {
    /// Creates a new MimiSubject
    pub fn new(mimi_host: String, user_identifier: String, mimi_device_id: String) -> Self {
        Self {
            mimi_host,
            user_identifier,
            mimi_device_id,
        }
    }

    /// Parses a mimi subject string into components
    /// Expected format: mimi://{host}/d/{user_identifier}/{device_id}
    /// where user_identifier is email, username, or "anonymous@anonymous.invalid" (which gets converted to "{device_id}@anonymous.invalid")
    pub fn parse(subject: &str) -> Result<Self, MeetCoreError> {
        if subject.is_empty() {
            return Err(MeetCoreError::InvalidInput {
                field: "mimi_subject".to_string(),
                reason: "Mimi subject cannot be empty".to_string(),
            });
        }

        // Parse the URI using a simple approach to avoid adding dependencies
        if !subject.starts_with("mimi://") {
            return Err(MeetCoreError::InvalidInput {
                field: "mimi_subject".to_string(),
                reason: "Mimi subject must start with 'mimi://'".to_string(),
            });
        }

        // Remove the scheme
        let without_scheme = &subject[7..]; // Remove "mimi://"

        // Find the first slash to separate host from path
        let Some(first_slash) = without_scheme.find('/') else {
            return Err(MeetCoreError::InvalidInput {
                field: "mimi_subject".to_string(),
                reason: "Mimi subject missing path component".to_string(),
            });
        };

        let mimi_host = without_scheme[..first_slash].to_string();
        if mimi_host.is_empty() {
            return Err(MeetCoreError::InvalidInput {
                field: "mimi_host".to_string(),
                reason: "Mimi host cannot be empty".to_string(),
            });
        }

        let path = &without_scheme[first_slash + 1..];
        let path_parts: Vec<&str> = path.split('/').collect();

        // Expected format: d/{user_identifier}/{device_id}
        if path_parts.len() != 3 {
            return Err(MeetCoreError::InvalidInput {
                field: "mimi_subject".to_string(),
                reason: format!(
                    "Mimi subject path must have exactly 3 parts (d/user_identifier/device_id), got {} parts",
                    path_parts.len()
                ),
            });
        }

        // Check if first part is 'd'
        if path_parts[0] != "d" {
            return Err(MeetCoreError::InvalidInput {
                field: "mimi_subject".to_string(),
                reason: "Mimi subject path must start with 'd' for device subjects".to_string(),
            });
        }

        let user_identifier = path_parts[1];
        if user_identifier.is_empty() {
            return Err(MeetCoreError::InvalidInput {
                field: "user_identifier".to_string(),
                reason: "User identifier cannot be empty".to_string(),
            });
        }

        let mimi_device_id = path_parts[2];
        if mimi_device_id.is_empty() {
            return Err(MeetCoreError::InvalidInput {
                field: "mimi_device_id".to_string(),
                reason: "Mimi device ID cannot be empty".to_string(),
            });
        }

        // For anonymous users, update the user_identifier to include the device_id
        let user_identifier = if user_identifier == ANONYMOUS_USER_IDENTIFIER {
            format!("{mimi_device_id}@anonymous.invalid")
        } else {
            user_identifier.to_string()
        };

        Ok(Self::new(
            mimi_host,
            user_identifier,
            mimi_device_id.to_string(),
        ))
    }

    /// Returns the host component
    pub fn host(&self) -> &str {
        &self.mimi_host
    }

    /// Returns the user identifier component (email, username, or anonymous)
    pub fn user_identifier(&self) -> &str {
        &self.user_identifier
    }

    /// Returns the device ID component
    pub fn device_id(&self) -> &str {
        &self.mimi_device_id
    }

    /// Reconstructs the mimi subject string from components
    pub fn to_subject_string(&self) -> String {
        format!(
            "mimi://{}/d/{}/{}",
            self.mimi_host, self.user_identifier, self.mimi_device_id
        )
    }
}

impl fmt::Display for MimiSubject {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_subject_string())
    }
}

impl std::str::FromStr for MimiSubject {
    type Err = MeetCoreError;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::parse(s)
    }
}

/// Convenience function to parse a mimi subject and extract components
pub fn parse_mimi_subject(subject: &str) -> Result<(String, String, String), MeetCoreError> {
    let parsed = MimiSubject::parse(subject)?;
    Ok((
        parsed.host().to_string(),
        parsed.user_identifier().to_string(),
        parsed.device_id().to_string(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_valid_mimi_subject() {
        let subject = "mimi://example.com/d/user@example.com/device456";
        let parsed = MimiSubject::parse(subject).unwrap();

        assert_eq!(parsed.host(), "example.com");
        assert_eq!(parsed.user_identifier(), "user@example.com");
        assert_eq!(parsed.device_id(), "device456");
    }

    #[test]
    fn test_parse_with_proton_email() {
        let subject = "mimi://meet.proton.me/d/alice@proton.me/GzAHoALHa6pUQI3ZbH0CmQ";
        let parsed = MimiSubject::parse(subject).unwrap();

        assert_eq!(parsed.host(), "meet.proton.me");
        assert_eq!(parsed.user_identifier(), "alice@proton.me");
        assert_eq!(parsed.device_id(), "GzAHoALHa6pUQI3ZbH0CmQ");
    }

    #[test]
    fn test_parse_with_username() {
        let subject = "mimi://meet.proton.me/d/alice/GzAHoALHa6pUQI3ZbH0CmQ";
        let parsed = MimiSubject::parse(subject).unwrap();

        assert_eq!(parsed.host(), "meet.proton.me");
        assert_eq!(parsed.user_identifier(), "alice");
        assert_eq!(parsed.device_id(), "GzAHoALHa6pUQI3ZbH0CmQ");
    }

    #[test]
    fn test_parse_with_anonymous_user() {
        let subject = "mimi://meet.proton.me/d/anonymous@anonymous.invalid/GzAHoALHa6pUQI3ZbH0CmQ";
        let parsed = MimiSubject::parse(subject).unwrap();

        assert_eq!(parsed.host(), "meet.proton.me");
        // Anonymous user identifier should be updated to include device_id
        assert_eq!(
            parsed.user_identifier(),
            "GzAHoALHa6pUQI3ZbH0CmQ@anonymous.invalid"
        );
        assert_eq!(parsed.device_id(), "GzAHoALHa6pUQI3ZbH0CmQ");
    }

    #[test]
    fn test_to_subject_string_with_anonymous() {
        // When generating a subject string for anonymous users, it uses the device_id in user_identifier
        let subject = MimiSubject::new(
            "meet.proton.me".to_string(),
            "GzAHoALHa6pUQI3ZbH0CmQ@anonymous.invalid".to_string(),
            "GzAHoALHa6pUQI3ZbH0CmQ".to_string(),
        );

        assert_eq!(
            subject.to_subject_string(),
            "mimi://meet.proton.me/d/GzAHoALHa6pUQI3ZbH0CmQ@anonymous.invalid/GzAHoALHa6pUQI3ZbH0CmQ"
        );
    }

    #[test]
    fn test_to_subject_string() {
        let subject = MimiSubject::new(
            "example.com".to_string(),
            "user@example.com".to_string(),
            "device456".to_string(),
        );

        assert_eq!(
            subject.to_subject_string(),
            "mimi://example.com/d/user@example.com/device456"
        );
    }

    #[test]
    fn test_display_trait() {
        let subject = MimiSubject::new(
            "example.com".to_string(),
            "user@example.com".to_string(),
            "device456".to_string(),
        );

        assert_eq!(
            subject.to_string(),
            "mimi://example.com/d/user@example.com/device456"
        );
    }

    #[test]
    fn test_from_str_trait() {
        let subject_str = "mimi://example.com/d/user@example.com/device456";
        let parsed: MimiSubject = subject_str.parse().unwrap();

        assert_eq!(parsed.host(), "example.com");
        assert_eq!(parsed.user_identifier(), "user@example.com");
        assert_eq!(parsed.device_id(), "device456");
    }

    #[test]
    fn test_parse_empty_string() {
        let result = MimiSubject::parse("");
        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("cannot be empty"));
    }

    #[test]
    fn test_parse_invalid_scheme() {
        let result = MimiSubject::parse("http://example.com/d/user/device");
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("must start with 'mimi://'"));
    }

    #[test]
    fn test_parse_missing_path() {
        let result = MimiSubject::parse("mimi://example.com");
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("missing path component"));
    }

    #[test]
    fn test_parse_empty_host() {
        let result = MimiSubject::parse("mimi:///d/user/device");
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("host cannot be empty"));
    }

    #[test]
    fn test_parse_wrong_path_parts_count() {
        let result = MimiSubject::parse("mimi://example.com/d/user");
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("must have exactly 3 parts"));
    }

    #[test]
    fn test_parse_invalid_device_code() {
        let result = MimiSubject::parse("mimi://example.com/u/user/device");
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("must start with 'd'"));
    }

    #[test]
    fn test_parse_empty_user_identifier() {
        let result = MimiSubject::parse("mimi://example.com/d//device");
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("User identifier cannot be empty"));
    }

    #[test]
    fn test_parse_empty_device_id() {
        let result = MimiSubject::parse("mimi://example.com/d/user/");
        assert!(result.is_err());
        assert!(result
            .unwrap_err()
            .to_string()
            .contains("device ID cannot be empty"));
    }

    #[test]
    fn test_equality() {
        let subject1 = MimiSubject::new(
            "example.com".to_string(),
            "user@example.com".to_string(),
            "device456".to_string(),
        );
        let subject2 =
            MimiSubject::parse("mimi://example.com/d/user@example.com/device456").unwrap();

        assert_eq!(subject1, subject2);
    }

    #[test]
    fn test_parse_mimi_subject_convenience_function() {
        let subject = "mimi://example.com/d/user@example.com/device456";
        let (host, user_identifier, device_id) = parse_mimi_subject(subject).unwrap();

        assert_eq!(host, "example.com");
        assert_eq!(user_identifier, "user@example.com");
        assert_eq!(device_id, "device456");
    }
}
