use super::App;
use crate::app_state::UserState;
use crate::domain::user::models::UserId;
use crate::domain::user::ports::user_api::UserApi;
use crate::domain::user::ports::UserService;
use crate::errors::core::MeetCoreError;
#[cfg(not(target_arch = "wasm32"))]
use crate::infra::dto::proton_user::UserData;
use muon::auth::ForkFlowResult;
use proton_meet_common::models::ProtonUser;
use tracing::error;

impl App {
    pub async fn fork_selector(&self, client_child: &str) -> Result<String, MeetCoreError> {
        let session = self.http_api.get_session();
        match session
            .fork(client_child)
            .payload(b"proton meet fork")
            .send()
            .await
        {
            ForkFlowResult::Success(_session, selector) => Ok(selector),
            other => {
                error!("Fork session failed: {:?}", other);
                Err(MeetCoreError::HttpClientError {
                    status: 0,
                    message: format!("Fork session failed: {other:?}"),
                    details: Some(format!("{other:?}")),
                })
            }
        }
    }

    pub async fn fetch_user_state(
        &self,
        user_id: String,
        force_remote: bool,
    ) -> Result<UserState, MeetCoreError> {
        let user = self
            .services
            .auth_service
            .get_user_with_policy(&UserId::new(user_id.clone()), force_remote)
            .await?;

        let user_keys = self
            .services
            .auth_service
            .get_user_keys(&UserId::new(user_id.clone()))
            .await?;

        let user_addresses = self.services.auth_service.get_user_addresses().await?;
        let user_state = UserState {
            user_data: user.clone(),
            user_keys,
            user_addresses,
        };

        let mut state = self.state.write().await;
        state.active_user = Some(user_state.clone());
        Ok(user_state)
    }

    /// Clears the Rust-side local user/keys cache, then reloads [`UserState`] from the API
    /// and updates in-memory [`AppState::active_user`][super::AppState::active_user]. Use when the event API reports
    /// `refresh` or other signals that server-side user data may have changed.
    pub async fn refresh_user_state_from_api(
        &self,
        user_id: String,
    ) -> Result<UserState, MeetCoreError> {
        let id = UserId::new(user_id.clone());
        self.services
            .auth_service
            .clear_local_user_profile_cache(&id)
            .await?;
        self.fetch_user_state(user_id, true).await
    }

    /// Username/password login (native mobile/desktop only; not used on WASM).
    #[cfg(not(target_arch = "wasm32"))]
    pub async fn login(
        &self,
        username: String,
        password: String,
    ) -> Result<UserData, MeetCoreError> {
        use zeroize::Zeroizing;
        let password = Zeroizing::new(password);
        let (login_response, user, user_keys, user_addresses) = self
            .services
            .auth_service
            .login(&username, password.as_str())
            .await?;
        let mut state = self.state.write().await;
        state.active_user = Some(UserState {
            user_data: user.clone(),
            user_keys,
            user_addresses,
        });
        Ok(login_response)
    }

    pub async fn get_user_state(&self) -> Result<UserState, MeetCoreError> {
        self.state
            .read()
            .await
            .active_user
            .clone()
            .ok_or(MeetCoreError::NoActiveUser)
    }

    pub async fn logout(&self, user_id: String) -> Result<(), MeetCoreError> {
        self.services
            .auth_service
            .logout(&UserId::new(user_id))
            .await?;
        let mut state = self.state.write().await;
        state.active_user = None;
        state.meeting_display_name_session_key = None;
        Ok(())
    }

    #[tracing::instrument(err, skip_all)]
    #[cfg(not(target_arch = "wasm32"))]
    pub async fn login_with_two_factor(
        &self,
        two_factor_code: String,
    ) -> Result<UserData, MeetCoreError> {
        let user_data = self
            .services
            .auth_service
            .login_with_two_factor(&two_factor_code)
            .await?;
        let user = user_data.user.clone();
        let user_keys = user.keys.clone().unwrap_or_default();
        let user_addresses = self.services.auth_service.get_user_addresses().await?;
        let mut state = self.state.write().await;
        state.active_user = Some(UserState {
            user_data: user,
            user_keys,
            user_addresses,
        });
        Ok(user_data)
    }

    #[tracing::instrument(err, skip_all)]
    pub async fn get_user(&self, user_id: String) -> Result<ProtonUser, anyhow::Error> {
        let user_data = self
            .services
            .auth_service
            .get_user(&UserId::new(user_id))
            .await?;
        Ok(user_data)
    }

    /// Reads `UserSettings.Telemetry` from `GET /core/v4/settings`.
    ///
    /// The settings payload includes many account fields; Meet only parses Telemetry
    /// for Sentry gating. See `ProtonSettingsUserSettingsDto`.
    #[tracing::instrument(err, skip_all)]
    pub async fn get_proton_telemetry_enabled(&self) -> Result<bool, MeetCoreError> {
        let proton_http = self
            .proton_http
            .as_ref()
            .ok_or(MeetCoreError::InternalError {
                message: "Proton HTTP client unavailable".to_string(),
                details: None,
            })?;
        proton_http
            .get_proton_telemetry_enabled()
            .await
            .map_err(MeetCoreError::from)
    }
}
