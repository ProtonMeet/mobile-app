use crate::error::ChatError;
use crate::types::{ChatComposeRequest, MessageId};
use mimi_content::{
    BaseDispos, Bstr, Disposition as Disp, MessageId as MimiMessageId, MessageIdDigest,
    MimiContent, MimiContentDeserialize, MimiContentSalt, Name, NestedPart, NestedPartContent,
    SinglePart, Tstr, TstrRef, Value,
};
use sha2::{Digest, Sha256};
use unicode_segmentation::UnicodeSegmentation;

pub const MIMI_CONTENT_MEDIA: &str = "application/mimi-content";
pub const LEGACY_MEET_MEDIA: &str = "application/vnd.proton-meet-old-message";

pub fn meet_room_uri(meeting_link_name: &str) -> String {
    format!("mimi://meet.proton.me/r/{meeting_link_name}")
}

fn sender_timestamp_extension(wire_timestamp_ms: u64) -> (Name, Value) {
    use mimi_content::reexports::ciborium;
    let secs = wire_timestamp_ms / 1000;
    let millis = (wire_timestamp_ms % 1000) as i64;
    let mut pairs = vec![(
        ciborium::Value::Integer(1.into()),
        ciborium::Value::Integer(secs.into()),
    )];
    if millis > 0 {
        pairs.push((
            ciborium::Value::Integer((-3).into()),
            ciborium::Value::Integer(millis.into()),
        ));
    }
    (Name::Int(3), ciborium::Value::Map(pairs).into())
}

fn compose_salt(
    sender_uri: &str,
    room_uri: &str,
    wire_timestamp_ms: u64,
    request: &ChatComposeRequest,
) -> MimiContentSalt {
    let mut hasher = Sha256::new();
    hasher.update(sender_uri.as_bytes());
    hasher.update(room_uri.as_bytes());
    hasher.update(wire_timestamp_ms.to_be_bytes());
    match request {
        ChatComposeRequest::Message { text, reply_to } => {
            hasher.update([0u8]);
            hasher.update(text.as_bytes());
            if let Some(rt) = reply_to {
                hasher.update(rt.message_id.as_bytes());
                if let Some(topic_id) = &rt.topic_id {
                    hasher.update(topic_id.as_bytes());
                }
            }
        }
        ChatComposeRequest::React { target, emoji } => {
            hasher.update([1u8]);
            hasher.update(target.as_bytes());
            hasher.update(emoji.as_bytes());
        }
        ChatComposeRequest::Unreact { target, replaces } => {
            hasher.update([2u8]);
            hasher.update(target.as_bytes());
            hasher.update(replaces.as_bytes());
        }
    }
    let hash = hasher.finalize();
    let mut salt = [0u8; 16];
    salt.copy_from_slice(&hash[..16]);
    salt
}

fn validate_reaction_emoji(emoji: &str) -> Result<(), ChatError> {
    if emoji.graphemes(true).count() != 1 || emoji.contains('\u{200d}') {
        return Err(ChatError::InvalidEmoji);
    }
    Ok(())
}

pub fn mimi_id_from_domain(id: &MessageId) -> MimiMessageId {
    MimiMessageId::from_raw_unchecked(*id.as_bytes())
}

pub fn domain_id_from_mimi(id: &MimiMessageId) -> MessageId {
    MessageId::from_bytes(**id)
}

pub fn compute_message_id<H: MessageIdDigest>(
    sender_uri: &str,
    room_uri: &str,
    content: &MimiContent,
) -> Result<MessageId, ChatError> {
    let id =
        MimiMessageId::construct::<H>(TstrRef::from(sender_uri), TstrRef::from(room_uri), content)
            .map_err(|e| ChatError::InvalidMimiContent(e.to_string()))?;
    Ok(domain_id_from_mimi(&id))
}

pub fn compute_message_id_from_content(
    mimi: &MimiContent,
    sender_uri: &str,
    meeting_link_name: &str,
) -> Result<MessageId, ChatError> {
    compute_message_id::<Sha256>(sender_uri, &meet_room_uri(meeting_link_name), mimi)
}

