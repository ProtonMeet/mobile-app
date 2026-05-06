use secrecy::{ExposeSecret, SecretString};

pub struct AccessToken(SecretString);

impl AccessToken {
    pub fn new(access_token: String) -> Self {
        Self(access_token.into())
    }

    pub fn expose_secret(&self) -> &str {
        self.0.expose_secret()
    }
}

impl From<String> for AccessToken {
    fn from(access_token: String) -> Self {
        Self(access_token.into())
    }
}

impl From<&str> for AccessToken {
    fn from(access_token: &str) -> Self {
        Self(access_token.into())
    }
}
