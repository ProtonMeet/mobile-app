use std::collections::HashMap;
use std::sync::Arc;

use async_trait::async_trait;
use cfg_if::cfg_if;
#[cfg(feature = "allow-dangerous-env")]
use muon::{app::AppVersion, common::Server, tls::TlsPinSet};
use muon::{
    client::Auth,
    common::IntoDyn,
    deps::cfg_if,
    env::{Env, EnvId},
    store::{Store, StoreError},
};
use tokio::sync::Mutex;

/// Single-session key used by Meet's one-account `AuthStore`.
pub const MUON_DEFAULT_SESSION_KEY: () = ();

/// Sized wrapper so muon can ingest a boxed store via `Client::builder`.
pub struct BoxedStore(pub Box<dyn Store<()>>);

#[async_trait]
impl Store<()> for BoxedStore {
    fn env(&self) -> EnvId {
        self.0.env()
    }

    async fn get_auth(&self, key: &()) -> Result<Auth, StoreError> {
        self.0.get_auth(key).await
    }

    async fn set_auth(&mut self, key: &(), auth: Auth) -> Result<(), StoreError> {
        self.0.set_auth(key, auth).await
    }

    async fn remove_auth(&mut self, key: &()) -> Result<Option<Auth>, StoreError> {
        self.0.remove_auth(key).await
    }

    async fn get_all_auth(&self) -> Result<HashMap<(), Auth>, StoreError> {
        self.0.get_all_auth().await
    }

    async fn set_all_auth(&mut self, auth: HashMap<(), Auth>) -> Result<(), StoreError> {
        self.0.set_all_auth(auth).await
    }

    async fn remove_all_auth(&mut self) -> Result<(), StoreError> {
        self.0.remove_all_auth().await
    }
}

#[derive(Debug, Clone)]
pub struct AuthStore {
    pub env: EnvId,
    pub auth: Arc<Mutex<Auth>>,
}

impl Default for AuthStore {
    fn default() -> Self {
        Self::prod()
    }
}

impl AuthStore {
    pub fn from_env_str(env: String, auth: Arc<Mutex<Auth>>) -> Self {
        if let Ok(env) = env.parse() {
            Self { env, auth }
        } else {
            Self::custom_env(env, auth)
        }
    }

    pub fn from_custom_env_str(env: String, auth: Arc<Mutex<Auth>>) -> Self {
        Self::custom_env(env, auth)
    }

    /// Create a new store for the given environment.
    pub fn new(env: EnvId) -> Self {
        Self {
            env,
            auth: Arc::new(Mutex::new(Auth::None)),
        }
    }

    /// Create a new prod store.
    pub fn prod() -> Self {
        Self::new(EnvId::Prod)
    }

    /// Create a new atlas store.
    pub fn atlas(option: Option<String>) -> Self {
        Self::new(EnvId::Atlas(option))
    }

    /// Create a new store for a custom environment.
    pub fn custom(env: impl Env) -> Self {
        Self::new(EnvId::Custom(env.into_dyn()))
    }
}

#[async_trait]
impl Store<()> for AuthStore {
    fn env(&self) -> EnvId {
        self.env.clone()
    }

    async fn get_auth(&self, _key: &()) -> Result<Auth, StoreError> {
        Ok(self.auth.lock().await.clone())
    }

    async fn set_auth(&mut self, _key: &(), auth: Auth) -> Result<(), StoreError> {
        *self.auth.lock().await = auth;
        Ok(())
    }

    async fn remove_auth(&mut self, _key: &()) -> Result<Option<Auth>, StoreError> {
        let mut guard = self.auth.lock().await;
        if matches!(*guard, Auth::None) {
            return Ok(None);
        }
        let removed = guard.clone();
        *guard = Auth::None;
        Ok(Some(removed))
    }

    async fn get_all_auth(&self) -> Result<HashMap<(), Auth>, StoreError> {
        let auth = self.get_auth(&MUON_DEFAULT_SESSION_KEY).await?;
        if matches!(auth, Auth::None) {
            Ok(HashMap::new())
        } else {
            Ok(HashMap::from([(MUON_DEFAULT_SESSION_KEY, auth)]))
        }
    }

    async fn set_all_auth(&mut self, auth: HashMap<(), Auth>) -> Result<(), StoreError> {
        if let Some(auth) = auth.get(&MUON_DEFAULT_SESSION_KEY) {
            self.set_auth(&MUON_DEFAULT_SESSION_KEY, auth.clone()).await
        } else {
            self.remove_auth(&MUON_DEFAULT_SESSION_KEY).await?;
            Ok(())
        }
    }

    async fn remove_all_auth(&mut self) -> Result<(), StoreError> {
        self.remove_auth(&MUON_DEFAULT_SESSION_KEY).await?;
        Ok(())
    }
}

cfg_if! {
    if #[cfg(feature = "allow-dangerous-env")] {
        struct MeetCustomEnv {
            inner: String,
        }
        /// Implement [`Env`] to specify the servers for the custom environment.
        impl Env for MeetCustomEnv {
            fn servers(&self, _: &AppVersion) -> Vec<Server> {
                vec![self.inner.as_str().parse().expect("Invalid server address")]
            }

            fn pins(&self, _: &Server) -> Option<TlsPinSet> {
                None
            }
        }

        impl AuthStore {
            fn custom_env(env: String, auth: Arc<Mutex<Auth>>) -> Self {
                Self {
                    env: EnvId::Custom(MeetCustomEnv{inner: env}.into_dyn()),
                    auth,
                }
            }
        }
    } else {
        impl AuthStore {
            fn custom_env(_env: String, _auth: Arc<Mutex<Auth>>) -> Self {
                panic!("the `allow-dangerous-env` feature must be enabled");
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::infra::auth_store::AuthStore;
    use muon::env::EnvId;

    #[test]
    fn test_build_auth_store() {
        use std::sync::Arc;

        use muon::client::Auth;

        let auth = Arc::new(tokio::sync::Mutex::new(Auth::None));
        let store = AuthStore::from_env_str("prod".to_string(), auth.clone());
        assert!(matches!(store.env, EnvId::Prod));
        let store = AuthStore::from_env_str("atlas".to_string(), auth.clone());
        assert!(matches!(store.env, EnvId::Atlas(None)));
        let store = AuthStore::from_env_str("atlas:scientist".to_string(), auth.clone());
        assert!(matches!(store.env, EnvId::Atlas(Some(name)) if name == "scientist"));

        #[cfg(feature = "allow-dangerous-env")]
        {
            let store =
                AuthStore::from_custom_env_str("http://localhost:8080".to_string(), auth.clone());
            assert!(matches!(store.env, EnvId::Custom(_)));
        }
    }

    #[test]
    fn test_parse_env_id() {
        let env: EnvId = "prod".parse().unwrap();
        assert!(matches!(env, EnvId::Prod));

        let env: EnvId = "atlas".parse().unwrap();
        assert!(matches!(env, EnvId::Atlas(None)));

        let env: EnvId = "atlas:scientist".parse().unwrap();
        assert!(matches!(env, EnvId::Atlas(Some(name)) if name == "scientist"));
    }
}
