use crate::domain::user::models::{Address, UserTokenInfo};
use crate::infra::dto::realtime::JoinType;
use crate::utils::PlatformInstant;
use proton_meet_common::models::{ProtonUser, ProtonUserKey};
use proton_meet_mls::MlsStore;
use std::sync::Arc;
use tokio::sync::RwLock;

pub struct AppState {
    pub app_version: Option<String>,
    pub user_agent: Option<String>,
    pub active_user: Option<UserState>,
    pub active_livekit_access_token: Option<String>,
    pub active_livekit_websocket_url: Option<String>,
    /// Base64-encoded decrypted meeting session key; used to decrypt participant display names.
    pub meeting_display_name_session_key: Option<String>,
    pub mls_store: Arc<RwLock<MlsStore>>,
    pub active_user_info: Option<UserTokenInfo>,
    pub join_start_time: Option<PlatformInstant>,
    pub join_mls_time: Option<PlatformInstant>,
    pub join_type: Option<JoinType>,
    pub use_psk: bool,
}

#[derive(Debug)]
pub struct UserState {
    pub user_data: ProtonUser,
    pub user_keys: Vec<ProtonUserKey>,
    pub user_addresses: Vec<Address>,
}

impl Clone for UserState {
    fn clone(&self) -> Self {
        Self {
            user_data: self.user_data.clone(),
            user_keys: self.user_keys.to_vec(),
            user_addresses: self.user_addresses.clone(),
        }
    }
}

impl UserState {
    pub fn new(
        user_data: ProtonUser,
        user_keys: Vec<ProtonUserKey>,
        user_addresses: Vec<Address>,
    ) -> Self {
        Self {
            user_data,
            user_keys,
            user_addresses,
        }
    }

    pub fn user_data(&self) -> &ProtonUser {
        &self.user_data
    }

    pub fn user_keys(&self) -> &Vec<ProtonUserKey> {
        &self.user_keys
    }

    pub fn user_addresses(&self) -> &Vec<Address> {
        &self.user_addresses
    }
}

/// Helper struct containing user authentication and address information
/// extracted from the active user state
pub struct UserStateInfo {
    pub active_user_key: ProtonUserKey,
    pub user_id: String,
    pub primary_address: Address,
}
