use std::future::ready;

use mockall::predicate::eq;

use crate::app::test_support::{
    auth_service, build_app, build_app_with_service, default_app_state, test_address,
    test_proton_user, test_user_key, test_user_state,
};
use crate::domain::user::ports::{user_api::MockUserApi, MockUserRepository};
use crate::errors::core::MeetCoreError;
use crate::errors::login::LoginError;
use crate::infra::dto::proton_user::UserData;

const TEST_USERNAME: &str = "alice";
const TEST_PASSWORD: &str = "secret";
const TEST_USER_ID: &str = "user-1";
const TEST_2FA_CODE: &str = "123456";

fn test_proton_user_with_keys(user_id: &str) -> proton_meet_common::models::ProtonUser {
    proton_meet_common::models::ProtonUser {
        id: user_id.to_string(),
        name: "Test User".to_string(),
        email: "test@example.com".to_string(),
        keys: Some(vec![test_user_key("key-1", 1, 1)]),
        ..Default::default()
    }
}

fn login_user_data() -> UserData {
    UserData {
        user: test_proton_user_with_keys(TEST_USER_ID),
        key_salts: vec![],
    }
}

fn login_success_mocks() -> (MockUserApi, MockUserRepository) {
    let mut user_api = MockUserApi::new();
    user_api
        .expect_login()
        .with(eq(TEST_USERNAME), eq(TEST_PASSWORD))
        .once()
        .returning(|_, _| Box::pin(ready(Ok(login_user_data()))));
    user_api
        .expect_get_user_addresses()
        .once()
        .returning(|| Box::pin(ready(Ok(vec![test_address("addr-1", "test@example.com")]))));

    let mut user_repository = MockUserRepository::new();
    user_repository
        .expect_init_tables()
        .with(eq(TEST_USER_ID))
        .once()
        .returning(|_| Box::pin(ready(Ok(()))));
    user_repository
        .expect_save_user()
        .once()
        .returning(|_| Box::pin(ready(Ok(()))));
    user_repository
        .expect_save_user_keys()
        .once()
        .returning(|_, _| Box::pin(ready(Ok(()))));

    (user_api, user_repository)
}

#[tokio::test]
async fn get_user_state_returns_active_user() {
    let mut state = default_app_state();
    let expected = test_user_state("user-1", true, true);
    state.active_user = Some(expected.clone());

    let app = build_app(state).await;
    let result = app.get_user_state().await.unwrap();

    assert_eq!(result.user_data.id, expected.user_data.id);
    assert_eq!(result.user_keys.len(), expected.user_keys.len());
}

#[tokio::test]
async fn get_user_state_errors_when_no_active_user() {
    let app = build_app(default_app_state()).await;
    let err = app.get_user_state().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::NoActiveUser));
}

#[tokio::test]
async fn login_stores_active_user_on_success() {
    let (user_api, user_repository) = login_success_mocks();
    let app =
        build_app_with_service(default_app_state(), auth_service(user_api, user_repository)).await;

    let response = app
        .login(TEST_USERNAME.to_string(), TEST_PASSWORD.to_string())
        .await
        .unwrap();
    assert_eq!(response.user.id, TEST_USER_ID);

    let active = app.get_user_state().await.unwrap();
    assert_eq!(active.user_data.id, TEST_USER_ID);
    assert_eq!(active.user_addresses.len(), 1);
}

#[tokio::test]
async fn login_leaves_state_empty_on_failure() {
    let mut user_api = MockUserApi::new();
    user_api.expect_login().once().returning(|_, _| {
        Box::pin(ready(Err(LoginError::LoginFailed(
            "Invalid credentials".to_string(),
        ))))
    });

    let app = build_app_with_service(
        default_app_state(),
        auth_service(user_api, MockUserRepository::new()),
    )
    .await;

    assert!(app
        .login(TEST_USERNAME.to_string(), TEST_PASSWORD.to_string())
        .await
        .is_err());
    assert!(matches!(
        app.get_user_state().await,
        Err(MeetCoreError::NoActiveUser)
    ));
}

