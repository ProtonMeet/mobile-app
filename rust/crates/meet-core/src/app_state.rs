use crate::domain::user::models::meeting_session_key::MeetingSessionKey;
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
    pub meeting_display_name_session_key: Option<MeetingSessionKey>,
    pub mls_store: Arc<RwLock<MlsStore>>,
    pub active_user_info: Option<UserTokenInfo>,
    pub join_start_time: Option<PlatformInstant>,
    pub join_mls_time: Option<PlatformInstant>,
    pub total_join_start_time: Option<PlatformInstant>,
    pub join_type: Option<JoinType>,
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

/// Picks the user key most likely to unlock with the mailbox password for crypto
/// (e.g. OpenPGP self-encryption when creating a meeting).
///
/// Order: primary+active → any active → any primary → first in list.
pub(crate) fn preferred_user_key_for_crypto(keys: &[ProtonUserKey]) -> Option<&ProtonUserKey> {
    if keys.is_empty() {
        return None;
    }
    keys.iter()
        .find(|k| k.primary != 0 && k.active != 0)
        .or_else(|| keys.iter().find(|k| k.active != 0))
        .or_else(|| keys.iter().find(|k| k.primary != 0))
        .or_else(|| keys.first())
}

/// Helper struct containing user authentication and address information
/// extracted from the active user state
pub struct UserStateInfo {
    pub active_user_key: ProtonUserKey,
    pub user_id: String,
    pub primary_address: Address,
}

#[cfg(test)]
mod preferred_user_key_tests {
    use super::*;

    fn key(id: &str, primary: u32, active: u32) -> ProtonUserKey {
        ProtonUserKey {
            id: id.to_string(),
            version: 0,
            private_key: String::new(),
            recovery_secret: None,
            recovery_secret_signature: None,
            token: None,
            fingerprint: String::new(),
            signature: None,
            primary,
            active,
        }
    }

    #[test]
    fn prefers_primary_and_active() {
        let keys = vec![
            key("old", 0, 0),
            key("primary_active", 1, 1),
            key("active_only", 0, 1),
        ];
        assert_eq!(
            preferred_user_key_for_crypto(&keys).unwrap().id,
            "primary_active"
        );
    }

    #[test]
    fn falls_back_to_first_active() {
        let keys = vec![key("a", 0, 0), key("b", 0, 1), key("c", 0, 0)];
        assert_eq!(preferred_user_key_for_crypto(&keys).unwrap().id, "b");
    }

    #[test]
    fn falls_back_to_primary_when_no_active() {
        let keys = vec![key("a", 0, 0), key("b", 1, 0)];
        assert_eq!(preferred_user_key_for_crypto(&keys).unwrap().id, "b");
    }

    #[test]
    fn falls_back_to_first_key() {
        let keys = vec![key("only", 0, 0)];
        assert_eq!(preferred_user_key_for_crypto(&keys).unwrap().id, "only");
    }
}

#[cfg(test)]
mod user_state_tests {
    use super::*;

    fn sample_user(id: &str) -> ProtonUser {
        ProtonUser {
            id: id.to_string(),
            name: "Test User".to_string(),
            email: "test@example.com".to_string(),
            ..Default::default()
        }
    }

    fn sample_key(id: &str) -> ProtonUserKey {
        ProtonUserKey {
            id: id.to_string(),
            version: 0,
            private_key: String::new(),
            recovery_secret: None,
            recovery_secret_signature: None,
            token: None,
            fingerprint: String::new(),
            signature: None,
            primary: 1,
            active: 1,
        }
    }

    fn sample_address(id: &str) -> Address {
        Address {
            id: id.to_string(),
            email: "test@example.com".to_string(),
            keys: vec![],
        }
    }

    #[test]
    fn new_stores_fields() {
        let user = sample_user("user-1");
        let keys = vec![sample_key("key-1")];
        let addresses = vec![sample_address("addr-1")];

        let state = UserState::new(user.clone(), keys.clone(), addresses.clone());

        assert_eq!(state.user_data().id, user.id);
        assert_eq!(state.user_keys().len(), 1);
        assert_eq!(state.user_keys()[0].id, "key-1");
        assert_eq!(state.user_addresses().len(), 1);
        assert_eq!(state.user_addresses()[0].id, "addr-1");
    }

    #[test]
    fn clone_produces_equal_state() {
        let state = UserState::new(
            sample_user("user-1"),
            vec![sample_key("key-1")],
            vec![sample_address("addr-1")],
        );
        let cloned = state.clone();

        assert_eq!(cloned.user_data().id, state.user_data().id);
        assert_eq!(cloned.user_keys().len(), state.user_keys().len());
        assert_eq!(cloned.user_addresses().len(), state.user_addresses().len());
    }
}
