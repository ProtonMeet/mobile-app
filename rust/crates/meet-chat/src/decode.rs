use crate::error::ChatError;
use crate::mimi::domain_id_from_mimi;
use crate::types::{ChatIncomingEvent, ChatProtocol, MessageId, ParticipantId};
use mimi_content::{
    BaseDispos, Bstr, Disposition as Disp, MimiContent, NestedPartContent, SinglePart,
};
use sha2::{Digest, Sha256};

pub fn legacy_message_id(sender: &str, text: &str, received_at_ms: u64) -> MessageId {
    let mut h = Sha256::new();
    h.update(sender.as_bytes());
    h.update(text.as_bytes());
    h.update(received_at_ms.to_le_bytes());
    MessageId::from_bytes(h.finalize().into())
}

pub fn decode_legacy_plaintext(
    text: &str,
    sender: ParticipantId,
    received_at_ms: u64,
) -> ChatIncomingEvent {
    ChatIncomingEvent::Message {
        id: legacy_message_id(&sender.0, text, received_at_ms),
        sender,
        received_at_ms,
        text: text.to_owned(),
        in_reply_to: None,
        topic_id: None,
        protocol: ChatProtocol::Legacy,
    }
}

fn optional_message_id_from_bstr(b: &Bstr) -> Option<MessageId> {
    if b.is_empty() {
        return None;
    }
    if b.len() != 32 {
        return None;
    }
    let mut bytes = [0u8; 32];
    bytes.copy_from_slice(b);
    Some(MessageId::from_bytes(bytes))
}

fn utf8_text(content: &[u8]) -> Result<String, ChatError> {
    String::from_utf8(content.to_vec()).map_err(|e| ChatError::InvalidMimiContent(e.to_string()))
}

fn unsupported_event(
    id: MessageId,
    sender: ParticipantId,
    received_at_ms: u64,
) -> ChatIncomingEvent {
    ChatIncomingEvent::Unsupported {
        id,
        sender,
        received_at_ms,
        protocol: ChatProtocol::MimiV1,
    }
}

fn decode_render_message(
    content: &MimiContent,
    single: &SinglePart,
    id: MessageId,
    sender: ParticipantId,
    received_at_ms: u64,
) -> Result<ChatIncomingEvent, ChatError> {
    if &*single.content_type != "text/markdown" {
        return Ok(unsupported_event(id, sender, received_at_ms));
    }
    Ok(ChatIncomingEvent::Message {
        id,
        sender,
        received_at_ms,
        text: utf8_text(&single.content)?,
        in_reply_to: content.in_reply_to.as_ref().map(domain_id_from_mimi),
        topic_id: content.topic_id().and_then(optional_message_id_from_bstr),
        protocol: ChatProtocol::MimiV1,
    })
}

fn decode_reaction_add(
    content: &MimiContent,
    single: &SinglePart,
    id: MessageId,
    sender: ParticipantId,
    received_at_ms: u64,
) -> Result<ChatIncomingEvent, ChatError> {
    if &*single.content_type != "text/plain" {
        return Ok(unsupported_event(id, sender, received_at_ms));
    }
    let Some(target) = content.in_reply_to.as_ref().map(domain_id_from_mimi) else {
        return Ok(unsupported_event(id, sender, received_at_ms));
    };
    Ok(ChatIncomingEvent::Reaction {
        id,
        sender,
        received_at_ms,
        target,
        emoji: Some(utf8_text(&single.content)?),
        replaces: None,
        protocol: ChatProtocol::MimiV1,
    })
}

fn decode_reaction_remove(
    content: &MimiContent,
    id: MessageId,
    sender: ParticipantId,
    received_at_ms: u64,
) -> Result<ChatIncomingEvent, ChatError> {
    let Some(target) = content.in_reply_to.as_ref().map(domain_id_from_mimi) else {
        return Ok(unsupported_event(id, sender, received_at_ms));
    };
    let Some(replaces) = content.replaces.as_ref().map(domain_id_from_mimi) else {
        return Ok(unsupported_event(id, sender, received_at_ms));
    };
    Ok(ChatIncomingEvent::Reaction {
        id,
        sender,
        received_at_ms,
        target,
        emoji: None,
        replaces: Some(replaces),
        protocol: ChatProtocol::MimiV1,
    })
}

