use secrecy::{ExposeSecret, SecretString};

pub struct MeetingPassword(SecretString);

impl MeetingPassword {
    pub fn new(meeting_password: String) -> Self {
        Self(meeting_password.into())
    }

    pub fn expose_secret(&self) -> &str {
        self.0.expose_secret()
    }
}

impl From<String> for MeetingPassword {
    fn from(meeting_password: String) -> Self {
        Self(meeting_password.into())
    }
}

impl From<&str> for MeetingPassword {
    fn from(meeting_password: &str) -> Self {
        Self(meeting_password.into())
    }
}
