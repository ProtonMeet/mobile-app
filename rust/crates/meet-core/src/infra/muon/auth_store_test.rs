use std::collections::HashMap;
use std::sync::Arc;

use muon::{auth::Auth, store::Store, Environment};
use tokio::sync::Mutex;

use super::auth_store::AuthStore;
use crate::infra::muon::support::{test_support, MUON_DEFAULT_SESSION_KEY};

fn sample_auth() -> Auth {
    Auth::external("user-id", "uid-123")
}

#[test]
fn default_is_prod() {
    let store = AuthStore::default();
    assert!(matches!(store.environment, Environment::Prod(_)));
}

#[test]
fn prod_constructor() {
    assert!(matches!(
        AuthStore::prod().environment,
        Environment::Prod(_)
    ));
}

#[test]
fn atlas_constructors() {
    assert!(matches!(
        AuthStore::atlas(None).environment,
        Environment::Atlas(_)
    ));
    assert!(matches!(
        AuthStore::atlas(Some("scientist".to_string())).environment,
        Environment::Scientist(_)
    ));
}

#[cfg(feature = "allow-dangerous-env")]
#[test]
fn custom_constructor() {
    use crate::infra::muon::support::MeetCustomEnv;

    let store = AuthStore::custom(MeetCustomEnv {
        inner: "http://localhost:8080".to_string(),
    });
    assert!(matches!(store.environment, Environment::Custom(_)));
}

#[test]
fn build_auth_store_environments() {
    let auth = Arc::new(Mutex::new(Auth::None));
    let store = AuthStore::from_env_str("prod".to_string(), auth.clone());
    assert!(matches!(store.environment, Environment::Prod(_)));
    let store = AuthStore::from_env_str("atlas".to_string(), auth.clone());
    assert!(matches!(store.environment, Environment::Atlas(_)));
    let store = AuthStore::from_env_str("atlas:scientist".to_string(), auth.clone());
    assert!(matches!(store.environment, Environment::Scientist(_)));

    test_support::assert_scientist_meet_api_host();

    #[cfg(feature = "allow-dangerous-env")]
    {
        let store =
            AuthStore::from_custom_env_str("http://localhost:8080".to_string(), auth.clone());
        assert!(matches!(store.environment, Environment::Custom(_)));
    }
}

#[tokio::test]
async fn auth_async_roundtrip() {
    let store = AuthStore::from_env_str("atlas".to_string(), Arc::new(Mutex::new(Auth::None)));
    assert!(matches!(store.get_auth_async().await, Auth::None));
    store.set_auth_async(Auth::None).await;
    assert!(matches!(store.get_auth_async().await, Auth::None));
}

#[tokio::test]
async fn set_session_auth_updates_auth() {
    let mut store = AuthStore::from_env_str("atlas".to_string(), Arc::new(Mutex::new(Auth::None)));
    store.set_session_auth(sample_auth());
    assert_eq!(store.get_auth_async().await, sample_auth());
}

#[test]
fn store_set_auth_stores_non_none() {
    let mut store = AuthStore::atlas(None);
    let auth = sample_auth();
    store.set_auth(MUON_DEFAULT_SESSION_KEY, auth.clone());
    assert_eq!(
        store.get_all_auth(),
        HashMap::from([(MUON_DEFAULT_SESSION_KEY, auth)])
    );
}

#[test]
fn store_set_auth_ignores_none() {
    let mut store = AuthStore::atlas(None);
    let auth = sample_auth();
    store.set_auth(MUON_DEFAULT_SESSION_KEY, auth.clone());
    store.set_auth(MUON_DEFAULT_SESSION_KEY, Auth::None);
    assert_eq!(
        store.get_all_auth(),
        HashMap::from([(MUON_DEFAULT_SESSION_KEY, auth)])
    );
}

#[test]
fn store_remove_auth_clears_session() {
    let mut store = AuthStore::atlas(None);
    store.set_auth(MUON_DEFAULT_SESSION_KEY, sample_auth());
    store.remove_auth(&MUON_DEFAULT_SESSION_KEY);
    assert!(store.get_all_auth().is_empty());
}

#[test]
fn store_get_all_auth_empty() {
    let store = AuthStore::atlas(None);
    assert!(store.get_all_auth().is_empty());
}

#[test]
fn store_get_all_auth_returns_session() {
    let mut store = AuthStore::atlas(None);
    let auth = sample_auth();
    store.set_auth(MUON_DEFAULT_SESSION_KEY, auth.clone());
    let all = store.get_all_auth();
    assert_eq!(all.len(), 1);
    assert_eq!(all.get(&MUON_DEFAULT_SESSION_KEY), Some(&auth));
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn sync_store_does_not_deadlock_with_concurrent_async_read() {
    let auth = Arc::new(Mutex::new(Auth::None));
    let mut store = AuthStore::from_env_str("atlas".to_string(), auth);

    let reader = {
        let store = store.clone();
        tokio::spawn(async move {
            for _ in 0..50 {
                let _ = store.get_auth_async().await;
                tokio::task::yield_now().await;
            }
        })
    };

    for i in 0..50 {
        store.set_session_auth(Auth::None);
        if i % 2 == 0 {
            let _ = store.get_all_auth();
        }
        tokio::task::yield_now().await;
    }

    reader.await.unwrap();
}
