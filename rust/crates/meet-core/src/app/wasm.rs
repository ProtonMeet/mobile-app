use super::{App, DecryptedMessageInfo};

use crate::chat::{
    ChatComposeRequest, ChatComposeResult, ChatIncomingEventInfo, MessageId, ReplyTarget,
};
use crate::domain::room::{JoinRequestChange, SubmitJoinRequestResponse};
use crate::domain::user::models::{
    access_token::AccessToken, meeting_link_name::MeetingLinkName,
    meeting_password::MeetingPassword, meeting_session_key::MeetingSessionKey,
};
use crate::domain::user::ports::ConnectionState;
use crate::errors::core::MeetCoreError;
use crate::infra::{
    dto::realtime::{JoinType, RejoinReason},
    http_client::ApiConfig,
};
use muon::auth::Auth;
use std::sync::Arc;

use wasm_bindgen::prelude::wasm_bindgen;
use wasm_bindgen::JsValue;

use crate::domain::user::models::MeetInfo;
use crate::infra::UserKeyProviderAdapter;

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct GroupKeyInfo {
    pub key: String,
    pub epoch: u64,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct GroupDisplayCode {
    pub full_code: String,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct ParticipantTrackSettingsInfo {
    pub audio: u8,
    pub video: u8,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct UserSettingsInfo {
    pub address_id: Option<String>,
    pub waiting_room: bool,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
#[derive(Clone)]
pub struct MeetingInfo {
    pub id: String,
    pub address_id: Option<String>,
    pub meeting_link_name: String,
    pub meeting_name: String,
    pub password: Option<String>,
    pub salt: String,
    pub session_key: String,
    pub srp_modulus_id: String,
    pub srp_salt: String,
    pub r_rule: Option<String>,
    pub time_zone: Option<String>,
    pub custom_password: u8,
    pub meeting_type: u8,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct MeetingInfoWithPassword {
    pub meeting: MeetingInfo,
    pub password: String,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ConnectionStateInfo {
    Disconnected,
    Connecting,
    Connected,
    Reconnecting,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum JoinTypeInfo {
    ExternalCommit = 0,
    ExternalProposal = 1,
}

impl From<JoinType> for JoinTypeInfo {
    fn from(join_type: JoinType) -> Self {
        match join_type {
            JoinType::ExternalCommit => JoinTypeInfo::ExternalCommit,
            JoinType::ExternalProposal => JoinTypeInfo::ExternalProposal,
        }
    }
}

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum JoinRequestChangeInfo {
    Added = 0,
    Removed = 1,
}

#[cfg(target_family = "wasm")]
impl From<JoinRequestChange> for JoinRequestChangeInfo {
    fn from(change: JoinRequestChange) -> Self {
        match change {
            JoinRequestChange::Added => JoinRequestChangeInfo::Added,
            JoinRequestChange::Removed => JoinRequestChangeInfo::Removed,
        }
    }
}

#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct SubmitJoinRequestResponseInfo {
    pub request_id: String,
}

#[cfg(target_family = "wasm")]
impl From<SubmitJoinRequestResponse> for SubmitJoinRequestResponseInfo {
    fn from(response: SubmitJoinRequestResponse) -> Self {
        Self {
            request_id: response.request_id,
        }
    }
}

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MlsSyncStateInfo {
    Success = 0,
    Checking = 1,
    Retrying = 2,
    Failed = 3,
}

#[cfg(target_family = "wasm")]
impl From<crate::service::service_state::MlsSyncState> for MlsSyncStateInfo {
    fn from(state: crate::service::service_state::MlsSyncState) -> Self {
        match state {
            crate::service::service_state::MlsSyncState::Success => MlsSyncStateInfo::Success,
            crate::service::service_state::MlsSyncState::Checking => MlsSyncStateInfo::Checking,
            crate::service::service_state::MlsSyncState::Retrying => MlsSyncStateInfo::Retrying,
            crate::service::service_state::MlsSyncState::Failed => MlsSyncStateInfo::Failed,
        }
    }
}

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RejoinReasonInfo {
    EpochMismatch = 0,
    WebsocketDisconnected = 1,
    MemberNotFoundInMLS = 2,
    FetchTimeout = 3,
    LivekitStateMismatch = 4,
    LivekitConnectionTimeout = 5,
    Other = 6,
}

#[cfg(target_family = "wasm")]
impl From<RejoinReason> for RejoinReasonInfo {
    fn from(reason: RejoinReason) -> Self {
        match reason {
            RejoinReason::EpochMismatch => RejoinReasonInfo::EpochMismatch,
            RejoinReason::WebsocketDisconnected => RejoinReasonInfo::WebsocketDisconnected,
            RejoinReason::MemberNotFoundInMLS => RejoinReasonInfo::MemberNotFoundInMLS,
            RejoinReason::FetchTimeout => RejoinReasonInfo::FetchTimeout,
            RejoinReason::LivekitStateMismatch => RejoinReasonInfo::LivekitStateMismatch,
            RejoinReason::LivekitConnectionTimeout => RejoinReasonInfo::LivekitConnectionTimeout,
            RejoinReason::Other => RejoinReasonInfo::Other,
        }
    }
}

#[cfg(target_family = "wasm")]
impl From<RejoinReasonInfo> for RejoinReason {
    fn from(reason: RejoinReasonInfo) -> Self {
        match reason {
            RejoinReasonInfo::EpochMismatch => RejoinReason::EpochMismatch,
            RejoinReasonInfo::WebsocketDisconnected => RejoinReason::WebsocketDisconnected,
            RejoinReasonInfo::MemberNotFoundInMLS => RejoinReason::MemberNotFoundInMLS,
            RejoinReasonInfo::FetchTimeout => RejoinReason::FetchTimeout,
            RejoinReasonInfo::LivekitStateMismatch => RejoinReason::LivekitStateMismatch,
            RejoinReasonInfo::LivekitConnectionTimeout => RejoinReason::LivekitConnectionTimeout,
            RejoinReasonInfo::Other => RejoinReason::Other,
        }
    }
}

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[repr(u8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GroupKeyUpdateReasonInfo {
    Join = 0,
    Leave = 1,
    Mixed = 2,
    Unknown = 3,
}

#[cfg(target_family = "wasm")]
impl From<crate::service::user_service::GroupKeyUpdateReason> for GroupKeyUpdateReasonInfo {
    fn from(reason: crate::service::user_service::GroupKeyUpdateReason) -> Self {
        use crate::service::user_service::GroupKeyUpdateReason;
        match reason {
            GroupKeyUpdateReason::Join => GroupKeyUpdateReasonInfo::Join,
            GroupKeyUpdateReason::Leave => GroupKeyUpdateReasonInfo::Leave,
            GroupKeyUpdateReason::Mixed => GroupKeyUpdateReasonInfo::Mixed,
            GroupKeyUpdateReason::Unknown => GroupKeyUpdateReasonInfo::Unknown,
        }
    }
}

#[cfg(target_family = "wasm")]
impl From<ConnectionState> for ConnectionStateInfo {
    fn from(state: ConnectionState) -> Self {
        match state {
            ConnectionState::Disconnected => ConnectionStateInfo::Disconnected,
            ConnectionState::Connecting => ConnectionStateInfo::Connecting,
            ConnectionState::Connected => ConnectionStateInfo::Connected,
            ConnectionState::Reconnecting => ConnectionStateInfo::Reconnecting,
        }
    }
}

#[cfg(target_family = "wasm")]
impl App {
    pub(crate) fn init_logging() {
        let _ = tracing_subscriber::fmt()
            .with_max_level(tracing::Level::DEBUG)
            .with_ansi(false)
            .with_timer(tracing_subscriber::fmt::time::ChronoLocal::new(
                "%H:%M:%S%.3f".to_string(),
            ))
            .with_writer(tracing_web::MakeWebConsoleWriter::new().with_pretty_level())
            .with_level(false) // Level is part of the "pretty level" in the console writer
            .try_init();
        console_error_panic_hook::set_once();
    }
}

#[cfg(target_family = "wasm")]
#[wasm_bindgen]
impl App {
    #[wasm_bindgen(constructor)]
    pub async fn new_wasm(
        env: String,
        app_version: String,
        user_agent: String,
        db_path: String,
        http_host: String,
        ws_host: String,
        user_id_str: String,
        uid_str: String,
    ) -> Result<Self, JsValue> {
        use crate::infra::UserKeyProviderAdapter;
        let auth = Auth::external(user_id_str, uid_str);
        let config = ApiConfig {
            spec: (app_version, user_agent),
            auth: Some(auth),
            url_prefix: None,
            env: Some(env),
            proxy: None,
        };
        let user_key_provider = Arc::new(UserKeyProviderAdapter::new());
        Self::from_config(config, db_path, http_host, ws_host, user_key_provider)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = joinMeetingWithAccessToken)]
    pub async fn join_meeting_with_access_token_wasm(
        &self,
        access_token: String,
        meet_link_name: String,
        meeting_password: String,
        session_id: Option<String>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.join_meeting_with_access_token(
            access_token,
            meet_link_name,
            meeting_password,
            session_id,
        )
        .await
        .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = joinMeetingWithAccessTokenWithSwitchJoinType)]
    pub async fn join_meeting_with_access_token_with_switch_join_type_wasm(
        &self,
        access_token: String,
        meet_link_name: String,
        meeting_password: String,
        session_id: Option<String>,
        switch_join_type: bool,
        is_waiting_room: bool,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.join_meeting(
            AccessToken::new(access_token),
            MeetingLinkName::new(meet_link_name),
            MeetingPassword::new(meeting_password),
            session_id,
            switch_join_type,
            is_waiting_room,
        )
        .await
        .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = joinRoomWithProposal)]
    pub async fn join_meeting_with_access_token_with_proposal_wasm(
        &self,
        access_token: String,
        meet_link_name: String,
        meeting_password: String,
        session_id: Option<String>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.join_meeting_with_access_token_with_proposal(
            access_token,
            meet_link_name,
            meeting_password,
            session_id,
        )
        .await
        .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = updateLivekitAccessToken)]
    pub async fn update_livekit_access_token_wasm(
        &self,
        access_token: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.update_livekit_access_token(access_token)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = getWsState)]
    pub async fn get_ws_state_wasm(
        &self,
    ) -> Result<ConnectionStateInfo, crate::errors::core::MeetCoreErrorEnum> {
        let ws_state = self
            .get_ws_state()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))?;
        Ok(ConnectionStateInfo::from(ws_state))
    }

    #[wasm_bindgen(js_name = setWorkerCookieBridgeEnabled)]
    pub fn set_worker_cookie_bridge_enabled_wasm(&self, enabled: bool) {
        self.ws_client.set_worker_cookie_bridge_enabled(enabled);
    }

    #[wasm_bindgen(js_name = setUseCachedServerTime)]
    pub fn set_use_cached_server_time_wasm(&self, enabled: bool) {
        self.set_use_cached_server_time(enabled);
    }

    #[wasm_bindgen(js_name = setWebsocketPingInterval)]
    pub async fn set_websocket_ping_interval_wasm(
        &self,
        seconds: Option<u64>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.set_websocket_ping_interval(seconds)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = setWebsocketMaxPingFailures)]
    pub async fn set_websocket_max_ping_failures_wasm(
        &self,
        failures: Option<u32>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.set_websocket_max_ping_failures(failures)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = setWebsocketPongTimeout)]
    pub async fn set_websocket_pong_timeout_wasm(
        &self,
        seconds: Option<u64>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.set_websocket_pong_timeout(seconds)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = setLivekitActiveUuids)]
    pub async fn set_livekit_active_uuids_wasm(
        &self,
        livekit_active_uuid_list: Vec<String>,
        is_agent_in_livekit: bool,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.set_livekit_active_uuids(livekit_active_uuid_list, is_agent_in_livekit)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = isMlsUpToDate)]
    pub async fn is_mls_up_to_date_wasm(&self) -> Result<bool, JsValue> {
        let is_up_to_date = self.is_mls_up_to_date().await?;
        Ok(is_up_to_date)
    }

    #[wasm_bindgen(js_name = isWebsocketHasReconnected)]
    pub async fn is_websocket_has_reconnected_wasm(&self) -> Result<bool, JsValue> {
        let has_reconnected = self.is_websocket_has_reconnected().await?;
        Ok(has_reconnected)
    }

    #[wasm_bindgen(js_name = getGroupKey)]
    pub async fn get_group_key_wasm(
        &self,
    ) -> Result<GroupKeyInfo, crate::errors::core::MeetCoreErrorEnum> {
        let (key, epoch) = self
            .get_group_key()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))?;
        Ok(GroupKeyInfo { key, epoch })
    }

    #[wasm_bindgen(js_name = getGroupLen)]
    pub async fn get_group_len_wasm(&self) -> Result<u32, crate::errors::core::MeetCoreErrorEnum> {
        self.get_group_len()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))
    }

    #[wasm_bindgen(js_name = getGroupDisplayCode)]
    pub async fn get_group_display_code_wasm(
        &self,
    ) -> Result<GroupDisplayCode, crate::errors::core::MeetCoreErrorEnum> {
        let full_code = self.get_group_display_code().await?;
        Ok(GroupDisplayCode { full_code })
    }

    #[wasm_bindgen(js_name = leaveMeeting)]
    pub async fn leave_meeting_wasm(&self) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.leave_meeting().await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = updateParticipantTrackSettings)]
    pub async fn update_participant_track_settings_wasm(
        &self,
        participant_uuid: String,
        audio: Option<u8>,
        video: Option<u8>,
    ) -> Result<ParticipantTrackSettingsInfo, JsValue> {
        let participant_track_settings = self
            .update_participant_track_settings(participant_uuid, audio, video)
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))?;
        Ok(ParticipantTrackSettingsInfo {
            audio: participant_track_settings.audio,
            video: participant_track_settings.video,
        })
    }

    #[wasm_bindgen(js_name = getActiveMeetings)]
    pub async fn get_active_meetings_wasm(&self) -> Result<Vec<MeetingInfo>, JsValue> {
        let active_meetings = self
            .get_active_meetings()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))?;
        Ok(active_meetings
            .into_iter()
            .map(|m| MeetingInfo {
                id: m.id,
                address_id: m.address_id.clone(),
                meeting_link_name: m.meeting_link_name,
                meeting_name: m.meeting_name,
                password: m.password,
                salt: m.salt,
                session_key: m.session_key,
                srp_modulus_id: m.srp_modulus_id,
                srp_salt: m.srp_salt,
                r_rule: m.r_rule,
                time_zone: m.time_zone,
                custom_password: m.custom_password as u8,
                meeting_type: m.meeting_type as u8,
            })
            .collect::<Vec<_>>())
    }

    #[wasm_bindgen(js_name = getUserSettings)]
    pub async fn get_user_settings_wasm(&self) -> Result<UserSettingsInfo, JsValue> {
        let user_settings = self
            .get_user_settings()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))?;
        Ok(UserSettingsInfo {
            address_id: user_settings.address_id,
            waiting_room: user_settings.waiting_room,
        })
    }

    #[wasm_bindgen(js_name = updateUserSettingsWaitingRoom)]
    pub async fn update_user_settings_waiting_room_wasm(
        &self,
        enable: bool,
    ) -> Result<UserSettingsInfo, JsValue> {
        let user_settings = self
            .update_user_settings_waiting_room(enable)
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))?;
        Ok(UserSettingsInfo {
            address_id: user_settings.address_id,
            waiting_room: user_settings.waiting_room,
        })
    }

    #[wasm_bindgen(js_name = removeParticipant)]
    pub async fn remove_participant_wasm(
        &self,
        participant_uuid: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.remove_participant(participant_uuid)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = encryptMessage)]
    pub async fn encrypt_message_wasm(
        &self,
        message: String,
    ) -> Result<Vec<u8>, crate::errors::core::MeetCoreErrorEnum> {
        self.encrypt_message(&message).await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = getJoinType)]
    pub fn get_join_type_wasm(
        &self,
        is_new_join_type: bool,
        enable_join_type_switch: bool,
        current_participant_count: u32,
    ) -> JoinTypeInfo {
        let join_type = self.get_join_type(
            is_new_join_type,
            enable_join_type_switch,
            current_participant_count,
        );
        join_type.into()
    }

    #[wasm_bindgen(js_name = endMeeting)]
    pub async fn end_meeting_wasm(&self) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.end_meeting().await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = decryptMessage)]
    pub async fn decrypt_message_wasm(
        &self,
        data: Vec<u8>,
    ) -> Result<DecryptedMessageInfo, JsValue> {
        self.decrypt_message(data).await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = composeChatMessage)]
    pub async fn compose_chat_message_wasm(
        &self,
        text: String,
        reply_to_id: Option<String>,
        reply_topic_id: Option<String>,
    ) -> Result<ChatComposeResult, crate::errors::core::MeetCoreErrorEnum> {
        let reply_to = match reply_to_id {
            None => None,
            Some(id) => Some(ReplyTarget {
                message_id: MessageId::from_hex(&id).map_err(MeetCoreError::from)?,
                topic_id: reply_topic_id
                    .map(|t| MessageId::from_hex(&t).map_err(MeetCoreError::from))
                    .transpose()?,
            }),
        };
        self.compose_chat(ChatComposeRequest::Message { text, reply_to })
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = composeChatReaction)]
    pub async fn compose_chat_reaction_wasm(
        &self,
        target_id: String,
        emoji: String,
    ) -> Result<ChatComposeResult, crate::errors::core::MeetCoreErrorEnum> {
        let target = MessageId::from_hex(&target_id).map_err(MeetCoreError::from)?;
        self.compose_chat(ChatComposeRequest::React { target, emoji })
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = composeChatUnreact)]
    pub async fn compose_chat_unreact_wasm(
        &self,
        target_id: String,
        replaces_id: String,
    ) -> Result<ChatComposeResult, crate::errors::core::MeetCoreErrorEnum> {
        let target = MessageId::from_hex(&target_id).map_err(MeetCoreError::from)?;
        let replaces = MessageId::from_hex(&replaces_id).map_err(MeetCoreError::from)?;
        self.compose_chat(ChatComposeRequest::Unreact { target, replaces })
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    #[wasm_bindgen(js_name = decodeChat)]
    pub async fn decode_chat_wasm(
        &self,
        data: Vec<u8>,
    ) -> Result<ChatIncomingEventInfo, crate::errors::core::MeetCoreErrorEnum> {
        self.decode_chat(data)
            .await
            .map(Into::into)
            .map_err(Into::into)
    }

    #[cfg(all(target_family = "wasm", not(test)))]
    #[wasm_bindgen(js_name = setMlsGroupUpdateHandler)]
    pub async fn set_mls_group_update_handler_wasm(&self) -> Result<(), JsValue> {
        self.services
            .user_service
            .write()
            .await
            .handlers
            .set_mls_group_update_handler(|meeting_link_name, reason| {
                Box::pin(async move {
                    let reason_info: GroupKeyUpdateReasonInfo = reason.into();
                    new_group_key_for(meeting_link_name, reason_info);
                })
            });
        Ok(())
    }

    #[cfg(all(target_family = "wasm", not(test)))]
    #[wasm_bindgen(js_name = setMlsSyncStateUpdateHandler)]
    pub async fn set_mls_sync_state_update_handler_wasm(&self) -> Result<(), JsValue> {
        self.services
            .user_service
            .write()
            .await
            .handlers
            .set_mls_sync_state_update_handler(|state, reason| {
                Box::pin(async move {
                    let state_info: MlsSyncStateInfo = state.into();
                    let reason_info = reason.map(|r| r.into());
                    on_mls_sync_state_changed(state_info, reason_info);
                })
            });
        Ok(())
    }

    #[cfg(all(target_family = "wasm", not(test)))]
    #[wasm_bindgen(js_name = setLiveKitAdminChangeHandler)]
    pub async fn set_livekit_admin_change_handler_wasm(&self) -> Result<(), JsValue> {
        self.services
            .user_service
            .write()
            .await
            .handlers
            .set_livekit_admin_change_handler(|room_id, participant_uid, participant_type| {
                Box::pin(async move {
                    on_livekit_admin_changed(
                        room_id.clone(),
                        participant_uid.clone(),
                        participant_type,
                    );
                })
            });
        Ok(())
    }

    #[wasm_bindgen(js_name = setDisconnectionHandler)]
    pub async fn set_disconnection_handler_wasm(&self) -> Result<(), JsValue> {
        self.ws_client
            .set_disconnection_handler(Arc::new(move |_| {
                wasm_bindgen_futures::spawn_local(async move {
                    disconnection_handler();
                });
            }))
            .await;
        Ok(())
    }

    #[wasm_bindgen(js_name = triggerWebSocketReconnect)]
    pub async fn trigger_websocket_reconnect_wasm(
        &self,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.trigger_websocket_reconnect()
            .await
            .map_err(|e| crate::errors::core::MeetCoreErrorEnum::from(e))
    }

    #[wasm_bindgen(js_name = logJoinedRoom)]
    pub async fn log_joined_room_wasm(
        &self,
        is_vp9_decode_supported: Option<bool>,
        is_vp9_encode_supported: Option<bool>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.log_joined_room(is_vp9_decode_supported, is_vp9_encode_supported)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = logJoinedRoomFailed)]
    pub async fn log_joined_room_failed_wasm(
        &self,
        error_code: Option<String>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.log_joined_room_failed(error_code)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = logConnectionLost)]
    pub async fn log_connection_lost_wasm(
        &self,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.log_connection_lost().await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = logUserEpochHealth)]
    pub async fn log_user_epoch_health_wasm(
        &self,
        current_epoch: u32,
        epoch_display_code: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.log_user_epoch_health(current_epoch, epoch_display_code)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = logUserRejoin)]
    pub async fn log_user_rejoin_wasm(
        &self,
        rejoin_time_ms: u64,
        incremental_count: u32,
        reason: RejoinReasonInfo,
        success: bool,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        let rejoin_reason: RejoinReason = reason.into();
        self.log_user_rejoin(rejoin_time_ms, incremental_count, rejoin_reason, success)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = tryLogDesignatedCommitter)]
    pub async fn try_log_designated_committer_wasm(
        &self,
        epoch: u32,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.try_log_designated_committer(epoch)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = ping)]
    pub async fn ping_wasm(&self) -> Result<u64, crate::errors::core::MeetCoreErrorEnum> {
        self.ping().await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = testWasm)]
    pub async fn test_wasm(&self) -> crate::errors::core::Result<()> {
        Err(crate::errors::core::MeetCoreError::PasswordTooShort)
    }

    #[wasm_bindgen(js_name = logStartToJoinRoom)]
    pub async fn log_start_to_join_room_wasm(
        &self,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.log_start_to_join_room().await.map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = authenticateMeetingLink)]
    pub async fn authenticate_meeting_link_wasm(
        &self,
        meet_link_name: String,
        meet_link_password: String,
        display_name: String,
    ) -> Result<MeetInfo, crate::errors::core::MeetCoreErrorEnum> {
        self.authenticate_meeting_link(meet_link_name, meet_link_password, display_name)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = prepareMlsSessionForWaitingRoom)]
    pub async fn prepare_mls_session_for_waiting_room_wasm(
        &self,
        access_token: String,
        meet_link_name: String,
        meet_link_password: String,
        session_id: Option<String>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.prepare_mls_session_for_waiting_room_with_access_token(
            access_token,
            meet_link_name,
            meet_link_password,
            session_id,
        )
        .await
        .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = hasMlsGroupInfo)]
    pub async fn has_mls_group_info_wasm(
        &self,
        access_token: Option<String>,
        meet_link_name: Option<String>,
        meet_link_password: Option<String>,
        session_id: Option<String>,
    ) -> Result<bool, crate::errors::core::MeetCoreErrorEnum> {
        self.ensure_mls_session_for_group_info(
            access_token,
            meet_link_name,
            meet_link_password,
            session_id.as_deref(),
        )
        .await?;
        self.has_mls_group_info_after_session()
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = refreshWaitingRoomGuestSessionForJoinRequest)]
    pub async fn refresh_waiting_room_guest_session_for_join_request_wasm(
        &self,
        access_token: String,
        meet_link_name: String,
        meet_link_password: String,
        session_id: Option<String>,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.refresh_waiting_room_guest_session_for_join_request_with_access_token(
            access_token,
            meet_link_name,
            meet_link_password,
            session_id,
        )
        .await
        .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = createJoinRequest)]
    pub async fn create_join_request_wasm(
        &self,
        meet_link_name: String,
        meeting_session_key: String,
    ) -> Result<SubmitJoinRequestResponseInfo, crate::errors::core::MeetCoreErrorEnum> {
        self.create_join_request(meet_link_name, MeetingSessionKey::from(meeting_session_key))
            .await
            .map(|response| response.into())
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = waitForWaitingRoomWelcome)]
    pub async fn wait_for_waiting_room_welcome_wasm(
        &self,
        meet_link_name: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.wait_for_waiting_room_welcome(meet_link_name)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = clearWaitingRoomJoinRequest)]
    pub async fn clear_waiting_room_join_request_wasm(&self) {
        self.clear_waiting_room_join_request().await;
    }

    #[wasm_bindgen(js_name = cancelWaitingRoomJoinRequest)]
    pub async fn cancel_waiting_room_join_request_wasm(
        &self,
        meet_link_name: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.cancel_waiting_room_join_request(meet_link_name)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = rejectWaitingRoomJoinRequest)]
    pub async fn reject_waiting_room_join_request_wasm(
        &self,
        meet_link_name: String,
        request_id: String,
        participant_uid: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.reject_waiting_room_join_request(meet_link_name, request_id, participant_uid)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = admitWaitingRoomJoinRequest)]
    pub async fn admit_waiting_room_join_request_wasm(
        &self,
        meet_link_name: String,
        request_id: String,
        session_key_base64: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        let session_key = meeting_session_key_from_base64(&session_key_base64)?;
        self.admit_waiting_room_join_requests_internal(
            meet_link_name,
            Some(vec![request_id]),
            Some(session_key),
        )
        .await
        .map(|_| ())
        .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = admitAllWaitingRoomJoinRequests)]
    pub async fn admit_all_waiting_room_join_requests_wasm(
        &self,
        meet_link_name: String,
        session_key_base64: String,
    ) -> Result<Vec<String>, crate::errors::core::MeetCoreErrorEnum> {
        let session_key = meeting_session_key_from_base64(&session_key_base64)?;
        self.admit_all_waiting_room_join_requests(meet_link_name, Some(session_key))
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = updateWaitingRoomSetting)]
    pub async fn update_waiting_room_setting_wasm(
        &self,
        meet_link_name: String,
        enable: bool,
        session_key_base64: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        let session_key = meeting_session_key_from_base64(&session_key_base64)?;
        self.update_waiting_room_setting(meet_link_name, enable, Some(session_key))
            .await
            .map_err(Into::into)
    }

    #[cfg(all(target_family = "wasm", not(test)))]
    #[wasm_bindgen(js_name = setJoinDecisionHandler)]
    pub async fn set_join_decision_handler_wasm(&self) -> Result<(), JsValue> {
        self.set_join_decision_handler(|request_id, admitted| {
            Box::pin(async move {
                on_join_decision(request_id, admitted);
            })
        })
        .await;
        Ok(())
    }

    #[wasm_bindgen(js_name = clearJoinDecisionHandler)]
    pub async fn clear_join_decision_handler_wasm(&self) {
        self.clear_join_decision_handler().await;
    }

    #[cfg(all(target_family = "wasm", not(test)))]
    #[wasm_bindgen(js_name = setJoinRequestHandler)]
    pub async fn set_join_request_handler_wasm(&self) -> Result<(), JsValue> {
        self.set_join_request_handler(|change, request_id, participant_uid, expires_at| {
            Box::pin(async move {
                on_join_request(change.into(), request_id, participant_uid, expires_at);
            })
        })
        .await;
        Ok(())
    }

    #[wasm_bindgen(js_name = clearJoinRequestHandler)]
    pub async fn clear_join_request_handler_wasm(&self) {
        self.clear_join_request_handler().await;
    }

    #[cfg(all(target_family = "wasm", not(test)))]
    #[wasm_bindgen(js_name = setAgentPendingHandler)]
    pub async fn set_agent_pending_handler_wasm(&self) -> Result<(), JsValue> {
        self.services
            .user_service
            .write()
            .await
            .handlers
            .set_agent_pending_handler(|device_id| {
                Box::pin(async move {
                    on_agent_pending(device_id);
                })
            });
        Ok(())
    }

    #[cfg(all(target_family = "wasm", not(test)))]
    #[wasm_bindgen(js_name = setAgentLeftHandler)]
    pub async fn set_agent_left_handler_wasm(&self) -> Result<(), JsValue> {
        self.services
            .user_service
            .write()
            .await
            .handlers
            .set_agent_left_handler(|device_id| {
                Box::pin(async move {
                    on_agent_left(device_id);
                })
            });
        Ok(())
    }

    #[wasm_bindgen(js_name = admitAgent)]
    pub async fn admit_agent_wasm(
        &self,
        meeting_link_name: String,
        agent_device_id: String,
        meeting_password: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.admit_agent(meeting_link_name, agent_device_id, meeting_password)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = removeAgent)]
    pub async fn remove_agent_wasm(
        &self,
        meeting_link_name: String,
        agent_device_id: String,
    ) -> Result<(), crate::errors::core::MeetCoreErrorEnum> {
        self.remove_agent(meeting_link_name, agent_device_id)
            .await
            .map_err(|e| e.into())
    }

    #[wasm_bindgen(js_name = requestClosedCaptions)]
    pub async fn request_closed_captions_wasm(
        &self,
        meeting_link_name: String,
    ) -> Result<(), wasm_bindgen::JsValue> {
        self.request_closed_captions(meeting_link_name)
            .await
            .map_err(MeetCoreError::into_js_error)
    }

    #[wasm_bindgen(js_name = stopClosedCaptions)]
    pub async fn stop_closed_captions_wasm(
        &self,
        meeting_link_name: String,
    ) -> Result<(), wasm_bindgen::JsValue> {
        self.stop_closed_captions(meeting_link_name)
            .await
            .map_err(MeetCoreError::into_js_error)
    }

    #[wasm_bindgen(js_name = setClosedCaptionsAvailabilityAsHost)]
    pub async fn set_closed_captions_availability_as_host_wasm(
        &self,
        meeting_link_name: String,
        available: bool,
    ) -> Result<(), wasm_bindgen::JsValue> {
        self.set_closed_captions_availability_as_host(meeting_link_name, available)
            .await
            .map_err(MeetCoreError::into_js_error)
    }

    #[wasm_bindgen(js_name = listPendingAgents)]
    pub async fn list_pending_agents_wasm(
        &self,
        meeting_link_name: String,
    ) -> Result<Vec<String>, crate::errors::core::MeetCoreErrorEnum> {
        self.list_pending_agents(meeting_link_name)
            .await
            .map_err(|e| e.into())
    }
}