#[tokio::test]
async fn fetch_user_state_loads_from_local_cache() {
    let user = test_proton_user(TEST_USER_ID);
    let keys = vec![test_user_key("key-1", 1, 1)];
    let addresses = vec![test_address("addr-1", "test@example.com")];

    let mut user_api = MockUserApi::new();
    user_api.expect_get_user_addresses().once().returning({
        let addresses = addresses.clone();
        move || Box::pin(ready(Ok(addresses.clone())))
    });

    let mut user_repository = MockUserRepository::new();
    user_repository
        .expect_get_user()
        .with(eq(TEST_USER_ID))
        .once()
        .returning({
            let user = user.clone();
            move |_| Box::pin(ready(Ok(Some(user.clone()))))
        });
    user_repository
        .expect_get_user_keys()
        .with(eq(TEST_USER_ID))
        .once()
        .returning({
            let keys = keys.clone();
            move |_| Box::pin(ready(Ok(keys.clone())))
        });

    let app =
        build_app_with_service(default_app_state(), auth_service(user_api, user_repository)).await;

    let fetched = app
        .fetch_user_state(TEST_USER_ID.to_string(), false)
        .await
        .unwrap();
    assert_eq!(fetched.user_data.id, TEST_USER_ID);
    assert_eq!(fetched.user_keys.len(), 1);

    let cached = app.get_user_state().await.unwrap();
    assert_eq!(cached.user_data.id, TEST_USER_ID);
}

#[tokio::test]
async fn fetch_user_state_force_remote_refreshes_from_api() {
    let user = test_proton_user_with_keys(TEST_USER_ID);
    let addresses = vec![test_address("addr-1", "test@example.com")];

    let mut user_api = MockUserApi::new();
    user_api.expect_get_user_info().times(2).returning({
        let user = user.clone();
        move || Box::pin(ready(Ok(user.clone())))
    });
    user_api.expect_get_user_addresses().once().returning({
        let addresses = addresses.clone();
        move || Box::pin(ready(Ok(addresses.clone())))
    });

    let mut user_repository = MockUserRepository::new();
    user_repository
        .expect_save_user()
        .times(2)
        .returning(|_| Box::pin(ready(Ok(()))));
    user_repository
        .expect_save_user_keys()
        .times(2)
        .returning(|_, _| Box::pin(ready(Ok(()))));
    user_repository
        .expect_get_user_keys()
        .with(eq(TEST_USER_ID))
        .once()
        .returning(|_| Box::pin(ready(Ok(vec![]))));

    let app =
        build_app_with_service(default_app_state(), auth_service(user_api, user_repository)).await;

    let fetched = app
        .fetch_user_state(TEST_USER_ID.to_string(), true)
        .await
        .unwrap();
    assert_eq!(fetched.user_data.id, TEST_USER_ID);
    assert_eq!(fetched.user_keys.len(), 1);
}

#[tokio::test]
async fn refresh_user_state_from_api_clears_cache_then_reloads() {
    let user = test_proton_user_with_keys(TEST_USER_ID);
    let addresses = vec![test_address("addr-1", "test@example.com")];

    let mut user_api = MockUserApi::new();
    user_api.expect_get_user_info().times(2).returning({
        let user = user.clone();
        move || Box::pin(ready(Ok(user.clone())))
    });
    user_api.expect_get_user_addresses().once().returning({
        let addresses = addresses.clone();
        move || Box::pin(ready(Ok(addresses.clone())))
    });

    let mut user_repository = MockUserRepository::new();
    user_repository
        .expect_delete_user_keys()
        .with(eq(TEST_USER_ID))
        .once()
        .returning(|_| Box::pin(ready(Ok(()))));
    user_repository
        .expect_delete_user()
        .with(eq(TEST_USER_ID))
        .once()
        .returning(|_| Box::pin(ready(Ok(1))));
    user_repository
        .expect_save_user()
        .times(2)
        .returning(|_| Box::pin(ready(Ok(()))));
    user_repository
        .expect_save_user_keys()
        .times(2)
        .returning(|_, _| Box::pin(ready(Ok(()))));
    user_repository
        .expect_get_user_keys()
        .with(eq(TEST_USER_ID))
        .once()
        .returning(|_| Box::pin(ready(Ok(vec![]))));

    let app =
        build_app_with_service(default_app_state(), auth_service(user_api, user_repository)).await;

    let refreshed = app
        .refresh_user_state_from_api(TEST_USER_ID.to_string())
        .await
        .unwrap();
    assert_eq!(refreshed.user_data.id, TEST_USER_ID);
    assert_eq!(
        app.get_user_state().await.unwrap().user_data.id,
        TEST_USER_ID
    );
}

