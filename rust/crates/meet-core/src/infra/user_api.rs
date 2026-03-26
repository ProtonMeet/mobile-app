use std::time::Duration;

use anyhow::Context;
use muon::client::flow::{LoginExtraInfo, LoginFlow};
use muon::Client;
use proton_meet_common::models::ProtonUser;
use proton_meet_macro::async_trait;

use crate::domain::user::models::Address;
use crate::domain::user::ports::user_api::UserApi;
use crate::errors::http_client::HttpClientError;
use crate::errors::login::LoginError;
use crate::infra::dto::proton_user::{ApiProtonUserResponse, UserData};
use crate::infra::http_client::ProtonHttpClient;
use crate::infra::http_client_util::HttpClientUtil;
use crate::infra::proton_response_ext::ProtonResponseExt;
use muon::rest::core as CoreAPI;

#[async_trait]
impl UserApi for ProtonHttpClient {
    async fn login(&self, username: &str, password: &str) -> Result<UserData, LoginError> {
        let extra_info = LoginExtraInfo::builder().build();
        let client = match self
            .get_session()
            .auth()
            .login_with_extra(username, password, extra_info)
            .await
        {
            LoginFlow::Ok(c, ..) => Ok(c),
            LoginFlow::TwoFactor(..) => Err(LoginError::MissingTwoFactor),
            LoginFlow::Failed {
                client: _,
                reason: e,
            } => Err(LoginError::LoginFailed(e.to_string())),
        }?;
        self.get_user_data(&client).await
    }

    async fn login_with_two_factor(&self, two_factor_code: &str) -> Result<UserData, LoginError> {
        let client = self.get_session().auth().from_totp(two_factor_code).await?;
        self.get_user_data(&client).await
    }

    async fn logout(&self) {
        self.get_session().logout().await
    }

    async fn get_user_info(&self) -> Result<ProtonUser, LoginError> {
        let client = self.get_session();
        let req = self
            .get("/core/v4/users")
            .allowed_time(Duration::from_secs(15));
        let res = client.send(req).await?;
        let user_res = res.parse_response::<ApiProtonUserResponse>()?;
        Ok(user_res.user)
    }

    async fn get_user_addresses(&self) -> Result<Vec<Address>, HttpClientError> {
        let req = self
            .get("/core/v4/addresses")
            .allowed_time(Duration::from_secs(15));
        let res = self.get_session().send(req).await?;
        let addresses_res: CoreAPI::v4::addresses::GetRes = res.into_body_json()?;
        Ok(addresses_res
            .addresses
            .iter()
            .map(|address| address.into())
            .collect())
    }
}

impl ProtonHttpClient {
    pub(crate) async fn get_user_data(&self, client: &Client) -> Result<UserData, LoginError> {
        let req = self
            .get("/core/v4/users")
            .allowed_time(Duration::from_secs(15));
        let res = client
            .send(req)
            .await
            .context("failed to send user request")?;
        let user_res = res.parse_response::<ApiProtonUserResponse>()?;

        let keysalt_req = self
            .get("/core/v4/keys/salts")
            .allowed_time(Duration::from_secs(15));
        let keysalt_res: CoreAPI::v4::keys::salts::GetRes = client
            .send(keysalt_req)
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
