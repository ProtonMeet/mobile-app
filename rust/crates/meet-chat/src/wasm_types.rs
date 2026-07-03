use super::types::{ChatIncomingEvent, ChatOutgoingPacket, ChatProtocol};

#[cfg(target_family = "wasm")]
use wasm_bindgen::prelude::wasm_bindgen;

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChatEventKind {
    Message,
    Reaction,
    Unsupported,
}

#[cfg_attr(target_family = "wasm", wasm_bindgen)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChatProtocolInfo {
    Legacy,
    MimiV1,
}

impl From<ChatProtocol> for ChatProtocolInfo {
    fn from(protocol: ChatProtocol) -> Self {
        match protocol {
            ChatProtocol::Legacy => ChatProtocolInfo::Legacy,
            ChatProtocol::MimiV1 => ChatProtocolInfo::MimiV1,
        }
    }
}

#[derive(Clone, Debug)]
#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct ChatIncomingEventInfo {
    pub kind: ChatEventKind,
    pub id: String,
    pub sender_participant_id: String,
    pub received_at_ms: u64,
    pub text: Option<String>,
    pub in_reply_to_id: Option<String>,
    pub topic_id: Option<String>,
    pub target_id: Option<String>,
    pub emoji: Option<String>,
    pub replaces_id: Option<String>,
    pub protocol: ChatProtocolInfo,
    pub legacy_m_type: Option<String>,
}

impl From<ChatIncomingEvent> for ChatIncomingEventInfo {
    fn from(event: ChatIncomingEvent) -> Self {
        match event {
            ChatIncomingEvent::Message {
                id,
                sender,
                received_at_ms,
                text,
                in_reply_to,
                topic_id,
                protocol,
                legacy_m_type,
            } => ChatIncomingEventInfo {
                kind: ChatEventKind::Message,
                id: id.to_hex(),
                sender_participant_id: sender.0,
                received_at_ms,
                text: Some(text),
                in_reply_to_id: in_reply_to.map(|m| m.to_hex()),
                topic_id: topic_id.map(|m| m.to_hex()),
                target_id: None,
                emoji: None,
                replaces_id: None,
                protocol: protocol.into(),
                legacy_m_type,
            },
            ChatIncomingEvent::Reaction {
                id,
                sender,
                received_at_ms,
                target,
                emoji,
                replaces,
                protocol,
            } => ChatIncomingEventInfo {
                kind: ChatEventKind::Reaction,
                id: id.to_hex(),
                sender_participant_id: sender.0,
                received_at_ms,
                text: None,
                in_reply_to_id: None,
                topic_id: None,
                target_id: Some(target.to_hex()),
                emoji,
                replaces_id: replaces.map(|m| m.to_hex()),
                protocol: protocol.into(),
                legacy_m_type: None,
            },
            ChatIncomingEvent::Unsupported {
                id,
                sender,
                received_at_ms,
                protocol,
            } => ChatIncomingEventInfo {
                kind: ChatEventKind::Unsupported,
                id: id.to_hex(),
                sender_participant_id: sender.0,
                received_at_ms,
                text: None,
                in_reply_to_id: None,
                topic_id: None,
                target_id: None,
                emoji: None,
                replaces_id: None,
                protocol: protocol.into(),
                legacy_m_type: None,
            },
        }
    }
}

#[derive(Clone, Debug)]
#[cfg_attr(target_family = "wasm", wasm_bindgen(getter_with_clone))]
pub struct ChatComposeResult {
    pub payload: Vec<u8>,
    pub local_echo: ChatIncomingEventInfo,
}

impl From<ChatOutgoingPacket> for ChatComposeResult {
    fn from(packet: ChatOutgoingPacket) -> Self {
        ChatComposeResult {
            payload: packet.payload,
            local_echo: packet.local_echo.into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{MessageId, ParticipantId};

    #[test]
    fn message_event_converts_to_info() {
        let id = MessageId::from_bytes([0xab; 32]);
        let info = ChatIncomingEventInfo::from(ChatIncomingEvent::Message {
            id,
            sender: ParticipantId("sender-1".into()),
            received_at_ms: 1_700_000_000_000,
            text: "hello".into(),
            in_reply_to: None,
            topic_id: None,
            protocol: ChatProtocol::MimiV1,
            legacy_m_type: None,
        });
        assert_eq!(info.kind, ChatEventKind::Message);
        assert_eq!(info.id, id.to_hex());
        assert_eq!(info.text.as_deref(), Some("hello"));
        assert_eq!(info.protocol, ChatProtocolInfo::MimiV1);
    }

    #[test]
    fn outgoing_packet_converts_to_compose_result() {
        let id = MessageId::from_bytes([0xcd; 32]);
        let local_echo = ChatIncomingEvent::Reaction {
            id,
            sender: ParticipantId("me".into()),
            received_at_ms: 42,
            target: MessageId::from_bytes([0xef; 32]),
            emoji: Some("👍".into()),
            replaces: None,
            protocol: ChatProtocol::MimiV1,
        };
        let result = ChatComposeResult::from(ChatOutgoingPacket {
            payload: vec![1, 2, 3],
            local_echo,
        });
        assert_eq!(result.payload, vec![1, 2, 3]);
        assert_eq!(result.local_echo.kind, ChatEventKind::Reaction);
    }
}
