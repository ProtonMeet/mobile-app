use flutter_rust_bridge::frb;
use proton_meet_core::{errors::login::LoginError, infra::dto::proton_user::UserData, muon::Auth};

use crate::errors::BridgeError;

pub struct ProtonUserSession {
    pub user_id: String,
    pub user_mail: String,
    pub user_name: String,
    pub user_display_name: Option<String>,
    pub session_id: String,
    pub access_token: String,
    pub refresh_token: String,
    pub scopes: Vec<String>,
    pub user_key_id: String,
    pub user_private_key: String,
    pub user_passphrase: String,
}

impl ProtonUserSession {
    /// Builds a ProtonUserSession from UserData, Auth, and mailbox password
    #[frb(ignore)]
    pub(crate) fn from_user_data_and_auth(
        user_data: UserData,
        auth: Auth,
        mailbox_password: String,
    ) -> Result<Self, BridgeError> {
        let session_id = auth
            .uid()
            .ok_or_else(|| BridgeError::from(LoginError::LoginFailed("No session ID".to_string())))?
            .to_string();
        let tokens = auth
            .tokens()
            .ok_or_else(|| BridgeError::from(LoginError::LoginFailed("No tokens".to_string())))?;
        let access_token = tokens
            .acc_tok()
            .ok_or_else(|| {
                BridgeError::from(LoginError::LoginFailed("No access token".to_string()))
            })?
            .to_string();
        let refresh_token = tokens.ref_tok().to_string();
        let scopes = tokens.scopes().unwrap_or_default().to_vec();

        // Extract user key information
        let user_key = user_data
            .user
            .keys
            .as_ref()
            .and_then(|keys| keys.first())
            .ok_or_else(|| BridgeError::from(LoginError::NoUserKeys))?;
        let user_key_id = user_key.id.clone();
        let user_private_key = user_key.private_key.clone();

        Ok(ProtonUserSession {
            user_id: user_data.user.id,
            user_mail: user_data.user.email,
            user_name: user_data.user.name,
            user_display_name: user_data.user.display_name.clone(),
            session_id,
            access_token,
            refresh_token,
            scopes,
            user_key_id,
            user_private_key,
            user_passphrase: mailbox_password,
        })
    }
}
