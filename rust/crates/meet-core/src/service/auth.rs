use std::sync::Arc;

#[cfg(not(target_arch = "wasm32"))]
use proton_meet_common::models::{ProtonUser, ProtonUserKey};
use proton_meet_macro::{async_trait, async_trait_with_mock};

#[cfg(not(target_arch = "wasm32"))]
use crate::{
    domain::user::models::Address, errors::login::LoginError, infra::dto::proton_user::UserData,
};
use crate::{
    domain::user::{
        models::{UserId, UserSettings},
        ports::{user_api::UserApi, ArcUserRepository, HttpClient},
    },
    errors::service::ServiceError,
    infra::storage::error::StorageError,
};

pub(crate) struct AuthServiceImpl {
    http_client: Arc<dyn HttpClient>,
    user_api: Arc<dyn UserApi>,
    user_repository: ArcUserRepository,
}

impl AuthServiceImpl {
    pub fn new(
        http_client: Arc<dyn HttpClient>,
        user_api: Arc<dyn UserApi>,
        user_repository: ArcUserRepository,
    ) -> Self {
        Self {
            http_client,
            user_api,
            user_repository,
        }
    }
}

#[async_trait_with_mock]
pub(crate) trait AuthService: Send + Sync {
    async fn login(
        &self,
        username: &str,
        password: &str,
    ) -> Result<(UserData, ProtonUser, Vec<ProtonUserKey>, Vec<Address>), LoginError>;
    async fn login_with_two_factor(&self, two_factor_code: &str) -> Result<UserData, LoginError>;
    async fn logout(&self, user_id: &UserId) -> Result<(), anyhow::Error>;

    async fn get_user_with_policy(
        &self,
        user_id: &UserId,
        force_remote: bool,
    ) -> Result<ProtonUser, ServiceError>;
    async fn get_user(&self, user_id: &UserId) -> Result<ProtonUser, ServiceError> {
        self.get_user_with_policy(user_id, false).await
    }

    async fn get_user_keys_with_policy(
        &self,
        user_id: &UserId,
        force_remote: bool,
    ) -> Result<Vec<ProtonUserKey>, anyhow::Error>;
    async fn get_user_keys(&self, user_id: &UserId) -> Result<Vec<ProtonUserKey>, anyhow::Error> {
        self.get_user_keys_with_policy(user_id, false).await
    }

    async fn get_user_addresses(&self) -> Result<Vec<Address>, anyhow::Error>;

    /// Clears the persisted Proton user row and keys so [`get_user`][Self::get_user] /
    /// [`get_user_keys``][Self::get_user_keys] load from the API again (meet-server may have
    /// changed user data when the event stream sets `refresh`).
    async fn clear_local_user_profile_cache(&self, user_id: &UserId) -> Result<(), StorageError>;

    async fn get_user_settings(&self) -> Result<UserSettings, anyhow::Error>;

    async fn update_user_settings_waiting_room(
        &self,
        enable: bool,
    ) -> Result<UserSettings, anyhow::Error>;
}

#[async_trait]
impl AuthService for AuthServiceImpl {
    #[cfg(not(target_arch = "wasm32"))]
    async fn login(
        &self,
        username: &str,
        password: &str,
    ) -> Result<(UserData, ProtonUser, Vec<ProtonUserKey>, Vec<Address>), LoginError> {
        let login_response = self.user_api.login(username, password).await?;

        self.user_repository
            .init_tables(&login_response.user.id)
            .await?;

        let user = login_response.user.clone();
        self.user_repository.save_user(&user).await?;

        let user_keys: Vec<ProtonUserKey> = login_response.user.keys.clone().unwrap_or_default();

        self.user_repository
            .save_user_keys(&user.id, &user_keys)
            .await?;

        let user_addresses = self.user_api.get_user_addresses().await?;

        Ok((login_response, user, user_keys, user_addresses))
    }

    #[cfg(target_arch = "wasm32")]
    async fn login(
        &self,
        _username: &str,
        _password: &str,
    ) -> Result<(UserData, ProtonUser, Vec<ProtonUserKey>, Vec<Address>), LoginError> {
        Err(LoginError::LoginFailed(
            "password login is not available on web".into(),
        ))
    }

