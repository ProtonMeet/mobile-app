//! Native-only muon persistence (`Store`). WASM uses `without_persistence` in [`super::support`].
//!
//! Locking: async code uses `.lock().await`; muon's sync `Store` uses
//! `lock_auth_sync` (`block_in_place` + `blocking_lock` on a tokio worker).
//! Never hold an async guard across muon/client calls — that can deadlock.

use std::collections::HashMap;
use std::sync::{Arc, OnceLock, RwLock};

use cfg_if::cfg_if;
use muon::{auth::Auth, store::Store, Environment};
use tokio::sync::Mutex;

/// Called when muon persists refreshed auth (e.g. after token rotation during API calls).
pub type AuthPersistCallback = Arc<dyn Fn(Auth) + Send + Sync>;

static AUTH_PERSIST_CALLBACK: OnceLock<RwLock<Option<AuthPersistCallback>>> = OnceLock::new();

fn auth_persist_slot() -> &'static RwLock<Option<AuthPersistCallback>> {
    AUTH_PERSIST_CALLBACK.get_or_init(|| RwLock::new(None))
}

/// Register a hook invoked whenever auth is written into the store (native only).
/// Used by the Flutter bridge to mirror tokens into platform secure storage.
pub fn set_auth_persist_callback(callback: Option<AuthPersistCallback>) {
    if let Ok(mut guard) = auth_persist_slot().write() {
        *guard = callback;
    }
}

fn notify_auth_persisted(auth: Auth) {
    if matches!(auth, Auth::None) {
        return;
    }
    if let Ok(guard) = auth_persist_slot().read() {
        if let Some(callback) = guard.as_ref() {
            callback(auth);
        }
    }
}

#[cfg(feature = "allow-dangerous-env")]
use super::support::MeetCustomEnv;
use super::support::{environment_from_str, MUON_DEFAULT_SESSION_KEY};

/// Shared handle to the active muon auth (Flutter bridge + desktop login).
pub type SharedAuth = Arc<Mutex<Auth>>;

/// Sync path for muon `Store` and `set_session_auth` (see module docs).
fn lock_auth_sync(auth: &SharedAuth) -> tokio::sync::MutexGuard<'_, Auth> {
    if let Ok(handle) = tokio::runtime::Handle::try_current() {
        if matches!(
            handle.runtime_flavor(),
            tokio::runtime::RuntimeFlavor::MultiThread
        ) {
            return tokio::task::block_in_place(|| auth.blocking_lock());
        }
        // `current_thread`: fall through to try_lock (lock must not be held across await).
    } else {
        return auth.blocking_lock();
    }

    loop {
        if let Ok(guard) = auth.try_lock() {
            return guard;
        }
        std::hint::spin_loop();
        std::thread::yield_now();
    }
}

/// Muon persistence store: environment + in-memory auth keyed by [`MUON_DEFAULT_SESSION_KEY`].
#[derive(Debug, Clone)]
pub struct AuthStore {
    pub environment: Environment,
    pub auth: SharedAuth,
}

impl Default for AuthStore {
    fn default() -> Self {
        Self::prod()
    }
}

impl AuthStore {
    pub fn from_env_str(env: String, auth: SharedAuth) -> Self {
        Self {
            environment: environment_from_str(&env),
            auth,
        }
    }

    pub fn from_custom_env_str(env: String, auth: SharedAuth) -> Self {
        Self::custom_env(env, auth)
    }

    pub fn new(environment: Environment) -> Self {
        Self {
            environment,
            auth: Arc::new(Mutex::new(Auth::None)),
        }
    }

    pub fn prod() -> Self {
        Self::new(Environment::new_prod())
    }

    pub fn atlas(option: Option<String>) -> Self {
        let environment = match option {
            Some(name) => Environment::new_atlas_name(name),
            None => Environment::new_atlas(),
        };
        Self::new(environment)
    }

    pub fn custom(env: impl muon::env::Env) -> Self {
        Self::new(Environment::new_custom(env))
    }

    pub async fn get_auth_async(&self) -> Auth {
        self.auth.lock().await.clone()
    }

    pub async fn set_auth_async(&self, auth: Auth) {
        *self.auth.lock().await = auth;
    }

    /// Write auth into the store the way muon expects (used before rebuilding the client).
    pub fn set_session_auth(&mut self, auth: Auth) {
        if matches!(auth, Auth::None) {
            *lock_auth_sync(&self.auth) = auth;
            return;
        }
        *lock_auth_sync(&self.auth) = auth.clone();
        notify_auth_persisted(auth);
    }
}

// Muon loads/saves auth through this during client build and sync.
impl Store for AuthStore {
    type Key = ();

    fn set_auth(&mut self, _key: Self::Key, auth: Auth) {
        if matches!(auth, Auth::None) {
            return;
        }
        *lock_auth_sync(&self.auth) = auth.clone();
        notify_auth_persisted(auth);
    }

    fn remove_auth(&mut self, _key: &Self::Key) {
        *lock_auth_sync(&self.auth) = Auth::None;
    }

    fn get_all_auth(&self) -> HashMap<Self::Key, Auth> {
        let auth = lock_auth_sync(&self.auth).clone();
        if matches!(auth, Auth::None) {
            HashMap::new()
        } else {
            HashMap::from([(MUON_DEFAULT_SESSION_KEY, auth)])
        }
    }
}

cfg_if! {
    if #[cfg(feature = "allow-dangerous-env")] {
        impl AuthStore {
            fn custom_env(env: String, auth: SharedAuth) -> Self {
                Self {
                    environment: Environment::new_custom(MeetCustomEnv { inner: env }),
                    auth,
                }
            }
        }
    } else {
        impl AuthStore {
            fn custom_env(_env: String, _auth: SharedAuth) -> Self {
                panic!("the `allow-dangerous-env` feature must be enabled");
            }
        }
    }
}
