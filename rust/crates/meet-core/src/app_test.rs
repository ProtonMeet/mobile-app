#[cfg(test)]
#[cfg(not(target_family = "wasm"))]
mod tests {
    use crate::app::*;
    use crate::domain::user::models::MeetingType;
    use crate::domain::user::ports::user_service::UserService;
    use crate::infra::auth_store::AuthStore;
    use std::sync::Arc;

    use muon::client::Auth;
    use tempfile::tempdir;

    // Test app creation
    #[tokio::test]
    #[ignore]
    async fn test_app_creation() {
        use crate::infra::adapters::storage::user_key_provider_adapter::UserKeyProviderAdapter;
        let user_key_provider = Arc::new(UserKeyProviderAdapter::new());
        let app_result = App::new(
            "https://popper.proton.black/api".to_string(),
            "macos-meet@0.0.1".to_string(),
            "Mac OS X 10.15.7".to_string(),
            "test/db_path".to_string(),
            Box::new(AuthStore::atlas(None)),
            "popper.proton.black/api".to_string(),
            "localhost:8090".to_string(),
            None,
            user_key_provider,
        )
        .await;

        assert!(app_result.is_ok(), "App creation should succeed");
    }

    #[cfg(not(target_family = "wasm"))]
    // Test login functionality (requires valid credentials)
    #[tokio::test]
    #[ignore]
    async fn test_login_and_logout() -> Result<(), anyhow::Error> {
        use muon::client::Auth;

        let temp_dir = tempdir()?;
        let db_path = temp_dir
            .path()
            .to_str()
            .ok_or_else(|| anyhow::anyhow!("Failed to convert path to string"))?
            .to_string();

        println!("db_path: {db_path}");

        use crate::infra::adapters::storage::user_key_provider_adapter::UserKeyProviderAdapter;
        let user_key_provider = Arc::new(UserKeyProviderAdapter::new());
        let app = match App::new(
            "https://proton.black/api".to_string(),
            "macos-meet@0.1.1".to_string(),
            "Mac OS X 10.15.7".to_string(),
            db_path,
            Box::new(AuthStore::from_custom_env_str(
                "https://proton.black/api".to_string(),
                Arc::new(tokio::sync::Mutex::new(Auth::None)),
            )),
            "proton.black/api".to_string(),
            "".to_string(),
            None,
            user_key_provider,
        )
        .await
        {
            Ok(app) => app,
            Err(e) => {
                panic!("Failed to create app: {e:?}");
            }
        };

        let login_result = app.user_service.read().await.login("bart", "bart").await;

        let user_id = match &login_result {
            Ok((_, user_data, _, _)) => {
                println!("Login successful for user: {user_data:?}");
                assert!(
                    !user_data.id.to_string().is_empty(),
                    "User ID should not be empty"
                );
                assert!(
                    !user_data.email.is_empty(),
                    "User email should not be empty"
                );
                user_data.id.to_string()
            }
            Err(e) => {
                println!("Login failed: {e:?}");
                panic!("Login should succeed with valid credentials");
            }
        };

        assert!(
            login_result.is_ok(),
            "Login should succeed with valid credentials"
        );

        let logout_result = app.logout(user_id).await;
        assert!(logout_result.is_ok(), "Logout should succeed");

        Ok(())
    }

    #[tokio::test]
    #[ignore]
    async fn test_join_meeting() -> Result<(), anyhow::Error> {
        use crate::infra::adapters::storage::user_key_provider_adapter::UserKeyProviderAdapter;
        let user_key_provider = Arc::new(UserKeyProviderAdapter::new());
        let app = App::new(
            // "https://localhost/api".to_string(),
            "https://anning.proton.black/api".to_string(),
            "macos-meet@0.0.1".to_string(),
            "Mac OS X 10.15.7".to_string(),
            "test/db_path".to_string(),
            Box::new(AuthStore::atlas(Some("anning".to_string()))),
            "anning.proton.black/api".to_string(),
            "mls.anning.proton.black".to_string(),
            None,
            user_key_provider,
        )
        .await?;

        let meeting_link_name = "YYDVC4V6D4";
        let meeting_link_p = "ZmdeJZE6BEud";
        let user_id = format!("user_{}", rand::random::<u32>());

        let meet_info = app
            .authenticate_meeting_link(
                meeting_link_name.to_string(),
                meeting_link_p.to_string(),
                user_id.clone(),
            )
            .await;
        println!("meet_info: {meet_info:?}");
        assert!(meet_info.is_ok(), "Join meeting should succeed");

        app.join_meeting_with_access_token(
            meet_info?.access_token,
            meeting_link_name.to_string(),
            meeting_link_p.to_string(),
            true,
            None,
        )
        .await?;

        Ok(())
    }

