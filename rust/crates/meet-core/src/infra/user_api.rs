//! HTTP user API. Password/2FA login is native-only (mobile + desktop); WASM uses
//! pre-imported session auth instead.

use std::time::Duration;

#[cfg(not(target_arch = "wasm32"))]
use anyhow::Context;
use proton_meet_common::models::ProtonUser;
use proton_meet_macro::async_trait;

use crate::domain::user::models::Address;
use crate::domain::user::ports::user_api::UserApi;
use crate::errors::http_client::HttpClientError;
use crate::errors::login::LoginError;
use crate::infra::dto::addresses::ApiAddressesResponse;
use crate::infra::dto::proton_settings::ProtonSettingsResponse;
use crate::infra::dto::proton_user::{ApiProtonUserResponse, UserData};
use crate::infra::http_client::ProtonHttpClient;
use crate::infra::http_client_util::HttpClientUtil;
#[cfg(not(target_arch = "wasm32"))]
use crate::infra::muon::MeetSession;
use crate::infra::proton_response_ext::ProtonResponseExt;
#[cfg(not(target_arch = "wasm32"))]
use muon::rest::core as CoreAPI;

#[cfg(not(target_arch = "wasm32"))]
use muon::auth::LoginFlow;

#[async_trait]
impl UserApi for ProtonHttpClient {
    #[cfg(not(target_arch = "wasm32"))]
    async fn login(&self, username: &str, password: &str) -> Result<UserData, LoginError> {
        let session = match self.get_session().auth().login(username, password).await {
            LoginFlow::Ok(session, ..) => Ok(session),
            LoginFlow::TwoFactor(..) => Err(LoginError::MissingTwoFactor),
            LoginFlow::Failed {
                session: _,
                reason: e,
            } => Err(LoginError::LoginFailed(e.to_string())),
        }?;
        self.get_user_data(&session).await
    }

    #[cfg(target_arch = "wasm32")]
    async fn login(&self, _username: &str, _password: &str) -> Result<UserData, LoginError> {
        Err(LoginError::LoginFailed(
            "password login is not available on web".into(),
        ))
    }

    #[cfg(not(target_arch = "wasm32"))]
    async fn login_with_two_factor(&self, two_factor_code: &str) -> Result<UserData, LoginError> {
        let session = self.get_session().auth().from_totp(two_factor_code).await?;
        self.get_user_data(&session).await
    }

    #[cfg(target_arch = "wasm32")]
    async fn login_with_two_factor(&self, _two_factor_code: &str) -> Result<UserData, LoginError> {
        Err(LoginError::LoginFailed(
            "password login is not available on web".into(),
        ))
    }

    async fn logout(&self) {
        self.get_session().logout().await
    }

    async fn get_user_info(&self) -> Result<ProtonUser, LoginError> {
        let req = self
            .get("/core/v4/users")
            .allowed_time(Duration::from_secs(15));
        let res = self.send_session_request(req).await?;
        let user_res = res.parse_response::<ApiProtonUserResponse>()?;
        Ok(user_res.user)
    }

    async fn get_user_addresses(&self) -> Result<Vec<Address>, HttpClientError> {
        let req = self
            .get("/core/v4/addresses")
            .allowed_time(Duration::from_secs(15));
        let res = self.send_session_request(req).await?;
        let addresses_res = res.parse_response::<ApiAddressesResponse>()?;
        Ok(addresses_res
            .addresses()
            .iter()
            .map(|address| address.into())
            .collect())
    }

    async fn get_proton_telemetry_enabled(&self) -> Result<bool, HttpClientError> {
        // `/core/v4/settings` returns a large UserSettings object; DTO keeps Telemetry only.
        let req = self
            .get("/core/v4/settings")
            .allowed_time(Duration::from_secs(15));
        let res = self.send_session_request(req).await?;
        let settings = res.parse_response::<ProtonSettingsResponse>()?;
        Ok(settings.user_settings.telemetry != 0)
    }
}

#[cfg(not(target_arch = "wasm32"))]
impl ProtonHttpClient {
    pub(crate) async fn get_user_data(
        &self,
        session: &MeetSession,
    ) -> Result<UserData, LoginError> {
        let req = self
            .get("/core/v4/users")
            .allowed_time(Duration::from_secs(15));
        let res = self
            .send_on_session(session, req)
            .await
            .context("failed to send user request")?;
        let user_res = res.parse_response::<ApiProtonUserResponse>()?;

        let keysalt_req = self
            .get("/core/v4/keys/salts")
            .allowed_time(Duration::from_secs(15));
        let keysalt_res: CoreAPI::v4::keys::salts::GetRes = self
            .send_on_session(session, keysalt_req)
            .await
            .context("failed to send keysalts request")?
            .into_body_json()
            .context("failed to deserialize keysalts")?;

        Ok(UserData {
            user: user_res.user,
            key_salts: keysalt_res.key_salts,
        })
    }
}
