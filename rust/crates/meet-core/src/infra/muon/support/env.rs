//! Proton environment string parsing (`prod`, `atlas`, `atlas:name`, custom dev URLs).

use muon::env::ParseEnvIdErr;
use muon::Environment;

/// Parse a standard Proton environment string (`prod`, `atlas`, `atlas:name`).
pub fn parse_environment(env: &str) -> Result<Environment, ParseEnvIdErr> {
    env.parse()
}

/// Parse a standard environment string, or build a custom environment for dev URLs.
#[cfg(feature = "allow-dangerous-env")]
pub fn environment_from_str(env: &str) -> Environment {
    env.parse().unwrap_or_else(|_| {
        Environment::new_custom(MeetCustomEnv {
            inner: env.to_string(),
        })
    })
}

#[cfg(not(feature = "allow-dangerous-env"))]
pub fn environment_from_str(env: &str) -> Environment {
    env.parse().expect("invalid environment string")
}

/// Whether `env` resolves to production (used for TLS pinning).
pub fn is_prod_environment(env: &str) -> bool {
    matches!(env.parse::<Environment>(), Ok(Environment::Prod(_)))
}

#[cfg(feature = "allow-dangerous-env")]
pub(crate) struct MeetCustomEnv {
    pub(crate) inner: String,
}

#[cfg(feature = "allow-dangerous-env")]
impl muon::env::Env for MeetCustomEnv {
    fn servers(&self, _: &muon::app::AppVersion) -> Vec<muon::common::Server> {
        vec![self.inner.as_str().parse().expect("Invalid server address")]
    }

    fn ar_pins(&self) -> Option<&muon::tls::pins::TlsPinSet> {
        None
    }

    fn api_pins(&self) -> Option<&muon::tls::pins::TlsPinSet> {
        None
    }
}