pub fn build_mimi_message(
    request: &ChatComposeRequest,
    sender_uri: &str,
    room_uri: &str,
    wire_timestamp_ms: u64,
) -> Result<(MimiContent, MessageId), ChatError> {
    let (ext_name, ext_value) = sender_timestamp_extension(wire_timestamp_ms);
    let salt = compose_salt(sender_uri, room_uri, wire_timestamp_ms, request);

    let content = match request {
        ChatComposeRequest::Message { text, reply_to } => {
            let nested = NestedPart::builder()
                .disposition(Disp::Base(BaseDispos::Render))
                .part_content(NestedPartContent::SinglePart(
                    SinglePart::builder()
                        .content_type(Tstr::from("text/markdown"))
                        .content(Bstr::from(text.as_bytes().to_vec()))
                        .build(),
                ))
                .build();

            match reply_to {
                None => MimiContent::builder()
                    .salt_from_outside_entropy(salt)
                    .with_extension(ext_name, ext_value)
                    .topic_id(Bstr::default())
                    .nested_part(nested)
                    .build(),
                Some(rt) => {
                    let topic = rt.topic_id.as_ref().unwrap_or(&rt.message_id);
                    MimiContent::builder()
                        .salt_from_outside_entropy(salt)
                        .with_extension(ext_name, ext_value)
                        .in_reply_to(mimi_id_from_domain(&rt.message_id))
                        .topic_id(Bstr::from(topic.as_bytes().to_vec()))
                        .nested_part(nested)
                        .build()
                }
            }
        }
        ChatComposeRequest::React { target, emoji } => {
            validate_reaction_emoji(emoji)?;
            let nested = NestedPart::builder()
                .disposition(Disp::Base(BaseDispos::Reaction))
                .part_content(NestedPartContent::SinglePart(
                    SinglePart::builder()
                        .content_type(Tstr::from("text/plain"))
                        .content(Bstr::from(emoji.as_bytes().to_vec()))
                        .build(),
                ))
                .build();

            MimiContent::builder()
                .salt_from_outside_entropy(salt)
                .with_extension(ext_name, ext_value)
                .in_reply_to(mimi_id_from_domain(target))
                .topic_id(Bstr::default())
                .nested_part(nested)
                .build()
        }
        ChatComposeRequest::Unreact { target, replaces } => {
            let nested = NestedPart::builder()
                .disposition(Disp::Base(BaseDispos::Reaction))
                .part_content(NestedPartContent::NullPart)
                .build();

            MimiContent::builder()
                .salt_from_outside_entropy(salt)
                .with_extension(ext_name, ext_value)
                .in_reply_to(mimi_id_from_domain(target))
                .replaces(mimi_id_from_domain(replaces))
                .topic_id(Bstr::default())
                .nested_part(nested)
                .build()
        }
    };

    let id = compute_message_id::<Sha256>(sender_uri, room_uri, &content)?;
    Ok((content, id))
}

pub fn parse_mimi_content(bytes: &[u8]) -> Result<MimiContent, ChatError> {
    MimiContent::from_cbor_bytes(bytes).map_err(|e| ChatError::InvalidMimiContent(e.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{ChatComposeRequest, MessageId, ReplyTarget};
    use mimi_content::MimiContentSerialize;

    #[test]
    fn build_text_message_produces_stable_id() {
        let wire_ts = 1_700_000_000_123u64;
        let sender = "mimi://meet.proton.me/d/alice@proton.me/device1";
        let room = meet_room_uri("my-room");
        let (content, id) = build_mimi_message(
            &ChatComposeRequest::Message {
                text: "hello".into(),
                reply_to: None,
            },
            sender,
            &room,
            wire_ts,
        )
        .unwrap();
        assert!(!content.to_cbor_bytes().unwrap().is_empty());
        let id2 = compute_message_id::<sha2::Sha256>(sender, &room, &content).unwrap();
        assert_eq!(id, id2);
        // Same inputs → same id
        let (_, id_repeat) = build_mimi_message(
            &ChatComposeRequest::Message {
                text: "hello".into(),
                reply_to: None,
            },
            sender,
            &room,
            wire_ts,
        )
        .unwrap();
        assert_eq!(id.to_hex(), id_repeat.to_hex());
    }

    #[test]
    fn reply_sets_topic_id_to_target_when_no_topic() {
        let target =
            MessageId::from_hex("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")
                .unwrap();
        let (content, _) = build_mimi_message(
            &ChatComposeRequest::Message {
                text: "reply".into(),
                reply_to: Some(ReplyTarget {
                    message_id: target,
                    topic_id: None,
                }),
            },
            "mimi://meet.proton.me/d/bob@proton.me/dev",
            &meet_room_uri("room"),
            1000,
        )
        .unwrap();
        assert_eq!(content.topic_id().map(|b| b.len()), Some(32));
    }

    #[test]
    fn react_rejects_multi_grapheme_emoji() {
        let target =
            MessageId::from_hex("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")
                .unwrap();
        let err = build_mimi_message(
            &ChatComposeRequest::React {
                target,
                emoji: "👨‍👩‍👧".into(),
            },
            "mimi://meet.proton.me/d/alice@proton.me/device1",
            &meet_room_uri("room"),
            1000,
        )
        .unwrap_err();
        assert!(matches!(err, ChatError::InvalidEmoji));
    }
}
