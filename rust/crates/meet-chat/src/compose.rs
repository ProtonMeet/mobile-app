use crate::types::{ChatComposeRequest, ChatIncomingEvent, ChatProtocol, MessageId, ParticipantId};

pub fn compose_local_echo(
    request: &ChatComposeRequest,
    id: MessageId,
    local_sender: ParticipantId,
    received_at_ms: u64,
) -> ChatIncomingEvent {
    match request {
        ChatComposeRequest::Message { text, reply_to } => ChatIncomingEvent::Message {
            id,
            sender: local_sender,
            received_at_ms,
            text: text.clone(),
            in_reply_to: reply_to.as_ref().map(|r| r.message_id),
            topic_id: reply_to
                .as_ref()
                .map(|r| r.topic_id.unwrap_or(r.message_id)),
            protocol: ChatProtocol::MimiV1,
        },
        ChatComposeRequest::React { target, emoji } => ChatIncomingEvent::Reaction {
            id,
            sender: local_sender,
            received_at_ms,
            target: *target,
            emoji: Some(emoji.clone()),
            replaces: None,
            protocol: ChatProtocol::MimiV1,
        },
        ChatComposeRequest::Unreact { target, replaces } => ChatIncomingEvent::Reaction {
            id,
            sender: local_sender,
            received_at_ms,
            target: *target,
            emoji: None,
            replaces: Some(*replaces),
            protocol: ChatProtocol::MimiV1,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::ReplyTarget;

    #[test]
    fn compose_local_echo_reply_sets_topic() {
        let target =
            MessageId::from_hex("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")
                .unwrap();
        let request = ChatComposeRequest::Message {
            text: "reply".into(),
            reply_to: Some(ReplyTarget {
                message_id: target,
                topic_id: None,
            }),
        };
        let id =
            MessageId::from_hex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
                .unwrap();
        let event = compose_local_echo(&request, id, ParticipantId("me".into()), 1000);
        match event {
            ChatIncomingEvent::Message {
                in_reply_to,
                topic_id,
                ..
            } => {
                assert_eq!(in_reply_to, Some(target));
                assert_eq!(topic_id, Some(target));
            }
            _ => panic!("expected message"),
        }
    }
}