    #[tokio::test]
    #[ignore]
    async fn test_create_meeting() -> Result<(), anyhow::Error> {
        let temp_dir = tempdir()?;
        let db_path = temp_dir
            .path()
            .to_str()
            .ok_or_else(|| anyhow::anyhow!("Failed to convert path to string"))?
            .to_string();

        use crate::infra::adapters::storage::user_key_provider_adapter::UserKeyProviderAdapter;
        let user_key_provider = Arc::new(UserKeyProviderAdapter::new());
        let app = App::new(
            "https://anning.proton.black/api".to_string(),
            "macos-meet@0.0.9".to_string(),
            "Mac OS X 10.15.7".to_string(),
            db_path,
            Box::new(AuthStore::from_custom_env_str(
                "https://anning.proton.black/api".to_string(),
                Arc::new(tokio::sync::Mutex::new(Auth::None)),
            )),
            "anning.proton.black/api".to_string(),
            "mls.anning.proton.black".to_string(),
            None,
            user_key_provider,
        )
        .await?;

        let user_data = app.login("bart".to_string(), "bart".to_string()).await?;

        println!("Login successful for user: {}", user_data.user.id);
        assert!(
            !user_data.user.id.to_string().is_empty(),
            "User ID should not be empty"
        );
        assert!(
            !user_data.user.email.is_empty(),
            "User email should not be empty"
        );

        let result = app
            .create_meeting(
                "test".to_string(),
                false,
                MeetingType::Instant,
                None,
                None,
                None,
                None,
                None,
            )
            .await;
        println!("result: {result:?}");
        assert!(result.is_ok(), "Create meeting should succeed");
        let meeting = result?;

        let meet_info = app
            .authenticate_meeting_link(
                meeting.meeting_link_name,
                meeting.meeting_password.clone(),
                "new joiner".to_string(),
            )
            .await?;

        app.join_meeting_with_access_token(
            meet_info.access_token,
            meet_info.meet_link_name,
            meeting.meeting_password,
            true,
            None,
        )
        .await?;

        Ok(())
    }
}

#[cfg(all(test, target_family = "wasm"))]
mod wasm_tests {
    use crate::app::*;
    use crate::domain::user::ports::user_service::UserService;
    use wasm_bindgen::JsValue;
    use wasm_bindgen_test::*;

    #[wasm_bindgen_test]
    #[ignore]
    async fn test_login_and_logout() -> Result<(), JsValue> {
        // In WASM environment, we don't need a file path
        let db_path = "".to_string();

        let app = App::new_wasm(
            "https://proton.black/api".to_string(),
            "macos-meet@0.0.1".to_string(),
            "Mozilla/5.0".to_string(),
            db_path,
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
            .map_err(|e| crate::errors::core::MeetCoreError::from(e))?;

        println!("Login successful for user: {}", user.1.id);
        assert!(
            !user.1.id.to_string().is_empty(),
            "User ID should not be empty"
        );
        assert!(!user.1.email.is_empty(), "User email should not be empty");

        let logout_result = app.logout(user.1.id.to_string()).await;
        assert!(logout_result.is_ok(), "Logout should succeed");

        Ok(())
    }

    #[wasm_bindgen_test]
    async fn test_login_test_for_error_handling() {
        let db_path = "".to_string();
        let app = App::new_wasm(
            "https://proton.black/api".to_string(),
            "macos-meet@1.2.0".to_string(),
            "Mozilla/5.0".to_string(),
            db_path,
            "localhost:8090".to_string(),
            "".into(),
            "".into(),
            "".into(),
        )
        .await
        .unwrap();
        // when calling login_test, the error is generic and it will auto convert to jsvalue
        let result = app.test_wasm().await;
        println!("result: {:?}", result);
        assert!(result.is_err(), "Test should fail");
    }
}
