//! Shared assertions and helpers for muon support tests (native + WASM).

use muon::app::AppVersion;
use muon::env::Env;
use muon::{App, Environment};

use super::{
    MeetClient, MeetClientExt, MeetSession, build_meet_client, environment_from_str,
    is_prod_environment, parse_environment,
};

/// Standard test app identity (valid `macos-meet@…` form).
pub fn test_app() -> App {
    App::new("macos-meet@0.0.1")
        .unwrap()
        .with_user_agent("test-agent")
}

/// `prod`, `atlas`, and `atlas:scientist` parse consistently.
pub fn assert_standard_environments_parse() {
    assert!(matches!(
        parse_environment("prod").unwrap(),
        Environment::Prod(_)
    ));
    assert!(matches!(
        parse_environment("atlas").unwrap(),
        Environment::Atlas(_)
    ));
    assert!(matches!(
        parse_environment("atlas:scientist").unwrap(),
        Environment::Scientist(_)
    ));
    assert!(matches!(environment_from_str("prod"), Environment::Prod(_)));
    assert!(matches!(
        environment_from_str("atlas"),
        Environment::Atlas(_)
    ));
}

/// Scientist atlas resolves the meet API host used in CI/dev.
pub fn assert_scientist_meet_api_host() {
    let env = environment_from_str("atlas:scientist");
    let Environment::Scientist(scientist) = env else {
        panic!("expected scientist environment");
    };
    let app_version: AppVersion = "macos-meet@0.0.1".parse().unwrap();
    let servers = scientist.servers(&app_version);
    assert_eq!(
        servers
            .first()
            .map(|server| std::convert::AsRef::<str>::as_ref(server.host())),
        Some("meet-api.scientist.proton.black")
    );
}

pub fn assert_is_prod_environment() {
    assert!(is_prod_environment("prod"));
    assert!(!is_prod_environment("atlas"));
    assert!(!is_prod_environment("atlas:scientist"));
}

/// Unknown env strings fail `parse_environment` (strict parse path).
pub fn assert_invalid_environment_rejected() {
    assert!(parse_environment("not-a-real-env").is_err());
}

#[cfg(not(target_arch = "wasm32"))]
pub fn build_test_client() -> MeetClient {
    use super::super::auth_store::AuthStore;

    build_meet_client(
        test_app(),
        environment_from_str("atlas"),
        AuthStore::atlas(None),
        None,
    )
    .expect("native test client")
}

#[cfg(target_arch = "wasm32")]
pub fn build_test_client() -> MeetClient {
    build_meet_client(test_app(), environment_from_str("atlas"), None).expect("wasm test client")
}

/// Build client + default session (shared smoke path on both targets).
pub async fn build_test_client_with_session() -> MeetSession {
    let client = build_test_client();
    client.default_session().await.expect("default session")
}
