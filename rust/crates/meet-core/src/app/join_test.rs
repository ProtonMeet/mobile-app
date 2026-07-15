//! Join/leave room APIs on [`crate::app::App`].
//!
//! `join_meeting`, `join_meeting_with_access_token`, and
//! `join_meeting_with_access_token_with_proposal` require a live MLS client and are covered by
//! [`tests/e2e`](../../../../tests/e2e/) and `manual` tests below.

use mockall::predicate::eq;
use std::future::ready;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use crate::app::test_support::{
    app_state_with_mls_participant, build_app, build_app_with_room, build_app_with_room_and_ws,
    build_app_with_service, build_app_with_service_room_and_ws, build_app_with_ws,
    default_app_state, join_test_service_with_mls_client, room_service_with_http,
    room_service_with_http_and_crypto, room_service_with_meeting_api,
    state_with_active_participant, state_with_participant_only,
};
use crate::domain::user::models::meet_link_info::MeetParticipant;
use crate::domain::user::ports::crypto_client::MockCryptoClient;
use crate::domain::user::ports::meeting_api::MockMeetingApi;
use crate::domain::user::ports::user_service::UserService;
use crate::domain::user::ports::MockHttpClient;
use crate::errors::{core::MeetCoreError, http_client::HttpClientError};
use crate::infra::dto::realtime::{
    GroupInfoVersion, JoinType, RatchetTreeAndGroupInfo, VersionedGroupInfoData,
};
use crate::service::service::{
    create_test_service, join_switch_service_with_http, mls_group_export_snapshot,
    setup_n_user_group,
};
use crate::JOIN_TYPE_SWITCH_THRESHOLD;
use mls_spec::drafts::ratchet_tree_options::RatchetTreeOption;
use proton_meet_crypto::MEET_DISPLAY_NAME_AAD;
use proton_meet_mls::MlsClientConfig;

#[test]
fn get_join_type_stays_external_commit_when_not_new_join_type() {
    let app = tokio::runtime::Runtime::new()
        .unwrap()
        .block_on(build_app(default_app_state()));
    assert_eq!(
        app.get_join_type(false, true, JOIN_TYPE_SWITCH_THRESHOLD),
        JoinType::ExternalCommit
    );
}

#[test]
fn get_join_type_uses_external_proposal_when_switch_disabled() {
    let app = tokio::runtime::Runtime::new()
        .unwrap()
        .block_on(build_app(default_app_state()));
    assert_eq!(
        app.get_join_type(true, false, 0),
        JoinType::ExternalProposal
    );
}

#[test]
fn get_join_type_switches_at_threshold_when_enabled() {
    let app = tokio::runtime::Runtime::new()
        .unwrap()
        .block_on(build_app(default_app_state()));
    assert_eq!(
        app.get_join_type(true, true, JOIN_TYPE_SWITCH_THRESHOLD - 1),
        JoinType::ExternalCommit
    );
    assert_eq!(
        app.get_join_type(true, true, JOIN_TYPE_SWITCH_THRESHOLD),
        JoinType::ExternalProposal
    );
}

#[tokio::test]
async fn update_and_get_livekit_access_token() {
    let app = build_app(default_app_state()).await;

    assert!(matches!(
        app.get_active_livekit_access_token().await,
        Err(MeetCoreError::LivekitAccessTokenNotFound)
    ));

    app.update_livekit_access_token("token-abc".to_string())
        .await
        .unwrap();
    assert_eq!(
        app.get_active_livekit_access_token().await.unwrap(),
        "token-abc"
    );
}

#[tokio::test]
async fn update_livekit_access_token_and_websocket_url() {
    let app = build_app(default_app_state()).await;

    app.update_livekit_access_token_and_websocket_url(
        "token".to_string(),
        "wss://livekit.example".to_string(),
    )
    .await
    .unwrap();

    assert_eq!(
        app.get_active_livekit_access_token().await.unwrap(),
        "token"
    );
    assert_eq!(
        app.get_active_livekit_websocket_url().await.unwrap(),
        "wss://livekit.example"
    );
}

#[tokio::test]
async fn get_active_livekit_websocket_url_errors_when_missing() {
    let app = build_app(default_app_state()).await;
    let err = app.get_active_livekit_websocket_url().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::InternalError { .. }));
}