pub fn decode_mimi_content(
    content: &MimiContent,
    id: MessageId,
    sender: ParticipantId,
    received_at_ms: u64,
) -> Result<ChatIncomingEvent, ChatError> {
    match &content.nested_part.disposition {
        Disp::Base(BaseDispos::Render) => match &content.nested_part.part_content {
            NestedPartContent::SinglePart(single) => {
                decode_render_message(content, single, id, sender, received_at_ms)
            }
            _ => Ok(unsupported_event(id, sender, received_at_ms)),
        },
        Disp::Base(BaseDispos::Reaction) => match &content.nested_part.part_content {
            NestedPartContent::SinglePart(single) => {
                decode_reaction_add(content, single, id, sender, received_at_ms)
            }
            NestedPartContent::NullPart => {
                decode_reaction_remove(content, id, sender, received_at_ms)
            }
            _ => Ok(unsupported_event(id, sender, received_at_ms)),
        },
        _ => Ok(unsupported_event(id, sender, received_at_ms)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mimi::{build_mimi_message, meet_room_uri, parse_mimi_content};
    use crate::types::ChatComposeRequest;
    use mimi_content::MimiContentSerialize;

    const TARGET_HEX: &str = "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20";

    #[test]
    fn decode_text_message_event() {
        let wire_ts = 1_700_000_000_000u64;
        let received_at = 1_700_000_001_000u64;
        let sender_uri = "mimi://meet.proton.me/d/alice@proton.me/device1";
        let room = meet_room_uri("my-room");
        let (content, id) = build_mimi_message(
            &ChatComposeRequest::Message {
                text: "hello".into(),
                reply_to: None,
            },
            sender_uri,
            &room,
            wire_ts,
        )
        .unwrap();
        let bytes = content.to_cbor_bytes().unwrap();
        let mimi = parse_mimi_content(&bytes).unwrap();
        let event =
            decode_mimi_content(&mimi, id, ParticipantId("sender-uuid".into()), received_at)
                .unwrap();
        match event {
            ChatIncomingEvent::Message {
                text,
                received_at_ms,
                protocol,
                in_reply_to,
                topic_id,
                ..
            } => {
                assert_eq!(text, "hello");
                assert_eq!(received_at_ms, received_at);
                assert_eq!(protocol, ChatProtocol::MimiV1);
                assert_eq!(in_reply_to, None);
                assert_eq!(topic_id, None);
            }
            _ => panic!("expected message"),
        }
    }

    #[test]
    fn decode_reaction_add_and_remove() {
        let target = MessageId::from_hex(TARGET_HEX).unwrap();
        let sender_uri = "mimi://meet.proton.me/d/alice@proton.me/device1";
        let room = meet_room_uri("room");
        let received_at = 2_000u64;

        let (add_content, add_id) = build_mimi_message(
            &ChatComposeRequest::React {
                target,
                emoji: "👍".into(),
            },
            sender_uri,
            &room,
            1000,
        )
        .unwrap();
        let add_mimi = parse_mimi_content(&add_content.to_cbor_bytes().unwrap()).unwrap();
        let add_event =
            decode_mimi_content(&add_mimi, add_id, ParticipantId("bob".into()), received_at)
                .unwrap();
        match add_event {
            ChatIncomingEvent::Reaction {
                target: t,
                emoji,
                replaces,
                protocol,
                ..
            } => {
                assert_eq!(t, target);
                assert_eq!(emoji.as_deref(), Some("👍"));
                assert_eq!(replaces, None);
                assert_eq!(protocol, ChatProtocol::MimiV1);
            }
            _ => panic!("expected reaction add"),
        }

        let replaces = add_id;
        let (remove_content, remove_id) = build_mimi_message(
            &ChatComposeRequest::Unreact { target, replaces },
            sender_uri,
            &room,
            1001,
        )
        .unwrap();
        let remove_mimi = parse_mimi_content(&remove_content.to_cbor_bytes().unwrap()).unwrap();
        let remove_event = decode_mimi_content(
            &remove_mimi,
            remove_id,
            ParticipantId("bob".into()),
            received_at,
        )
        .unwrap();
        match remove_event {
            ChatIncomingEvent::Reaction {
                target: t,
                emoji,
                replaces: Some(r),
                protocol,
                ..
            } => {
                assert_eq!(t, target);
                assert_eq!(emoji, None);
                assert_eq!(r, replaces);
                assert_eq!(protocol, ChatProtocol::MimiV1);
            }
            _ => panic!("expected reaction remove"),
        }
    }
}
