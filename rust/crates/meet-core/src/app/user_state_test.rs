use crate::app::test_support::{build_app, default_app_state, test_user_key, test_user_state};
use crate::errors::core::MeetCoreError;

#[tokio::test]
async fn get_user_state_info_succeeds_with_valid_state() {
    let mut state = default_app_state();
    state.active_user = Some(test_user_state("user-1", true, true));

    let app = build_app(state).await;
    let info = app.get_user_state_info().await.unwrap();

    assert_eq!(info.user_id, "user-1");
    assert_eq!(info.active_user_key.id, "key-1");
    assert_eq!(info.primary_address.id, "addr-1");
}

#[tokio::test]
async fn get_user_state_info_errors_without_active_user() {
    let app = build_app(default_app_state()).await;
    let result = app.get_user_state_info().await;
    assert!(matches!(result, Err(MeetCoreError::NoActiveUser)));
}

#[tokio::test]
async fn get_user_state_info_errors_without_user_keys() {
    let mut state = default_app_state();
    state.active_user = Some(test_user_state("user-1", false, true));

    let app = build_app(state).await;
    let result = app.get_user_state_info().await;
    assert!(matches!(result, Err(MeetCoreError::NoUserKeys)));
}

#[tokio::test]
async fn get_user_state_info_errors_without_primary_address() {
    let mut state = default_app_state();
    state.active_user = Some(test_user_state("user-1", true, false));

    let app = build_app(state).await;
    let result = app.get_user_state_info().await;
    assert!(matches!(result, Err(MeetCoreError::NoPrimaryAddress)));
}

#[tokio::test]
async fn get_user_state_info_prefers_primary_active_key() {
    let mut state = default_app_state();
    let mut user_state = test_user_state("user-1", false, true);
    user_state.user_keys = vec![
        test_user_key("inactive", 0, 0),
        test_user_key("active-only", 0, 1),
        test_user_key("primary-active", 1, 1),
    ];
    state.active_user = Some(user_state);

    let app = build_app(state).await;
    let info = app.get_user_state_info().await.unwrap();
    assert_eq!(info.active_user_key.id, "primary-active");
}
