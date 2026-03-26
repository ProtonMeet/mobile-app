use std::sync::Arc;

use flutter_rust_bridge::{frb, DartFnFuture};
use proton_meet_core::infra::UserKeyProviderAdapter;

// Define a new struct that wraps UserKeyProviderAdapter
pub struct FrbUserKeyProvider {
    pub(crate) inner: UserKeyProviderAdapter,
}

impl FrbUserKeyProvider {
    #[frb(sync)]
    pub fn new() -> Self {
        FrbUserKeyProvider {
            inner: UserKeyProviderAdapter::new(),
        }
    }

    pub async fn set_get_passphrase_callback(
        &mut self,
        callback: impl Fn(String) -> DartFnFuture<String> + Send + Sync + 'static,
    ) {
        self.inner
            .set_get_user_key_passphrase_callback(Arc::new(callback))
            .await
    }

    pub async fn clear_auth_dart_callback(&self) {
        self.inner.clear().await;
    }
}
