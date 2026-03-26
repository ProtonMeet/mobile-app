use crate::domain::user::models::{user_settings::UserSettings, Address, UserId, UserTokenInfo};
use crate::errors::{core::MeetCoreError, login::LoginError, service::ServiceError};
use crate::infra::{dto::proton_user::UserData, ws_client::WebSocketMessage};
use mls_spec::{drafts::ratchet_tree_options::RatchetTreeOption, group::group_info::GroupInfo};
use mls_trait::{CommitBundle, MlsGroup};
use mls_types::{CipherSuite, ExternalPskId, MlsMessage};
use proton_meet_common::models::ProtonUser;
use proton_meet_common::models::ProtonUserKey;
use proton_meet_macro::async_trait_with_mock;
use proton_meet_mls::kv::MemKv;
use std::sync::Arc;
use tokio::sync::RwLock;

#[async_trait_with_mock]
pub trait UserService {
    async fn login(
        &self,
        username: &str,
        password: &str,
    ) -> Result<(UserData, ProtonUser, Vec<ProtonUserKey>, Vec<Address>), LoginError>;

    async fn logout(&self, user_id: &UserId) -> Result<(), anyhow::Error>;

    async fn create_mls_client(
        &self,
        access_token: &str,
        meet_link_name: &str,
        meeting_password: &str,
        use_psk: bool,
        session_id: Option<&str>,
    ) -> Result<UserTokenInfo, anyhow::Error>;

    async fn create_mls_group(
        &self,
        participant_id: &UserId,
        group_id: &str,
        meeting_link_name: &str,
        cs: CipherSuite,
    ) -> Result<(Arc<RwLock<MlsGroup<MemKv>>>, CommitBundle), anyhow::Error>;

    async fn create_external_commit(
        &self,
        participant_id: &UserId,
        meeting_link_name: &str,
        cs: CipherSuite,
        group_info: GroupInfo,
        ratchet_tree_option: RatchetTreeOption,
    ) -> Result<(Arc<RwLock<MlsGroup<MemKv>>>, CommitBundle), anyhow::Error>;

    async fn create_external_proposal(
        &self,
        participant_id: &UserId,
        cs: CipherSuite,
        group_info: GroupInfo,
        ratchet_tree_option: RatchetTreeOption,
    ) -> Result<MlsMessage, anyhow::Error>;

    async fn join_group(
        &self,
        participant_id: &UserId,
        meeting_link_name: &str,
        welcome_message: MlsMessage,
        ratchet_tree_option: RatchetTreeOption,
    ) -> Result<Arc<RwLock<MlsGroup<MemKv>>>, anyhow::Error>;

    async fn create_leave_proposal(
        &self,
        participant_id: &UserId,
        mls_group: &mut MlsGroup<MemKv>,
        cs: CipherSuite,
    ) -> Result<mls_types::MlsMessage, anyhow::Error>;

    async fn handle_websocket_message(
        &self,
        message: WebSocketMessage,
    ) -> Result<(), anyhow::Error>;

    async fn get_group_key(&self, meeting_link_name: &str) -> Result<(String, u64), anyhow::Error>;

    async fn get_group_len(&self, meeting_link_name: &str) -> Result<u32, anyhow::Error>;

    async fn get_group_display_code(
        &self,
        meeting_link_name: &str,
    ) -> Result<String, anyhow::Error>;

    async fn encrypt_application_message(
        &self,
        meeting_link_name: &str,
        message: &str,
    ) -> Result<MlsMessage, anyhow::Error>;

    async fn decrypt_application_message(
        &self,
        meeting_link_name: &str,
        message: MlsMessage,
    ) -> Result<(String, UserId), anyhow::Error>;

    async fn join_room(
        &self,
        user_info_token: &UserTokenInfo,
        meeting_link_name: &str,
        use_psk: bool,
    ) -> Result<(), MeetCoreError>;

    async fn join_room_with_proposal(
        &self,
        participant_id: &UserId,
        meeting_link_name: &str,
    ) -> Result<(), MeetCoreError>;

    async fn leave_room(
        &self,
        user_identifier: &UserId,
        meeting_link_name: &str,
    ) -> Result<(), anyhow::Error>;

    async fn handle_proposal(
        &self,
        room_id: &str,
        proposal: mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error>;

    async fn get_sd_kbt(&self, participant_id: &UserId) -> Result<String, anyhow::Error>;

    async fn get_meeting_id(&self, user_identifier: &UserId) -> Result<String, anyhow::Error>;

    async fn login_with_two_factor(&self, two_factor_code: &str) -> Result<UserData, LoginError>;

    async fn get_user(&self, user_id: &UserId) -> Result<ProtonUser, ServiceError>;

    async fn get_user_keys(&self, user_id: &UserId) -> Result<Vec<ProtonUserKey>, anyhow::Error>;

    async fn get_user_addresses(&self) -> Result<Vec<Address>, anyhow::Error>;

    async fn get_user_settings(&self) -> Result<UserSettings, anyhow::Error>;

    async fn handle_livekit_admin_change(
        &self,
        room_id: &str,
        participant_uid: String,
        participant_type: u32,
    ) -> Result<(), anyhow::Error>;

    async fn kick_participant(
        &self,
        target_participant_id: &str,
        meeting_link_name: &str,
    ) -> Result<(), MeetCoreError>;

    async fn check_and_update_host_role(&self, room_id: &str) -> Result<(), anyhow::Error>;

    async fn create_self_remove_participant_update_proposal(
        &self,
        mls_group: &mut MlsGroup<MemKv>,
    ) -> Result<Option<mls_types::MlsMessage>, anyhow::Error>;

    async fn create_external_commit_with_psks(
        &self,
        participant_id: &UserId,
        meeting_link_name: &str,
        cs: CipherSuite,
        group_info: GroupInfo,
        ratchet_tree_option: RatchetTreeOption,
        external_psks: Vec<ExternalPskId>,
    ) -> Result<(Arc<RwLock<MlsGroup<MemKv>>>, CommitBundle), anyhow::Error>;
}
