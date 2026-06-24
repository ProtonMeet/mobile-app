//! WASM-only tests (browser / wasm-bindgen-test).

use crate::app::App;
use crate::domain::user::ports::user_service::UserService;
use wasm_bindgen::JsValue;
use wasm_bindgen_test::*;

#[wasm_bindgen_test]
#[ignore = "requires proton.black credentials and live websocket"]
async fn login_and_logout() -> Result<(), JsValue> {
    let app = App::new_wasm(
        "https://proton.black/api".to_string(),
        "macos-meet@0.0.1".to_string(),
        "Mozilla/5.0".to_string(),
        "".to_string(),
        "localhost:8090".to_string(),
        "".into(),
        "".into(),
        "".into(),
    )
    .await?;

    let user = app
        .user_service
        .read()
        .await
        .login("bart", "bart")
        .await
        .map_err(crate::errors::core::MeetCoreError::from)?;

    assert!(!user.1.id.to_string().is_empty());
    assert!(!user.1.email.is_empty());

    app.logout(user.1.id.to_string()).await?;

    Ok(())
}

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
