use flutter_rust_bridge::frb;
use proton_meet_chat::{ChatIncomingEvent, ChatOutgoingPacket, ChatProtocol};

/// Kind of a decoded / locally-echoed chat event (MimiV1 unified format).
#[frb]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrbChatEventKind {
    Message,
    Reaction,
    Unsupported,
}

/// Chat wire protocol the event was produced with.
#[frb]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FrbChatProtocol {
    Legacy,
    MimiV1,
}

impl From<ChatProtocol> for FrbChatProtocol {
    fn from(protocol: ChatProtocol) -> Self {
        match protocol {
            ChatProtocol::Legacy => FrbChatProtocol::Legacy,
            ChatProtocol::MimiV1 => FrbChatProtocol::MimiV1,
        }
    }
}

/// Flattened, Dart-friendly representation of a decoded chat event or the
/// optimistic local echo returned by `compose_chat_*`.
#[frb]
#[derive(Clone, Debug)]
pub struct FrbChatIncomingEvent {
    pub kind: FrbChatEventKind,
    pub id: String,
    pub sender_participant_id: String,
    pub received_at_ms: u64,
    pub text: Option<String>,
    pub in_reply_to_id: Option<String>,
    pub topic_id: Option<String>,
    pub target_id: Option<String>,
    pub emoji: Option<String>,
    pub replaces_id: Option<String>,
    pub protocol: FrbChatProtocol,
    pub legacy_m_type: Option<String>,
}

impl From<ChatIncomingEvent> for FrbChatIncomingEvent {
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
            } => FrbChatIncomingEvent {
                kind: FrbChatEventKind::Message,
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
            } => FrbChatIncomingEvent {
                kind: FrbChatEventKind::Reaction,
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
            } => FrbChatIncomingEvent {
                kind: FrbChatEventKind::Unsupported,
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

/// Result of composing an outgoing chat event: the encrypted wire `payload`
/// to publish over the data channel, plus the optimistic `local_echo`.
#[frb]
#[derive(Clone, Debug)]
pub struct FrbChatComposeResult {
    pub payload: Vec<u8>,
    pub local_echo: FrbChatIncomingEvent,
}

impl From<ChatOutgoingPacket> for FrbChatComposeResult {
    fn from(packet: ChatOutgoingPacket) -> Self {
        FrbChatComposeResult {
            payload: packet.payload,
            local_echo: packet.local_echo.into(),
        }
    }
}
