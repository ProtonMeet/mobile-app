use std::sync::Arc;

use flutter_rust_bridge::frb;
use proton_meet_core::infra::desktop_web_login_manager::DesktopWebLoginManager;

use crate::errors::BridgeError;
use crate::proton_meet::core::AppCore;
use crate::proton_meet::meet_auth_store::ProtonMeetAuthStore;
use crate::proton_meet::models::{
    desktop_web_login::DesktopWebLoginStart, proton_user_session::ProtonUserSession,
};

/// Ephemeral desktop web login flow. Create when opening the login UI; drop after success or cancel.
#[cfg(not(target_arch = "wasm32"))]
#[frb(opaque)]
pub struct DesktopWebLogin {
    inner: DesktopWebLoginManager,
    auth_store: Arc<ProtonMeetAuthStore>,
}

#[cfg(not(target_arch = "wasm32"))]
#[frb]
impl DesktopWebLogin {
    pub async fn new(
        env: String,
        app_version: String,
        user_agent: String,
        http_host: String,
        app: &AppCore,
    ) -> Result<Self, BridgeError> {
        let inner = DesktopWebLoginManager::new(
            env,
            app_version,
            user_agent,
            http_host,
            app.inner.http_client(),
            app.auth_store.inner.auth.clone(),
        )
        .await
        .map_err(|e| BridgeError::Login(e.to_string()))?;
        Ok(Self {
            inner,
            auth_store: app.auth_store.clone(),
        })
    }

    pub async fn start(
        &mut self,
        child_client_id: String,
    ) -> Result<DesktopWebLoginStart, BridgeError> {
        let start = self
            .inner
            .start(child_client_id)
            .await
            .map_err(|e| BridgeError::Login(e.to_string()))?;
        Ok(DesktopWebLoginStart {
            login_url: start.login_url,
            browser_redirect_state: start.browser_redirect_state,
        })
    }

    /// Returns `None` while waiting; `Some(session)` when the user has signed in.
    pub async fn poll(&mut self) -> Result<Option<ProtonUserSession>, BridgeError> {
        use proton_meet_core::infra::desktop_web_login::DesktopWebLoginPoll as CorePoll;

        let poll = self
            .inner
            .poll()
            .await
            .map_err(|e| BridgeError::Login(e.to_string()))?;

        match poll {
            CorePoll::Pending => Ok(None),
            CorePoll::Complete {
                user_data,
                mailbox_password,
                auth: _,
            } => {
                let auth = self.auth_store.get_auth().await;
                let session =
                    ProtonUserSession::from_user_data_and_auth(user_data, auth, mailbox_password)?;
                Ok(Some(session))
            }
        }
    }

    pub async fn cancel(&mut self) {
        self.inner.cancel();
    }
}
