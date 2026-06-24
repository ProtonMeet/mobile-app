use mls_rs_codec::MlsEncode;
use mls_types::MediaType;
use proton_meet_chat::{
    ChatComposeRequest, ChatIncomingEvent, ChatProtocol, LEGACY_MEET_MEDIA,
};

use crate::app::test_support::{
    build_app, build_app_with_mls_service, default_app_state, state_with_participant_only,
    two_user_mls_services_with_group,
};
use crate::domain::user::ports::UserService;
use crate::errors::core::MeetCoreError;

#[tokio::test]
async fn active_meeting_link_errors_without_participant() {
    let app = build_app(default_app_state()).await;
    let err = app.active_meeting_link().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn active_meeting_link_errors_without_mls_client() {
    let app = build_app(state_with_participant_only("chat-user")).await;
    let err = app.active_meeting_link().await.unwrap_err();
    assert!(!matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn compose_chat_errors_without_participant() {
    let app = build_app(default_app_state()).await;
    let err = app
        .compose_chat(ChatComposeRequest::Message {
            text: "hello".into(),
            reply_to: None,
        })
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn decode_chat_errors_without_participant() {
    let app = build_app(default_app_state()).await;
    let err = app.decode_chat(vec![1, 2, 3]).await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn active_meeting_link_returns_meeting_id_after_mls_join() {
    let meet_link = "app_chat_active_meeting_link";
    let (service1, user1, store1, _, _, _) =
        two_user_mls_services_with_group(meet_link, "chat-user-1", "chat-user-2").await;
    let app = build_app_with_mls_service(service1, store1, user1).await;

    assert_eq!(app.active_meeting_link().await.unwrap(), meet_link);
}

#[tokio::test]
async fn compose_chat_mimi_roundtrip_between_two_apps() {
    let meet_link = "app_chat_mimi_roundtrip";
    let (service1, user1, store1, service2, user2, store2) =
        two_user_mls_services_with_group(meet_link, "mimi-user-1", "mimi-user-2").await;
    let app1 = build_app_with_mls_service(service1, store1, user1).await;
    let app2 = build_app_with_mls_service(service2, store2, user2).await;

    let packet = app1
        .compose_chat(ChatComposeRequest::Message {
            text: "hello from app".into(),
            reply_to: None,
        })
        .await
        .expect("compose chat");
    assert!(!packet.payload.is_empty());
    assert!(matches!(
        packet.local_echo,
        ChatIncomingEvent::Message { .. }
    ));

    let event = app2
        .decode_chat(packet.payload)
        .await
        .expect("decode chat");
    match event {
        ChatIncomingEvent::Message { text, protocol, .. } => {
            assert_eq!(text, "hello from app");
            assert_eq!(protocol, ChatProtocol::MimiV1);
        }
        other => panic!("expected message event, got {other:?}"),
    }
}

#[tokio::test]
async fn decode_chat_decodes_legacy_plaintext_media() {
    let meet_link = "app_chat_legacy_plaintext";
    let (service1, user1, store1, service2, user2, store2) =
        two_user_mls_services_with_group(meet_link, "legacy-user-1", "legacy-user-2").await;

    let media = MediaType {
        media_type: LEGACY_MEET_MEDIA.into(),
        parameters: vec![],
    };
    let plaintext = b"legacy hello";
    let mls_msg = service1
        .encrypt_application_message_bytes(meet_link, media, plaintext)
        .await
        .expect("encrypt legacy bytes");
    let payload = mls_msg.mls_encode_to_vec().expect("encode mls");

    let app2 = build_app_with_mls_service(service2, store2, user2).await;
    let event = app2.decode_chat(payload).await.expect("decode legacy");
    match event {
        ChatIncomingEvent::Message { text, protocol, .. } => {
            assert_eq!(text, "legacy hello");
            assert_eq!(protocol, ChatProtocol::Legacy);
        }
        other => panic!("expected legacy message event, got {other:?}"),
    }

    let app1 = build_app_with_mls_service(service1, store1, user1).await;
    assert_eq!(app1.active_meeting_link().await.unwrap(), meet_link);
}

#[tokio::test]
async fn decode_chat_returns_unsupported_for_unknown_media_type() {
    let meet_link = "app_chat_unsupported_media";
    let (service1, _, _, service2, user2, store2) =
        two_user_mls_services_with_group(meet_link, "unsupported-1", "unsupported-2").await;

    let media = MediaType {
        media_type: "application/unknown".into(),
        parameters: vec![],
    };
    let mls_msg = service1
        .encrypt_application_message_bytes(meet_link, media, b"opaque")
        .await
        .expect("encrypt unknown media");
    let payload = mls_msg.mls_encode_to_vec().expect("encode mls");

    let app2 = build_app_with_mls_service(service2, store2, user2).await;
    let event = app2.decode_chat(payload).await.expect("decode unsupported");
    assert!(matches!(event, ChatIncomingEvent::Unsupported { .. }));
}

#[tokio::test]
async fn encrypt_and_decrypt_message_roundtrip_via_legacy_helpers() {
    let meet_link = "app_chat_encrypt_decrypt_legacy";
    let (service1, user1, store1, service2, user2, store2) =
        two_user_mls_services_with_group(meet_link, "enc-user-1", "enc-user-2").await;
    let app1 = build_app_with_mls_service(service1, store1, user1).await;
    let app2 = build_app_with_mls_service(service2, store2, user2).await;

    let ciphertext = app1
        .encrypt_message("plain mls string")
        .await
        .expect("encrypt");
    let decrypted = app2.decrypt_message(ciphertext).await.expect("decrypt");
    assert_eq!(decrypted.message, "plain mls string");
}
