use super::App;
use crate::chat::{
    self, ChatComposeRequest, ChatIncomingEvent, ChatOutgoingPacket, LEGACY_MEET_MEDIA,
    MIMI_CONTENT_MEDIA, ParticipantId, compose_local_echo,
};
use crate::domain::user::models::UserId;
use crate::domain::user::ports::UserService;
use crate::errors::core::MeetCoreError;
use chrono::Utc;
use mimi_content::MimiContentSerialize;
use mls_rs_codec::MlsEncode;
use mls_types::{MediaType, MlsMessage};

impl App {
    fn now_ms() -> u64 {
        Utc::now().timestamp_millis().try_into().unwrap_or(0)
    }

    pub(crate) async fn active_meeting_link(&self) -> Result<String, MeetCoreError> {
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        let user_id = user_info.user_id();
        self.services
            .user_service
            .read()
            .await
            .get_meeting_id(&user_id)
            .await
            .map_err(Into::into)
    }

    pub(super) async fn active_user_id(&self) -> Result<UserId, MeetCoreError> {
        let app_state = self.state.read().await;
        let user_info = app_state
            .active_user_info
            .as_ref()
            .ok_or(MeetCoreError::ParticipantNotFound)?;
        Ok(user_info.user_id())
    }

    async fn local_sender_uri(&self, meeting_link_name: &str) -> Result<String, MeetCoreError> {
        self.services
            .user_service
            .read()
            .await
            .local_mimi_sender_uri(meeting_link_name)
            .await
            .map_err(|e| MeetCoreError::MlsProtocolError {
                message: e.to_string(),
            })
    }

    pub async fn compose_chat(
        &self,
        request: ChatComposeRequest,
    ) -> Result<ChatOutgoingPacket, MeetCoreError> {
        let meeting = self.active_meeting_link().await?;
        let sender_uri = self.local_sender_uri(&meeting).await?;
        let room_uri = chat::meet_room_uri(&meeting);
        let wire_ts = Self::now_ms();
        let (content, id) = chat::build_mimi_message(&request, &sender_uri, &room_uri, wire_ts)?;
        let cbor = content.to_cbor_bytes().map_err(|e| {
            MeetCoreError::ChatError(chat::ChatError::InvalidMimiContent(e.to_string()))
        })?;
        let media = MediaType {
            media_type: MIMI_CONTENT_MEDIA.into(),
            parameters: vec![],
        };
        let mls_msg = self
            .services
            .user_service
            .read()
            .await
            .encrypt_application_message_bytes(&meeting, media, &cbor)
            .await
            .map_err(|e| MeetCoreError::MlsProtocolError {
                message: e.to_string(),
            })?;
        let payload = mls_msg.mls_encode_to_vec()?;
        let local_participant = self.active_user_id().await?;
        let local_echo = compose_local_echo(
            &request,
            id,
            ParticipantId(local_participant.to_string()),
            wire_ts,
        );
        Ok(ChatOutgoingPacket {
            payload,
            local_echo,
        })
    }

    pub async fn decode_chat(&self, data: Vec<u8>) -> Result<ChatIncomingEvent, MeetCoreError> {
        let meeting = self.active_meeting_link().await?;
        let ciphertext = chat::extract_mls_ciphertext(&data)?;
        let mls_msg = MlsMessage::from_bytes(&ciphertext)?;
        let (content, media_type, sender_id, sender_mimi_uri) = self
            .services
            .user_service
            .read()
            .await
            .decrypt_application_message_bytes(&meeting, mls_msg)
            .await
            .map_err(|e| MeetCoreError::MlsProtocolError {
                message: e.to_string(),
            })?;
        let received_at = Self::now_ms();
        let sender = ParticipantId(sender_id.to_string());
        match media_type.media_type.as_str() {
            MIMI_CONTENT_MEDIA => {
                let mimi = chat::parse_mimi_content(&content)?;
                let id = chat::compute_message_id_from_content(&mimi, &sender_mimi_uri, &meeting)?;
                chat::decode_mimi_content(&mimi, id, sender, received_at).map_err(Into::into)
            }
            LEGACY_MEET_MEDIA | "text/plain" => {
                let text = String::from_utf8(content.to_vec()).map_err(|e| {
                    MeetCoreError::ChatError(chat::ChatError::InvalidMimiContent(e.to_string()))
                })?;
                Ok(chat::decode_legacy_plaintext(&text, sender, received_at))
            }
            other => Ok(ChatIncomingEvent::Unsupported {
                id: chat::legacy_message_id(&sender.0, other, received_at),
                sender,
                received_at_ms: received_at,
                protocol: chat::ChatProtocol::Legacy,
            }),
        }
    }
}
