use secrecy::{ExposeSecret, SecretString};

#[derive(Debug, Clone)]
pub struct MeetingSessionKey(pub SecretString);

impl MeetingSessionKey {
    pub fn new(session_key: SecretString) -> Self {
        Self(session_key)
    }

    pub fn expose_secret(&self) -> &str {
        self.0.expose_secret()
    }
}

impl From<String> for MeetingSessionKey {
    fn from(session_key: String) -> Self {
        Self(session_key.into())
    }
}

impl From<&str> for MeetingSessionKey {
    fn from(session_key: &str) -> Self {
        Self(session_key.into())
    }
}