#[tokio::test]
async fn login_with_two_factor_stores_active_user() {
    let mut user_api = MockUserApi::new();
    user_api
        .expect_login_with_two_factor()
        .with(eq(TEST_2FA_CODE))
        .once()
        .returning(|_| Box::pin(ready(Ok(login_user_data()))));
    user_api
        .expect_get_user_addresses()
        .once()
        .returning(|| Box::pin(ready(Ok(vec![test_address("addr-1", "test@example.com")]))));

    let mut user_repository = MockUserRepository::new();
    user_repository
        .expect_init_tables()
        .with(eq(TEST_USER_ID))
        .once()
        .returning(|_| Box::pin(ready(Ok(()))));
    user_repository
        .expect_save_user()
        .once()
        .returning(|_| Box::pin(ready(Ok(()))));

    let app =
        build_app_with_service(default_app_state(), auth_service(user_api, user_repository)).await;

    let response = app
        .login_with_two_factor(TEST_2FA_CODE.to_string())
        .await
        .unwrap();
    assert_eq!(response.user.id, TEST_USER_ID);

    let active = app.get_user_state().await.unwrap();
    assert_eq!(active.user_data.id, TEST_USER_ID);
}

#[tokio::test]
async fn get_user_returns_cached_profile() {
    let user = test_proton_user(TEST_USER_ID);

    let mut user_repository = MockUserRepository::new();
    user_repository
        .expect_get_user()
        .with(eq(TEST_USER_ID))
        .once()
        .returning({
            let user = user.clone();
            move |_| Box::pin(ready(Ok(Some(user.clone()))))
        });

    let app = build_app_with_service(
        default_app_state(),
        auth_service(MockUserApi::new(), user_repository),
    )
    .await;

    let fetched = app.get_user(TEST_USER_ID.to_string()).await.unwrap();
    assert_eq!(fetched.id, TEST_USER_ID);
}

#[tokio::test]
async fn logout_clears_active_user_on_success() {
    let mut state = default_app_state();
    state.active_user = Some(test_user_state("user-1", true, true));
    state.meeting_display_name_session_key = Some("session-key".to_string().into());

    let mut user_api = MockUserApi::new();
    user_api
        .expect_logout()
        .once()
        .returning(|| Box::pin(async {}));

    let mut user_repository = MockUserRepository::new();
    user_repository
        .expect_delete_user()
        .withf(|id| id == "user-1")
        .once()
        .returning(|_| Box::pin(ready(Ok(1))));

    let app = build_app_with_service(state, auth_service(user_api, user_repository)).await;

    assert!(app.get_user_state().await.is_ok());
    app.logout("user-1".to_string()).await.unwrap();
    assert!(matches!(
        app.get_user_state().await,
        Err(MeetCoreError::NoActiveUser)
    ));
}

#[tokio::test]
async fn logout_keeps_active_user_when_service_fails() {
    let mut state = default_app_state();
    state.active_user = Some(test_user_state("user-1", true, true));

    let mut user_api = MockUserApi::new();
    user_api
        .expect_logout()
        .once()
        .returning(|| Box::pin(async {}));

    let mut user_repository = MockUserRepository::new();
    user_repository.expect_delete_user().once().returning(|_| {
        Box::pin(ready(Err(
            crate::infra::storage::error::StorageError::DbNotFound {
                name: "user-1".to_string(),
            },
        )))
    });

    let app = build_app_with_service(state, auth_service(user_api, user_repository)).await;

    assert!(app.logout("user-1".to_string()).await.is_err());
    assert!(app.get_user_state().await.is_ok());
}

#[tokio::test]
async fn fork_selector_returns_error_without_authenticated_session() {
    let app = build_app(default_app_state()).await;
    let result = app.fork_selector("child-client").await;
    assert!(matches!(result, Err(MeetCoreError::HttpClientError { .. })));
}

// --- Manual integration (real backend). Run: cargo test -p proton-meet-core login_and_logout -- --ignored ---

#[cfg(all(test, not(target_family = "wasm")))]
mod manual {
    use crate::app::test_support::manual;
    use crate::domain::user::ports::user_service::UserService;
    use tempfile::tempdir;

    #[tokio::test]
    #[ignore = "requires proton.black credentials (bart/bart)"]
    async fn login_and_logout() -> Result<(), anyhow::Error> {
        let temp_dir = tempdir()?;
        let db_path = temp_dir
            .path()
            .to_str()
            .ok_or_else(|| anyhow::anyhow!("temp path"))?
            .to_string();

        let app = manual::app_for_custom_api(
            "https://proton.black/api",
            "proton.black/api",
            db_path,
            "",
            "macos-meet@0.1.1",
        )
        .await?;

        let login_result = app.user_service.read().await.login("bart", "bart").await;
        let user_id = match &login_result {
            Ok((_, user_data, _, _)) => {
                assert!(!user_data.id.to_string().is_empty());
                assert!(!user_data.email.is_empty());
                user_data.id.to_string()
            }
            Err(e) => panic!("login failed: {e:?}"),
        };

        assert!(login_result.is_ok());
        assert!(app.logout(user_id).await.is_ok());

        Ok(())
    }
}
