use crate::domain::user::models::meet_link_info::MeetParticipant;
use crate::domain::user::models::participant_track_settings::ParticipantTrackSettings;
use crate::domain::user::models::{
    login::Modulus,
    meet_link_info::{AccessTokenInfo, MeetLinkAuthInfo, MeetLinkInfo},
    meeting::{Meeting, MeetingInfo},
    user_settings::UserSettings,
};
use crate::errors::http_client::HttpClientError;
use crate::infra::dto::realtime::{
    GroupInfoSummaryData, MlsCommitInfo, MlsProposalInfo, ServiceMetricsRequest,
    VersionedGroupInfoData,
};
use mls_spec::{drafts::ratchet_tree_options::RatchetTreeOption, messages::MlsMessage};
use proton_meet_macro::async_trait_with_mock;

#[async_trait_with_mock]
pub trait HttpClient: Send + Sync {
    async fn get_group_info(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<VersionedGroupInfoData, HttpClientError>;

    async fn get_group_info_summary(
        &self,
        base64_sd_kbt: &str,
    ) -> Result<GroupInfoSummaryData, HttpClientError>;

    async fn update_group_info(
        &self,
        base64_sd_kbt: &str,
        mls_message: &MlsMessage,
        ratchet_tree: &RatchetTreeOption,
        mls_commit_info: Option<&MlsCommitInfo>,
        proposals: Option<Vec<MlsProposalInfo>>,
    ) -> Result<(), HttpClientError>;

    async fn join_group_by_proposal(
        &self,
        base64_sd_kbt: &str,
        mls_message: &MlsMessage,
    ) -> Result<(), HttpClientError>;

    async fn auth_meet_link(
        &self,
        meet_link_name: &str,
        client_ephemeral: &str,
        client_proof: &str,
        srp_session: &str,
    ) -> Result<MeetLinkAuthInfo, HttpClientError>;

    async fn update_participant_track_settings(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
        audio_enabled: Option<u8>,
        video_enabled: Option<u8>,
    ) -> Result<ParticipantTrackSettings, HttpClientError>;

    async fn fetch_access_token(
        &self,
        meet_link_name: &str,
        display_name: &str,
        encrypted_display_name: &str,
    ) -> Result<AccessTokenInfo, HttpClientError>;

    async fn get_meet_info(
        &self,
        meet_link_name: &str,
    ) -> Result<MeetingInfo, HttpClientError>;

    async fn get_active_meetings(&self) -> Result<Vec<Meeting>, HttpClientError>;

    async fn get_user_settings(&self) -> Result<UserSettings, HttpClientError>;

    async fn get_meet_link_info(
        &self,
        meet_link_name: &str,
    ) -> Result<MeetLinkInfo, HttpClientError>;

    async fn get_participants(
        &self,
        meet_link_name: &str,
    ) -> Result<Vec<MeetParticipant>, HttpClientError>;

    async fn get_participants_count(&self, meet_link_name: &str) -> Result<u32, HttpClientError>;

    async fn fetch_sd_cwt(
        &self,
        meet_link_name: &str,
        access_token: &str,
        base64_holder_confirmation_key: &str,
        session_id: Option<&str>,
    ) -> Result<String, HttpClientError>;

    async fn fetch_cose_key_set(&self) -> Result<Vec<u8>, HttpClientError>;

    async fn get_modulus(&self) -> Result<Modulus, HttpClientError>;

    async fn remove_participant(
        &self,
        meet_link_name: &str,
        access_token: &str,
        participant_uuid: &str,
    ) -> Result<(), HttpClientError>;

    async fn send_metrics(
        &self,
        base64_sd_kbt: &str,
        app_version: &str,
        user_agent: &str,
        metrics_request: &ServiceMetricsRequest,
    ) -> Result<(), HttpClientError>;

    /// Ping the server and return RTT in milliseconds
    async fn ping(&self) -> Result<u64, HttpClientError>;

    async fn fetch_external_sender(&self) -> Result<Vec<u8>, HttpClientError>;
}
