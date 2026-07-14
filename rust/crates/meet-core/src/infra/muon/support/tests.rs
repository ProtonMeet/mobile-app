use proton_meet_macro::unified_test;

use super::test_support;
use super::{meet_sdk_from_app, MeetClientExt, MUON_DEFAULT_SESSION_KEY};
use crate::infra::muon::environment_from_str;
#[cfg(not(target_arch = "wasm32"))]
use crate::infra::muon::AuthStore;
use muon::App;

#[cfg(all(test, target_family = "wasm"))]
use wasm_bindgen_test::wasm_bindgen_test_configure;
#[cfg(all(test, target_family = "wasm"))]
wasm_bindgen_test_configure!(run_in_browser);

// ---------------------------------------------------------------------------
// Environment parsing (native + WASM)
// ---------------------------------------------------------------------------

#[unified_test]
async fn environment_helpers() {
    test_support::assert_standard_environments_parse();
    test_support::assert_scientist_meet_api_host();
    test_support::assert_is_prod_environment();
    test_support::assert_invalid_environment_rejected();
}

#[unified_test]
async fn default_session_key_is_unit() {
    let _: () = MUON_DEFAULT_SESSION_KEY;
}

// ---------------------------------------------------------------------------
// SDK header helper (native + WASM)
// ---------------------------------------------------------------------------

#[unified_test]
async fn meet_sdk_from_app_parses_valid_version() {
    let app = App::new("macos-meet@1.2.3")
        .unwrap()
        .with_user_agent("test-agent");
    assert!(meet_sdk_from_app(&app).is_some());
}

#[unified_test]
async fn meet_sdk_from_app_rejects_invalid_app_string() {
    assert!(App::new("not-valid").is_err());
}

#[unified_test]
async fn meet_sdk_from_app_extracts_name_and_version() {
    let app = App::new("macos-meet@1.2.3").unwrap();
    let sdk = meet_sdk_from_app(&app).expect("sdk");
    assert_eq!(sdk.name(), "macos-meet");
    assert_eq!(sdk.version(), "1.2.3");
}

// ---------------------------------------------------------------------------
// Client + session (platform-specific build, shared default_session)
// ---------------------------------------------------------------------------

#[unified_test]
async fn build_client_and_default_session() {
    let session = test_support::build_test_client_with_session().await;
    let _ = session;
}

#[unified_test]
async fn default_session_is_idempotent() {
    let client = test_support::build_test_client();
    let first = client.default_session().await.unwrap();
    let second = client.default_session().await.unwrap();
    assert_eq!(first.session_key(), second.session_key());
}

#[unified_test]
async fn default_session_binds_atlas_environment() {
    let client = test_support::build_test_client();
    let session = client.default_session().await.unwrap();
    assert!(matches!(session.env(), muon::Environment::Atlas(_)));
}

#[cfg(target_arch = "wasm32")]
#[unified_test]
async fn wasm_client_uses_atlas_environment() {
    let client = test_support::build_test_client();
    let _ = client;
    let _ = environment_from_str("atlas");
}

#[cfg(not(target_arch = "wasm32"))]
#[tokio::test]
async fn native_client_with_auth_store_persistence() {
    let client = super::build_meet_client(
        test_support::test_app(),
        environment_from_str("atlas"),
        AuthStore::atlas(None),
        None,
    )
    .unwrap();
    let session = client.default_session().await.unwrap();
    let _ = session;
}
