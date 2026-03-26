use proton_meet_macro::async_trait_with_mock;

use crate::{
    domain::user::models::Address,
    errors::{http_client::HttpClientError, login::LoginError},
    infra::dto::proton_user::UserData,
};
use proton_meet_common::models::ProtonUser;

#[async_trait_with_mock]
pub trait UserApi: Send + Sync {
    async fn login(&self, username: &str, password: &str) -> Result<UserData, LoginError>;
    async fn login_with_two_factor(&self, two_factor_code: &str) -> Result<UserData, LoginError>;
    async fn logout(&self);
    async fn get_user_info(&self) -> Result<ProtonUser, LoginError>;
    async fn get_user_addresses(&self) -> Result<Vec<Address>, HttpClientError>;
}

#[cfg(test)]
mod tests {
    use super::*;
    use proton_meet_macro::unified_test;
    use serde_json::json;

    fn dummy_user() -> ProtonUser {
        ProtonUser {
            id: "u1".to_string(),
            name: "Alice".to_string(),
            email: "alice@example.com".to_string(),
            ..Default::default()
        }
    }
    // ---- login: success ----------------------------------------------------
    #[unified_test]
    async fn login_succeeds_with_correct_credentials() {
        let mut mock = MockUserApi::new();

        mock.expect_login()
            .times(1)
            .withf(|u, p| u == "alice" && p == "secret")
            .returning(|_, _| Box::pin(async { Ok(UserData::default()) }));

        let result = mock.login("alice", "secret").await;
        assert!(
            result.is_ok(),
            "expected Ok(Login), got: {:?}",
            result.err()
        );
    }

    // ---- login: failure ----------------------------------------------------
    #[unified_test]
    async fn login_fails_with_wrong_credentials() {
        let mut mock = MockUserApi::new();

        mock.expect_login()
            .times(1)
            .withf(|u, p| u == "alice" && p == "wrong")
            .returning(|_, _| {
                Box::pin(async { Err(LoginError::LoginFailed("Invalid credentials".to_string())) })
            });

        let result = mock.login("alice", "wrong").await;
        assert!(result.is_err(), "expected Err(LoginError), got Ok(..)");
    }

    // ---- get_user_info: success -------------------------------------------
    #[unified_test]
    async fn get_user_info_returns_user() {
        let mut mock = MockUserApi::new();

        mock.expect_get_user_info()
            .times(1)
            .returning(|| Box::pin(async { Ok(dummy_user()) }));

        let user = mock.get_user_info().await.expect("should return User");
        // Optionally assert on fields if your dummy_user() is concrete
        // assert_eq!(user.name, "Alice");
        let _ = user;
    }

    // ---- logout: called exactly once --------------------------------------
    #[unified_test]
    async fn logout_is_called_once() {
        let mut mock = MockUserApi::new();

        // async fn -> () ; return a completed future
        mock.expect_logout()
            .times(1)
            .returning(|| Box::pin(async {}));

        mock.logout().await;
    }

    fn base_user_json() -> serde_json::Value {
        json!({
            "ID": "u1",
            "UsedSpace": 0,
            "Currency": "USD",
            "Credit": 0,
            "CreateTime": 0,
            "MaxSpace": 0,
            "MaxUpload": 0,
            "Role": 0,
            "Private": 0,
            "Subscribed": 0,
            "Services": 0,
            "Delinquent": 0,
            "OrganizationPrivateKey": null,
            "Email": "alice@example.com",
            "DisplayName": null,
            "Keys": null,
            "MnemonicStatus": 0
        })
    }

    #[test]
    fn proton_user_name_null_deserializes_to_empty() {
        let mut payload = base_user_json();
        payload["Name"] = serde_json::Value::Null;
        let user: ProtonUser =
            serde_json::from_str(&payload.to_string()).expect("parse proton user");
        assert_eq!(user.name, "");
    }

    #[test]
    fn proton_user_name_missing_deserializes_to_empty() {
        let payload = base_user_json();
        let user: ProtonUser =
            serde_json::from_str(&payload.to_string()).expect("parse proton user");
        assert_eq!(user.name, "");
    }

    #[test]
    fn proton_user_name_null_string_deserializes_to_empty() {
        let mut payload = base_user_json();
        payload["Name"] = serde_json::Value::String("NULL".to_string());
        let user: ProtonUser =
            serde_json::from_str(&payload.to_string()).expect("parse proton user");
        assert_eq!(user.name, "");
    }
}
