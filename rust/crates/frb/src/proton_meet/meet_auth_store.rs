use std::sync::Arc;

use crate::errors::BridgeError;
use flutter_rust_bridge::{frb, DartFnFuture};
use proton_meet_core::muon::Auth;
use proton_meet_core::{
    infra::auth_store::{AuthStore, SharedAuth},
    muon::{EnvId, Tokens},
};

pub type DartCallback = dyn Fn(ChildAuthSession) -> DartFnFuture<String> + Send + Sync;

lazy_static::lazy_static! {
    static ref MEET_AUTH_STORE_DART_CALLBACK: Arc<tokio::sync::Mutex<Option<Arc<DartCallback>>>> =
        Arc::new(tokio::sync::Mutex::new(None));
}

#[derive(Debug, Clone)]
#[frb(opaque)]
// Define a new struct that wraps AuthStore
pub struct ProtonMeetAuthStore {
    pub(crate) inner: AuthStore,
}

impl ProtonMeetAuthStore {
    #[frb(sync)]
    pub fn new(env: &str) -> Result<Self, BridgeError> {
        let auth = Arc::new(tokio::sync::Mutex::new(Auth::None));
        ProtonMeetAuthStore::from_auth(env, auth)
    }

    #[frb(ignore)]
    pub(crate) fn from_auth(env: &str, auth: SharedAuth) -> Result<Self, BridgeError> {
        let store = AuthStore::from_env_str(env.to_string(), auth);
        Ok(Self { inner: store })
    }

    #[frb(sync)]
    pub fn from_session(
        env: &str,
        user_id: String,
        uid: String,
        access: String,
        refresh: String,
        scopes: Vec<String>,
    ) -> Result<Self, BridgeError> {
        let auth = Auth::internal(user_id, uid, Tokens::access(access, refresh, scopes));
        ProtonMeetAuthStore::from_auth(env, Arc::new(tokio::sync::Mutex::new(auth)))
    }

    pub async fn set_auth(
        &mut self,
        user_id: String,
        uid: String,
        access: String,
        refresh: String,
        scopes: Vec<String>,
    ) -> Result<(), BridgeError> {
        let auth = Auth::internal(user_id, uid, Tokens::access(access, refresh, scopes));
        let mut store = self.inner.clone();
        store.set_session_auth(auth.clone());
        self.inner = store;
        self.refresh_auth_credential(auth).await;
        Ok(())
    }

    #[frb(ignore)]
    pub async fn get_auth(&self) -> Auth {
        self.inner.get_auth_async().await
    }

    #[frb(ignore)]
    pub fn environment(&self) -> EnvId {
        self.inner.environment.clone()
    }

    pub async fn set_auth_dart_callback(
        &mut self,
        callback: impl Fn(ChildAuthSession) -> DartFnFuture<String> + Send + Sync + 'static,
    ) -> Result<(), BridgeError> {
        let mut cb = MEET_AUTH_STORE_DART_CALLBACK.lock().await;
        *cb = Some(Arc::new(callback));
        Ok(())
    }

    pub async fn clear_auth_dart_callback(&self) -> Result<(), BridgeError> {
        let mut cb = MEET_AUTH_STORE_DART_CALLBACK.lock().await;
        *cb = None;
        Ok(())
    }

    #[frb(ignore)]
    pub async fn logout(&mut self) -> Result<(), BridgeError> {
        let mut cb = MEET_AUTH_STORE_DART_CALLBACK.lock().await;
        *cb = None;
        *self.inner.auth.lock().await = Auth::None;
        Ok(())
    }

    async fn refresh_auth_credential(&self, auth: Auth) {
        // Clone the callback outside the async block
        let callback_option = {
            let guard = MEET_AUTH_STORE_DART_CALLBACK.lock().await;
            guard.as_ref().cloned()
        };

        flutter_rust_bridge::spawn(async move {
            if let Some(callback) = callback_option {
                let session = ChildAuthSession {
                    scopes: auth
                        .scopes()
                        .map(|scopes| scopes.iter().cloned().collect())
                        .unwrap_or_default(),
                    session_id: auth.uid().unwrap_or_default().to_string(),
                    access_token: auth.acc_tok().unwrap_or_default().to_string(),
                    refresh_token: auth.ref_tok().unwrap_or_default().to_string(),
                    user_id: auth.user_id().unwrap_or_default().to_string(),
                };
                let _msg = callback(session).await;
            }
        });
    }
}

#[derive(Debug, Clone)]
pub struct ChildAuthSession {
    pub session_id: String,
    pub access_token: String,
    pub refresh_token: String,
    pub scopes: Vec<String>,
    pub user_id: String,
}
