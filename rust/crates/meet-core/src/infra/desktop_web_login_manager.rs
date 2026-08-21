//! Ephemeral desktop web login session — isolated from the main app muon client.
//! Drop or cancel when login finishes or is abandoned.

use muon::auth::Auth;
use muon::Environment;

use crate::errors::core::MeetCoreError;
use crate::errors::http_client::HttpClientError;
use crate::infra::desktop_web_login::{
    self, DesktopWebLoginPoll, DesktopWebLoginStart, PendingState,
};
use crate::infra::http_client::{ApiConfig, ProtonHttpClient};
use crate::infra::muon::{AuthStore, SharedAuth};

/// Standalone manager for one desktop web login attempt.
#[cfg(not(target_arch = "wasm32"))]
pub struct DesktopWebLoginManager {
    login_http: ProtonHttpClient,
    main_http: ProtonHttpClient,
    session_auth: SharedAuth,
    pending: Option<PendingState>,
}

#[cfg(not(target_arch = "wasm32"))]
impl DesktopWebLoginManager {
    pub async fn new(
        env: String,
        app_version: String,
        user_agent: String,
        http_host: String,
        main_http: ProtonHttpClient,
        session_auth: SharedAuth,
    ) -> Result<Self, MeetCoreError> {
        let environment: Environment =
            env.parse()
                .map_err(|_| MeetCoreError::AuthenticationFailed {
                    message: format!("Invalid environment for desktop web login: {env}"),
                })?;
        let config = ApiConfig {
            spec: (app_version, user_agent),
            auth: None,
            url_prefix: None,
            env: Some(env),
            proxy: None,
        };
        let login_http = ProtonHttpClient::new_with_server_time(
            config,
            AuthStore::new(environment),
            http_host,
            main_http.server_time_tracker(),
        )
        .await
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
        let (start, pending) = desktop_web_login::start(&self.login_http, child_client_id).await?;
        self.pending = Some(pending);
        Ok(start)
    }

    pub async fn poll(&mut self) -> Result<DesktopWebLoginPoll, MeetCoreError> {
        if self.pending.is_none() {
            // Another poll call already holds the pending state, or login was cancelled.
            return Ok(DesktopWebLoginPoll::Pending);
        }

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
    session_auth: &SharedAuth,
    auth: Auth,
) -> Result<(), MeetCoreError> {
    *session_auth.lock().await = auth;
    let environment = main_http.get_session().env().clone();
    let store = AuthStore {
        environment,
        auth: session_auth.clone(),
    };
    main_http
        .sync_auth_store(store)
        .await
        .map_err(|e| MeetCoreError::AuthenticationFailed {
            message: match e {
                HttpClientError::MlsHttpError { message } => message,
                other => format!("Unable to complete sign-in. Please try again. ({other})"),
            },
        })
}
