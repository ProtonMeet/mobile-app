//! WASM-only tests (browser / wasm-bindgen-test).

use crate::app::App;
use wasm_bindgen_test::*;

#[wasm_bindgen_test]
async fn login_test_for_error_handling() {
    let app = App::new_wasm(
        "https://proton.black/api".to_string(),
        "macos-meet@1.2.0".to_string(),
        "Mozilla/5.0".to_string(),
        "".to_string(),
        "localhost:8090".to_string(),
        "".into(),
        "".into(),
        "".into(),
    )
    .await
    .unwrap();

    let result = app.test_wasm().await;
    assert!(
        result.is_err(),
        "TestFunctions::test_wasm should return InvalidUrl error"
    );
}