#[tokio::test]
async fn leave_meeting_errors_without_active_participant() {
    let app = build_app(default_app_state()).await;
    let err = app.leave_meeting().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn end_meeting_errors_without_active_participant() {
    let app = build_app(default_app_state()).await;
    let err = app.end_meeting().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn end_meeting_errors_without_mls_meeting_context() {
    // `end_meeting` resolves meeting_id before checking the LiveKit token.
    let app = build_app(state_with_participant_only("user-1")).await;
    assert!(app.end_meeting().await.is_err());
}

#[tokio::test]
async fn kick_participant_errors_without_active_participant() {
    let app = build_app(default_app_state()).await;
    let err = app
        .kick_participant("participant-1".to_string())
        .await
        .unwrap_err();
    assert!(matches!(err, MeetCoreError::ParticipantNotFound));
}

#[tokio::test]
async fn kick_participant_propagates_when_mls_client_missing() {
    let app = build_app(state_with_participant_only("user-1")).await;
    assert!(app
        .kick_participant("participant-2".to_string())
        .await
        .is_err());
}

#[tokio::test]
async fn end_meeting_propagates_room_service_error_when_meeting_id_resolves() {
    let mut meeting_api = MockMeetingApi::new();
    meeting_api.expect_end_meeting().times(0);

    let app = build_app_with_room(
        state_with_active_participant("user-1"),
        room_service_with_meeting_api(meeting_api),
    )
    .await;
    // Fails resolving meeting_id from MLS store before calling room_service.
    assert!(app.end_meeting().await.is_err());
}

#[tokio::test]
async fn get_participants_count_delegates_to_room_service() {
    let mut http = MockHttpClient::new();
    http.expect_get_participants_count()
        .with(eq("LINK123"))
        .once()
        .returning(|_| Box::pin(ready(Ok(5))));

    let app = build_app_with_room(default_app_state(), room_service_with_http(http)).await;
    assert_eq!(
        app.get_participants_count("LINK123".to_string())
            .await
            .unwrap(),
        5
    );
}

#[tokio::test]
async fn get_participants_propagates_room_service_error() {
    let mut http = MockHttpClient::new();
    http.expect_get_participants().once().returning(|_| {
        Box::pin(ready(Err(HttpClientError::Deserialize(
            "offline".to_string(),
        ))))
    });

    let app = build_app_with_room(default_app_state(), room_service_with_http(http)).await;
    assert!(app.get_participants("LINK123".to_string()).await.is_err());
}

#[tokio::test]
async fn trigger_websocket_reconnect_delegates_to_client() {
    let mut ws = crate::domain::user::ports::MockWebSocketClient::new();
    ws.expect_trigger_reconnect()
        .once()
        .returning(|| Box::pin(ready(Ok(()))));

    let app = build_app_with_ws(ws, default_app_state()).await;
    app.trigger_websocket_reconnect().await.unwrap();
}

#[tokio::test]
async fn end_meeting_errors_without_livekit_token_when_mls_client_exists() {
    const MEET_LINK: &str = "LINK123";
    let (service, user_info, mls_store) =
        join_test_service_with_mls_client("user1@test.com", MEET_LINK).await;
    let state = app_state_with_mls_participant(default_app_state(), mls_store, user_info, None);

    let app = build_app_with_service_room_and_ws(
        state,
        service,
        room_service_with_meeting_api(MockMeetingApi::new()),
        crate::app::test_support::minimal_ws_mock(),
    )
    .await;

    let err = app.end_meeting().await.unwrap_err();
    assert!(matches!(err, MeetCoreError::LivekitAccessTokenNotFound));
}

#[tokio::test]
async fn end_meeting_calls_room_service_and_disconnects_websocket() {
    const MEET_LINK: &str = "LINK123";
    const LIVEKIT_TOKEN: &str = "lk-token";
    let (service, user_info, mls_store) =
        join_test_service_with_mls_client("user1@test.com", MEET_LINK).await;
    let state = app_state_with_mls_participant(
        default_app_state(),
        mls_store,
        user_info,
        Some(LIVEKIT_TOKEN),
    );

    let mut meeting_api = MockMeetingApi::new();
    meeting_api
        .expect_end_meeting()
        .with(eq(MEET_LINK), eq(LIVEKIT_TOKEN))
        .once()
        .returning(|_, _| Box::pin(ready(Ok(()))));

    let mut ws = crate::domain::user::ports::MockWebSocketClient::new();
    ws.expect_disconnect()
        .with(eq(Some(true)))
        .once()
        .returning(|_| Box::pin(ready(Ok(()))));

    let app = build_app_with_service_room_and_ws(
        state,
        service,
        room_service_with_meeting_api(meeting_api),
        ws,
    )
    .await;

    app.end_meeting().await.unwrap();
}

#[tokio::test]
async fn get_participants_returns_room_service_list() {
    let participants = vec![MeetParticipant {
        participant_uuid: "uuid-1".to_string(),
        display_name: Some("Alice".to_string()),
        encrypted_display_name: None,
        can_subscribe: Some(1),
        can_publish: Some(1),
        can_publish_data: Some(1),
        is_admin: Some(0),
        is_host: Some(0),
    }];

    let mut http = MockHttpClient::new();
    http.expect_get_participants()
        .with(eq("LINK123"))
        .once()
        .returning({
            let participants = participants.clone();
            move |_| Box::pin(ready(Ok(participants.clone())))
        });

    let app = build_app_with_room(default_app_state(), room_service_with_http(http)).await;
    let result = app.get_participants("LINK123".to_string()).await.unwrap();
    assert_eq!(result.len(), 1);
    assert_eq!(result[0].display_name.as_deref(), Some("Alice"));
}

#[tokio::test]
async fn get_participants_decrypts_display_names_when_session_key_cached() {
    let mut state = default_app_state();
    state.meeting_display_name_session_key = Some("session-key".to_string().into());

    let participants = vec![MeetParticipant {
        participant_uuid: "uuid-1".to_string(),
        display_name: None,
        encrypted_display_name: Some("enc-name".to_string()),
        can_subscribe: None,
        can_publish: None,
        can_publish_data: None,
        is_admin: None,
        is_host: None,
    }];

    let mut http = MockHttpClient::new();
    http.expect_get_participants()
        .with(eq("LINK123"))
        .once()
        .returning({
            let participants = participants.clone();
            move |_| Box::pin(ready(Ok(participants.clone())))
        });

    let mut crypto = MockCryptoClient::new();
    crypto
        .expect_decrypt_message()
        .with(eq("enc-name"), eq("session-key"), eq(MEET_DISPLAY_NAME_AAD))
        .once()
        .returning(|_, _, _| Box::pin(ready(Ok("Decrypted Name".to_string()))));

    let app = build_app_with_room(state, room_service_with_http_and_crypto(http, crypto)).await;

    let result = app.get_participants("LINK123".to_string()).await.unwrap();
    assert_eq!(result[0].display_name.as_deref(), Some("Decrypted Name"));
}

#[tokio::test]
async fn trigger_websocket_reconnect_maps_client_error() {
    let mut ws = crate::domain::user::ports::MockWebSocketClient::new();
    ws.expect_trigger_reconnect()
        .once()
        .returning(|| Box::pin(ready(Err(anyhow::anyhow!("reconnect failed")))));

    let app = build_app_with_ws(ws, default_app_state()).await;
    let err = app.trigger_websocket_reconnect().await.unwrap_err();
    assert!(matches!(
        err,
        MeetCoreError::WebSocketError { message, .. } if message.contains("reconnect failed")
    ));
}

#[tokio::test]
async fn leave_meeting_propagates_when_mls_client_missing() {
    let mut ws = crate::domain::user::ports::MockWebSocketClient::new();
    ws.expect_disconnect().times(0);

    let app = build_app_with_room_and_ws(
        state_with_participant_only("user-1"),
        room_service_with_meeting_api(MockMeetingApi::new()),
        ws,
    )
    .await;
    assert!(app.leave_meeting().await.is_err());
}

#[tokio::test]
async fn join_room_with_switch_join_type_falls_back_to_false_on_retryable_error() {
    let meet_link_name = "join_switch_app_fallback";
    let config = MlsClientConfig::default();
    let existing_member_count = JOIN_TYPE_SWITCH_THRESHOLD as usize;
    let services = futures::future::join_all((0..existing_member_count).map(|idx| {
        let user_id = format!("user{idx}");
        async move { create_test_service(&user_id, meet_link_name).await }
    }))
    .await;
    let service_refs = services.iter().collect::<Vec<_>>();
    let groups = setup_n_user_group(service_refs, meet_link_name, config.ciphersuite).await;
    let host_group = groups[0].clone();

    let (group_info_msg, ratchet_tree_opt) = mls_group_export_snapshot(&host_group).await;
    let ratchet_tree = match &ratchet_tree_opt {
        RatchetTreeOption::Full { ratchet_tree } => ratchet_tree,
        _ => panic!("expected full ratchet tree"),
    };
    let member_count = ratchet_tree
        .iter()
        .filter_map(|slot| slot.as_ref())
        .filter_map(|node| node.as_leaf_node())
        .count();
    assert_eq!(member_count, existing_member_count);

    let joiner_service = create_test_service("joiner", meet_link_name).await;
    let joiner_token = joiner_service
        .create_mls_client("access_token", meet_link_name, "meet_password", None)
        .await
        .unwrap();

    let versioned = Arc::new(VersionedGroupInfoData {
        version: GroupInfoVersion::V1,
        data: RatchetTreeAndGroupInfo {
            ratchet_tree: ratchet_tree_opt,
            group_info: group_info_msg,
        },
    });

    let proposal_attempts = Arc::new(AtomicUsize::new(0));
    let external_commit_attempts = Arc::new(AtomicUsize::new(0));

    let join_service =
        join_switch_service_with_http(&joiner_service, "joiner", meet_link_name, |http| {
            http.expect_get_group_info().returning({
                let v = versioned.clone();
                move |_| Box::pin(ready(Ok((*v).clone())))
            });
            http.expect_join_group_by_proposal().returning({
                let proposal_attempts = proposal_attempts.clone();
                move |_, _| {
                    proposal_attempts.fetch_add(1, Ordering::SeqCst);
                    Box::pin(ready(Err(HttpClientError::MlsStatusCode(422))))
                }
            });
            http.expect_update_group_info().returning({
                let external_commit_attempts = external_commit_attempts.clone();
                move |_, _, _, _, _| {
                    external_commit_attempts.fetch_add(1, Ordering::SeqCst);
                    Box::pin(ready(Ok(())))
                }
            });
        })
        .await;

    let mut state = default_app_state();
    state.active_user_info = Some(joiner_token);
    let app = build_app_with_service(state, join_service).await;

    app.join_room_with_switch_join_type(true, false)
        .await
        .expect("should fall back to external commit after retryable proposal failures");

    assert!(
        proposal_attempts.load(Ordering::SeqCst) >= 1,
        "proposal join should be attempted with switch_join_type=true"
    );
    assert_eq!(
        external_commit_attempts.load(Ordering::SeqCst),
        1,
        "fallback should join via external commit with switch_join_type=false"
    );
}

// --- Manual integration (real backend). Run: cargo test -p proton-meet-core join_meeting -- --ignored ---

#[cfg(all(test, not(target_family = "wasm")))]
mod manual {
    use crate::app::test_support::manual;

    #[tokio::test]
    #[ignore = "requires anning atlas and a live meeting link"]
    async fn join_meeting() -> Result<(), anyhow::Error> {
        let app = manual::app_for_atlas(
            "anning",
            "test/db_path",
            "mls.anning.proton.black",
            "macos-meet@0.0.1",
        )
        .await?;

        let meeting_link_name = "YYDVC4V6D4";
        let meeting_link_p = "ZmdeJZE6BEud";
        let user_id = format!("user_{}", rand::random::<u32>());

        let meet_info = app
            .authenticate_meeting_link(
                meeting_link_name.to_string(),
                meeting_link_p.to_string(),
                user_id.clone(),
            )
            .await?;
        app.join_meeting_with_access_token(
            meet_info.access_token,
            meeting_link_name.to_string(),
            meeting_link_p.to_string(),
            None,
        )
        .await?;

        Ok(())
    }
}