    #[cfg(not(target_arch = "wasm32"))]
    async fn login_with_two_factor(&self, two_factor_code: &str) -> Result<UserData, LoginError> {
        let user_data = self.user_api.login_with_two_factor(two_factor_code).await?;
        self.user_repository.init_tables(&user_data.user.id).await?;
        let user = user_data.user.clone();
        self.user_repository.save_user(&user).await?;
        Ok(user_data)
    }

    #[cfg(target_arch = "wasm32")]
    async fn login_with_two_factor(&self, _two_factor_code: &str) -> Result<UserData, LoginError> {
        Err(LoginError::LoginFailed(
            "password login is not available on web".into(),
        ))
    }

    async fn get_user_with_policy(
        &self,
        user_id: &UserId,
        force_remote: bool,
    ) -> Result<ProtonUser, ServiceError> {
        if !force_remote {
            let user = self.user_repository.get_user(user_id.as_str()).await?;
            if let Some(local_user) = user {
                return Ok(local_user);
            }
        }

        // Force remote (or local miss): fetch fresh profile, then persist.
        let proton_user = self.user_api.get_user_info().await?;
        self.user_repository.save_user(&proton_user).await?;

        // Keep key cache in sync with the latest user profile payload.
        let user_keys = proton_user.keys.clone().unwrap_or_default();
        self.user_repository
            .save_user_keys(&proton_user.id, &user_keys)
            .await?;

        Ok(proton_user)
    }

    async fn get_user_keys_with_policy(
        &self,
        user_id: &UserId,
        force_remote: bool,
    ) -> Result<Vec<ProtonUserKey>, anyhow::Error> {
        if !force_remote {
            let user_keys = self.user_repository.get_user_keys(user_id.as_str()).await?;
            if !user_keys.is_empty() {
                return Ok(user_keys);
            }
        }

        // Force remote (or local miss): fetch user profile, then persist user + keys.
        let proton_user = self.user_api.get_user_info().await?;
        self.user_repository.save_user(&proton_user).await?;

        let proton_keys: Vec<ProtonUserKey> = proton_user.keys.unwrap_or_default();
        self.user_repository
            .save_user_keys(user_id.as_str(), &proton_keys)
            .await?;
        Ok(proton_keys)
    }

    async fn get_user_addresses(&self) -> Result<Vec<Address>, anyhow::Error> {
        let user_addresses = self.user_api.get_user_addresses().await?;
        Ok(user_addresses)
    }

    async fn logout(&self, user_id: &UserId) -> Result<(), anyhow::Error> {
        self.user_api.logout().await;
        self.user_repository.delete_user(user_id.as_str()).await?;
        Ok(())
    }

    async fn clear_local_user_profile_cache(&self, user_id: &UserId) -> Result<(), StorageError> {
        // On native, `delete_user` removes the whole per-user DB bundle; clear keys first
        // so `delete_user_keys` can still open the DB. On WASM, order is harmless.
        self.user_repository
            .delete_user_keys(user_id.as_str())
            .await?;
        self.user_repository.delete_user(user_id.as_str()).await?;
        Ok(())
    }

    async fn get_user_settings(&self) -> Result<UserSettings, anyhow::Error> {
        let user_settings = self.http_client.get_user_settings().await?;
        Ok(user_settings)
    }

    async fn update_user_settings_waiting_room(
        &self,
        enable: bool,
    ) -> Result<UserSettings, anyhow::Error> {
        let user_settings = self
            .http_client
            .update_user_settings_waiting_room(enable)
            .await?;
        Ok(user_settings)
    }
}

#[cfg(test)]
pub mod tests {
    use std::{future::ready, sync::Arc};

    use mockall::predicate::eq;

    use crate::{
        domain::user::{
            models::UserId,
            ports::{user_api::MockUserApi, MockHttpClient, MockUserRepository},
        },
        errors::login::LoginError,
        infra::dto::proton_user::UserData,
        service::auth::{AuthService, AuthServiceImpl},
    };