#[cfg(target_family = "wasm")]
fn meeting_session_key_from_base64(
    session_key_base64: &str,
) -> Result<MeetingSessionKey, MeetCoreError> {
    let trimmed = session_key_base64.trim();
    if trimmed.is_empty() {
        return Err(MeetCoreError::InvalidInput {
            field: "session_key_base64".to_string(),
            reason: "Session key is empty".to_string(),
        });
    }

    Ok(MeetingSessionKey::from(trimmed.to_string()))
}

#[cfg(all(target_family = "wasm", not(test)))]
#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = newGroupKeyEvent)]
    pub fn new_group_key_for(meeting_link_name: String, reason: GroupKeyUpdateReasonInfo);

    #[wasm_bindgen(js_namespace = livekitAdminChangeEvent)]
    pub fn on_livekit_admin_changed(
        room_id: String,
        participant_uid: String,
        participant_type: u32,
    );

    #[wasm_bindgen(js_namespace = disconnectionEvent)]
    pub fn disconnection_handler();

    #[wasm_bindgen(js_namespace = mlsSyncStateChangeEvent)]
    pub fn on_mls_sync_state_changed(state: MlsSyncStateInfo, reason: Option<RejoinReasonInfo>);

    #[wasm_bindgen(js_namespace = joinDecisionEvent)]
    pub fn on_join_decision(request_id: String, admitted: bool);

    #[wasm_bindgen(js_namespace = joinRequestEvent)]
    pub fn on_join_request(
        change: JoinRequestChangeInfo,
        request_id: String,
        participant_uid: String,
        expires_at: u64,
    );

    #[wasm_bindgen(js_namespace = agentPendingEvent)]
    pub fn on_agent_pending(device_id: String);

    #[wasm_bindgen(js_namespace = agentLeftEvent)]
    pub fn on_agent_left(device_id: String);
}

// Provide a stub for tests
#[cfg(all(target_family = "wasm", test))]
pub fn disconnection_handler() {
    // Stub implementation for tests
    log::debug!("disconnection_handler called in test");
}

#[cfg(all(target_family = "wasm", test))]
pub fn on_join_decision(_request_id: String, _admitted: bool) {}

#[cfg(all(target_family = "wasm", test))]
pub fn on_join_request(
    _change: JoinRequestChangeInfo,
    _request_id: String,
    _participant_uid: String,
    _expires_at: u64,
) {
}
