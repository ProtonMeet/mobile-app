//! Ephemeral desktop web login session — isolated from the main app muon client.
//! Drop or cancel when login finishes or is abandoned.

use std::sync::Arc;

use muon::client::Auth;
use muon::env::EnvId;
use tokio::sync::Mutex;

use crate::errors::core::MeetCoreError;
use crate::infra::auth_store::AuthStore;
use crate::infra::desktop_web_login::{self, DesktopWebLoginPoll, DesktopWebLoginStart, PendingState};
use crate::infra::http_client::{ApiConfig, ProtonHttpClient};

/// Standalone manager for one desktop web login attempt.
#[cfg(not(target_arch = "wasm32"))]
pub struct DesktopWebLoginManager {
    login_http: ProtonHttpClient,
    main_http: ProtonHttpClient,
    session_auth: Arc<Mutex<Auth>>,
    pending: Option<PendingState>,
}

#[cfg(not(target_arch = "wasm32"))]
impl DesktopWebLoginManager {
    pub fn new(
        env: String,
        app_version: String,
        user_agent: String,
        http_host: String,
        main_http: ProtonHttpClient,
        session_auth: Arc<Mutex<Auth>>,
    ) -> Result<Self, MeetCoreError> {
        let env_id: EnvId = env.parse().map_err(|_| MeetCoreError::AuthenticationFailed {
            message: format!("Invalid environment for desktop web login: {env}"),
        })?;
        let config = ApiConfig {
            spec: (app_version, user_agent),
            auth: None,
            url_prefix: None,
            env: Some(env),
            store: None,
            proxy: None,
        };
        let login_http = ProtonHttpClient::new(config, Box::new(AuthStore::new(env_id)), http_host)
            .map_err(|e| MeetCoreError::AuthenticationFailed {
                message: format!("Failed to create desktop login HTTP client: {e}"),
            })?;

        Ok(Self {
            login_http,
            main_http,
            session_auth,
            pending: None,
        })
    }

    pub async fn start(
        &mut self,
        child_client_id: String,
    ) -> Result<DesktopWebLoginStart, MeetCoreError> {
        let (start, pending) =
            desktop_web_login::start(&self.login_http, child_client_id).await?;
        self.pending = Some(pending);
        Ok(start)
    }

    pub async fn poll(&mut self) -> Result<DesktopWebLoginPoll, MeetCoreError> {
        let pending = self
            .pending
            .take()
            .ok_or_else(|| MeetCoreError::AuthenticationFailed {
                message: "Desktop web login was not started".to_string(),
            })?;

        let (result, next) = desktop_web_login::poll(&self.login_http, pending).await?;

        if let Some(state) = next {
            self.pending = Some(state);
        }

        if let DesktopWebLoginPoll::Complete { auth, .. } = &result {
            promote_auth_to_main_session(&self.main_http, &self.session_auth, auth.clone()).await?;
        }

        Ok(result)
    }

    pub fn cancel(&mut self) {
        self.pending = None;
    }
}

/// Apply forked auth to the main muon session (persistent store + in-memory client).
pub async fn promote_auth_to_main_session(
    main_http: &ProtonHttpClient,
    session_auth: &Arc<Mutex<Auth>>,
    auth: Auth,
) -> Result<(), MeetCoreError> {
    *session_auth.lock().await = auth;
    let env = main_http.get_session().env().clone();
    let store = AuthStore {
        env,
        auth: session_auth.clone(),
    };
    let client = main_http
        .build_client(store)
        .map_err(|e| MeetCoreError::AuthenticationFailed {
            message: format!("Failed to apply desktop login session: {e}"),
        })?;
    main_http.replace_session(client);
    Ok(())
}