    // Test data constants for better maintainability
    const TEST_USERNAME: &str = "test_user";
    const TEST_PASSWORD: &str = "test_password";
    const TEST_USER_ID: &str = "test_user_id";
    const TEST_USER_EMAIL: &str = "test@example.com";
    const TEST_USER_NAME: &str = "Test User";

    #[tokio::test]
    async fn test_login_success() {
        let http_client = MockHttpClient::new();
        let mut mock_user_api = MockUserApi::new();
        mock_user_api
            .expect_login()
            .with(eq(TEST_USERNAME), eq(TEST_PASSWORD))
            .once()
            .returning(move |_, _| {
                let user_data = UserData {
                    user: proton_meet_common::models::ProtonUser {
                        id: TEST_USER_ID.to_string(),
                        name: TEST_USER_NAME.to_string(),
                        email: TEST_USER_EMAIL.to_string(),
                        ..Default::default()
                    },
                    key_salts: vec![],
                };
                Box::pin(ready(Ok(user_data)))
            });
        mock_user_api
            .expect_get_user_addresses()
            .once()
            .returning(|| Box::pin(ready(Ok(vec![]))));

        let mut user_repository = MockUserRepository::new();
        user_repository
            .expect_init_tables()
            .with(eq(TEST_USER_ID))
            .once()
            .returning(|_| Box::pin(ready(Ok(()))));

        user_repository
            .expect_save_user()
            .withf(move |user| {
                user.id == TEST_USER_ID
                    && user.name == TEST_USER_NAME
                    && user.email == TEST_USER_EMAIL
            })
            .once()
            .returning(|_| Box::pin(ready(Ok(()))));
        user_repository
            .expect_save_user_keys()
            .withf(|user_id, keys| user_id == TEST_USER_ID && keys.is_empty())
            .once()
            .returning(|_, _| Box::pin(ready(Ok(()))));

        let auth_service = AuthServiceImpl::new(
            Arc::new(http_client),
            Arc::new(mock_user_api),
            Arc::new(user_repository),
        );

        let result = auth_service.login(TEST_USERNAME, TEST_PASSWORD).await;

        assert!(result.is_ok());
        let (_, user, user_keys, user_addresses) = result.unwrap();
        assert_eq!(user.id, TEST_USER_ID.to_string());
        assert_eq!(user.name, TEST_USER_NAME);
        assert_eq!(user.email, TEST_USER_EMAIL);
        assert_eq!(user_keys, vec![]);
        assert_eq!(user_addresses, vec![]);
    }

    #[tokio::test]
    async fn test_login_http_client_error() {
        let http_client = MockHttpClient::new();
        let mut mock_user_api = MockUserApi::new();
        mock_user_api
            .expect_login()
            .with(eq(TEST_USERNAME), eq(TEST_PASSWORD))
            .once()
            .returning(|_, _| {
                Box::pin(ready(Err(LoginError::LoginFailed(
                    "Invalid credentials".to_string(),
                ))))
            });
        let user_repository = MockUserRepository::new();

        let auth_service = AuthServiceImpl::new(
            Arc::new(http_client),
            Arc::new(mock_user_api),
            Arc::new(user_repository),
        );

        let result = auth_service.login(TEST_USERNAME, TEST_PASSWORD).await;

        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), LoginError::LoginFailed(_)));
    }

    #[tokio::test]
    async fn test_logout_success() {
        let user_id = TEST_USER_ID.to_string();

        let http_client = MockHttpClient::new();
        let mut mock_user_api = MockUserApi::new();
        mock_user_api
            .expect_logout()
            .once()
            .returning(|| Box::pin(ready(())));

        let mut user_repository = MockUserRepository::new();
        user_repository
            .expect_delete_user()
            .with(eq(user_id.clone()))
            .once()
            .returning(|_| Box::pin(ready(Ok(1))));

        let auth_service = AuthServiceImpl::new(
            Arc::new(http_client),
            Arc::new(mock_user_api),
            Arc::new(user_repository),
        );

        let result = auth_service.logout(&UserId::new(user_id)).await;

        assert!(result.is_ok());
    }
}
