use std::sync::Arc;

use proton_meet_macro::async_trait;
use tokio::sync::Mutex;

use crate::domain::mls::ports::StateRepositoryPort;
use crate::service::service_state::{MlsGroupState, ServiceState};

/// Adapter that implements StateRepositoryPort using existing ServiceState
pub struct StateRepositoryAdapter {
    state: Arc<Mutex<ServiceState>>,
}

impl StateRepositoryAdapter {
    pub fn new(state: Arc<Mutex<ServiceState>>) -> Self {
        Self { state }
    }
}

#[async_trait]
impl StateRepositoryPort for StateRepositoryAdapter {
    async fn get_mls_state(&self, _room_id: &str) -> Result<MlsGroupState, anyhow::Error> {
        let state = self.state.lock().await;
        Ok(state.mls_group_state.clone())
    }

    async fn set_mls_state(
        &self,
        _room_id: &str,
        state: MlsGroupState,
    ) -> Result<(), anyhow::Error> {
        let mut service_state = self.state.lock().await;
        service_state.set_mls_group_state(state);
        Ok(())
    }
}
