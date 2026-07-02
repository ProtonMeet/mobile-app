use std::fmt;

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub struct MessageId([u8; 32]);

impl MessageId {
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Self(bytes)
    }

    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }

    pub fn to_hex(&self) -> String {
        self.0.iter().map(|b| format!("{b:02x}")).collect()
    }

    pub fn from_hex(s: &str) -> Result<Self, crate::error::ChatError> {
        if s.len() != 64 || !s.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(crate::error::ChatError::InvalidMessageId(s.to_string()));
        }
        let mut out = [0u8; 32];
        for (i, chunk) in s.as_bytes().chunks(2).enumerate() {
            out[i] = u8::from_str_radix(std::str::from_utf8(chunk)?, 16)
                .map_err(|_| crate::error::ChatError::InvalidMessageId(s.to_string()))?;
        }
        Ok(Self(out))
    }
}

impl fmt::Debug for MessageId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "MessageId({})", self.to_hex())
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ParticipantId(pub String);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ChatProtocol {
    Legacy,
    MimiV1,
}

#[derive(Clone, Debug)]
pub struct ReplyTarget {
    pub message_id: MessageId,
    pub topic_id: Option<MessageId>,
}

#[derive(Clone, Debug)]
pub enum ChatComposeRequest {
    Message {
        text: String,
        reply_to: Option<ReplyTarget>,
    },
    React {
        target: MessageId,
        emoji: String,
    },
    Unreact {
        target: MessageId,
        replaces: MessageId,
    },
}

#[derive(Clone, Debug)]
pub enum ChatIncomingEvent {
    Message {
        id: MessageId,
        sender: ParticipantId,
        received_at_ms: u64,
        text: String,
        in_reply_to: Option<MessageId>,
        topic_id: Option<MessageId>,
        protocol: ChatProtocol,
        legacy_m_type: Option<String>, // Only used for legacy messages
    },
    Reaction {
        id: MessageId,
        sender: ParticipantId,
        received_at_ms: u64,
        target: MessageId,
        emoji: Option<String>,
        replaces: Option<MessageId>,
        protocol: ChatProtocol,
    },
    Unsupported {
        id: MessageId,
        sender: ParticipantId,
        received_at_ms: u64,
        protocol: ChatProtocol,
    },
}

#[derive(Clone, Debug)]
pub struct ChatOutgoingPacket {
    pub payload: Vec<u8>,
    pub local_echo: ChatIncomingEvent,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn message_id_hex_roundtrip() {
        let bytes = [0xab; 32];
        let id = MessageId::from_bytes(bytes);
        let hex = id.to_hex();
        assert_eq!(hex.len(), 64);
        assert_eq!(MessageId::from_hex(&hex).unwrap(), id);
    }

    #[test]
    fn message_id_from_hex_rejects_invalid() {
        assert!(MessageId::from_hex("not-hex").is_err());
        assert!(MessageId::from_hex("ab").is_err());
        assert!(MessageId::from_hex(&"g".repeat(64)).is_err());
    }
}
