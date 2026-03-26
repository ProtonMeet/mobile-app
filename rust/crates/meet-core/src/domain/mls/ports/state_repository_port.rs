use proton_meet_macro::async_trait_with_mock;

use crate::service::service_state::MlsGroupState;

/// Port for state management
#[async_trait_with_mock]
pub trait StateRepositoryPort: Send + Sync {
    async fn get_mls_state(&self, room_id: &str) -> Result<MlsGroupState, anyhow::Error>;

    async fn set_mls_state(&self, room_id: &str, state: MlsGroupState)
        -> Result<(), anyhow::Error>;
}
