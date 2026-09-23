#[cfg(test)]
use std::sync::Arc;
use std::time::Duration;

use crate::{
    domain::user::ports::{ConnectionState, UserService},
    infra::{dto::websocket::ClientAck, ws_client::WebSocketMessage},
    service::{
        service_state::MlsGroupState,
        user_service::{MessageWithId, Service},
        utils::describe_proposal_kind,
    },
    utils::{instant, sleep},
};
use meet_type::{
    fanout::{RTCMessageIn, RTCMessageInContent},
    JoinRoomResponse, WebSocketTextResponse, WebSocketTextResponseCommand,
};
use mls_spec::Parsable;
use uuid::Uuid;

impl Service {
    pub(super) async fn handle_websocket_message_impl(
        &self,
        message: WebSocketMessage,
    ) -> Result<(), anyhow::Error> {
        const MLS_STATE_CHECK_TIMEOUT: u64 = 3; // seconds

        match message {
            WebSocketMessage::Text(text) => {
                if let Ok(envelope) = serde_json::from_str::<WebSocketTextResponse>(&text) {
                    match envelope.command {
                        WebSocketTextResponseCommand::AgentPending(notification) => {
                            let device_id = notification.device_id;
                            if !self
                                .handlers
                                .call_agent_pending_handler(device_id.clone())
                                .await
                            {
                                tracing::debug!("AgentPending received but no handler registered: device_id={device_id}");
                            }
                            return Ok(());
                        }
                        WebSocketTextResponseCommand::AgentLeft(notification) => {
                            let device_id = notification.device_id;
                            if !self
                                .handlers
                                .call_agent_left_handler(device_id.clone())
                                .await
                            {
                                tracing::debug!("AgentLeft received but no handler registered: device_id={device_id}");
                            }
                            return Ok(());
                        }
                        _ => {}
                    }
                }

                // try to parse as JoinRoomResponse
                if let Ok(join_response) = serde_json::from_str::<JoinRoomResponse>(&text) {
                    #[cfg(debug_assertions)]
                    tracing::info!(
                        "Parsed JoinRoomResponse: success={}, error={:?}",
                        join_response.success,
                        join_response.error
                    );
                    if !join_response.success {
                        if let Some(error) = join_response.error {
                            tracing::error!("Join room failed: {}", error);
                        }
                    } else {
                        {
                            tracing::info!("Join room successful");
                        } // Release state lock before sending message to avoid deadlock
                    }
                    return Ok(());
                }
                // if none of the above, log the original text
                tracing::info!("Received text message from meet-server: {}", text);
            }
            WebSocketMessage::Binary(items) => {
                let mut requires_ack = true;
                let rtc_payload: Option<Vec<u8>>;
                let mut msg_id: Option<Uuid> = None;

                // Try CBOR decoding for wrapped messages
                if let Ok(msg) = ciborium::from_reader::<MessageWithId, _>(&items[..]) {
                    rtc_payload = Some(msg.payload);
                    msg_id = Some(msg.id);
                } else {
                    rtc_payload = Some(items);
                }

                if let Some(payload) = rtc_payload {
                    match RTCMessageIn::from_tls_bytes(&payload) {
                        Ok(rtc_message) => {
                            let msg_id_for_log = msg_id.as_ref().map(|id| id.to_string());
                            match rtc_message.content {
                                RTCMessageInContent::JoinRequest(info) => {
                                    requires_ack = false;
                                    tracing::info!(
                                        ws_msg_id = msg_id_for_log.as_deref().unwrap_or("n/a"),
                                        "Received join request notification"
                                    );
                                    self.handle_join_request(info).await?;
                                }
                                RTCMessageInContent::JoinRequestRemoved(info) => {
                                    requires_ack = false;
                                    tracing::info!(
                                        ws_msg_id = msg_id_for_log.as_deref().unwrap_or("n/a"),
                                        "Received join request removed notification"
                                    );
                                    self.handle_join_request_removed(info).await?;
                                }
                                other => {
                                    // check if the mls group is ready before we process the message
                                    let mls_check_start = instant::now();

                                    let mut check_count = 0;
                                    // Clone Arc outside loop to avoid repeated cloning
                                    loop {
                                        check_count += 1;

                                        // Check connection state first - drop guard immediately after check
                                        let ws_connection_state =
                                            { self.ws_client.get_connection_state().await };

                                        if ws_connection_state == ConnectionState::Disconnected {
                                            tracing::error!("Websocket is disconnected, skipping binary message processing");
                                            return Ok(());
                                        }

                                        // Check MLS group state
                                        let mls_state = {
                                            let state = self.state.lock().await;
                                            state.mls_group_state.clone()
                                        };

                                        if mls_state == MlsGroupState::Success {
                                            if check_count > 1 {
                                                let elapsed = mls_check_start.elapsed();
                                                tracing::info!(
                                                    "MLS group ready after {} checks (elapsed: {:?})",
                                                    check_count,
                                                    elapsed
                                                );
                                            } else {
                                                tracing::debug!("MLS group ready immediately");
                                            }
                                            break;
                                        }

                                        let elapsed = mls_check_start.elapsed();
                                        if elapsed > Duration::from_secs(MLS_STATE_CHECK_TIMEOUT) {
                                            tracing::warn!(
                                                "MLS group not ready after {}s (checked {} times, state: {:?}), skipping binary message processing",
                                                MLS_STATE_CHECK_TIMEOUT,
                                                check_count,
                                                mls_state
                                            );
                                            return Ok(());
                                        }

                                        let state = self.state.lock().await;
                                        if state.mls_group_state == MlsGroupState::Success
                                            || state.mls_group_state
                                                == MlsGroupState::WaitingForJoinProposalWelcome
                                        {
                                            break;
                                        }

                                        // Use shorter sleep interval for faster response (100ms instead of 1s)
                                        sleep(std::time::Duration::from_millis(100)).await;
                                    }

                                    match other {
                                        RTCMessageInContent::Welcome(mls_welcome_info) => {
                                            tracing::info!(
                                                ws_msg_id =
                                                    msg_id_for_log.as_deref().unwrap_or("n/a"),
                                                "Received welcome message"
                                            );
                                            let mut state = self.state.lock().await;
                                            // save the welcome info to the state
                                            state.set_welcome_info(Some(mls_welcome_info));
                                            drop(state);
                                            self.join_proposal_welcome_notify.notify_waiters();
                                        }
                                        RTCMessageInContent::CommitUpdate(mls_commit_info) => {
                                            let room_id_str =
                                                String::from_utf8_lossy(&mls_commit_info.room_id);
                                            let commit_message = mls_types::MlsMessage::try_from(
                                                mls_commit_info.commit.clone(),
                                            )
                                            .map_err(|e| {
                                                tracing::error!(
                                                    ws_msg_id = msg_id_for_log
                                                        .as_deref()
                                                        .unwrap_or("n/a"),
                                                    room_id = %room_id_str,
                                                    error = %e,
                                                    "Failed to parse commit message"
                                                );
                                                e
                                            })?;
                                            let room_id =
                                                String::from_utf8(mls_commit_info.room_id.clone())
                                                    .map_err(|e| {
                                                        tracing::error!(
                                                            ws_msg_id = msg_id_for_log
                                                                .as_deref()
                                                                .unwrap_or("n/a"),
                                                            error = %e,
                                                            "Failed to parse room_id as UTF-8"
                                                        );
                                                        e
                                                    })?;
                                            let epoch = commit_message.epoch();
                                            let has_welcome =
                                                mls_commit_info.welcome_message.is_some();
                                            tracing::info!(
                                                ws_msg_id = msg_id_for_log
                                                    .as_deref()
                                                    .unwrap_or("n/a"),
                                                room_id = %room_id,
                                                commit_epoch = ?epoch,
                                                has_welcome = has_welcome,
                                                "Received commit update"
                                            );

                                            self.services()?
                                                .get_message_queue(room_id)
                                                .await?
                                                .push_commit(commit_message)
                                                .await?;
                                        }
                                        RTCMessageInContent::Proposal(proposal_info) => {
                                            let room_id_str =
                                                String::from_utf8_lossy(&proposal_info.room_id);
                                            let proposal_message = mls_types::MlsMessage::try_from(
                                                proposal_info.proposal.clone(),
                                            )
                                            .map_err(|e| {
                                                tracing::error!(
                                                    ws_msg_id = msg_id_for_log
                                                        .as_deref()
                                                        .unwrap_or("n/a"),
                                                    room_id = %room_id_str,
                                                    error = %e,
                                                    "Failed to parse proposal message"
                                                );
                                                e
                                            })?;
                                            let room_id =
                                                String::from_utf8(proposal_info.room_id.clone())
                                                    .map_err(|e| {
                                                        tracing::error!(
                                                            ws_msg_id = msg_id_for_log
                                                                .as_deref()
                                                                .unwrap_or("n/a"),
                                                            error = %e,
                                                            "Failed to parse room_id as UTF-8"
                                                        );
                                                        e
                                                    })?;
                                            let proposal_epoch = proposal_message.epoch();
                                            let proposal_type =
                                                describe_proposal_kind(&proposal_message)
                                                    .unwrap_or("UNKNOWN");
                                            tracing::info!(
                                                ws_msg_id = msg_id_for_log
                                                    .as_deref()
                                                    .unwrap_or("n/a"),
                                                room_id = %room_id,
                                                proposal_epoch = ?proposal_epoch,
                                                proposal_type = proposal_type,
                                                "Received proposal message"
                                            );

                                            self.services()?
                                                .get_message_queue(room_id)
                                                .await?
                                                .push_proposal(proposal_message)
                                                .await?;
                                        }

                                        RTCMessageInContent::LiveKitAdminChange(
                                            livekit_admin_change_info,
                                        ) => {
                                            let room_id = String::from_utf8(
                                                livekit_admin_change_info.room_id.clone(),
                                            )?;
                                            let participant_uid = String::from_utf8(
                                                livekit_admin_change_info.participant_uid.clone(),
                                            )?;
                                            let participant_type =
                                                livekit_admin_change_info.participant_type;
                                            tracing::info!(
                                                ws_msg_id = msg_id_for_log
                                                    .as_deref()
                                                    .unwrap_or("n/a"),
                                                room_id = %room_id,
                                                participant_uid = %participant_uid,
                                                participant_type = participant_type,
                                                "Received livekit admin change"
                                            );
                                            self.handle_livekit_admin_change(
                                                &room_id,
                                                participant_uid,
                                                participant_type,
                                            )
                                            .await?;
                                        }
                                        RTCMessageInContent::RemoveLeafNode(
                                            _mls_remove_leaf_node_info,
                                        ) => {
                                            tracing::debug!(
                                                "Received RemoveLeafNode message (not being used)"
                                            );
                                        }
                                        RTCMessageInContent::SendCommit(_mls_commit_info) => {
                                            tracing::debug!(
                                                "Received SendCommit message (not being used)"
                                            );
                                        }
                                        RTCMessageInContent::SendProposalAndCommit(
                                            _mls_proposal_and_commit_info,
                                        ) => {
                                            tracing::debug!(
                                        "Received SendProposalAndCommit message (not being used)"
                                    );
                                        }
                                        RTCMessageInContent::JoinDecision(join_decision_info) => {
                                            requires_ack = false;
                                            tracing::info!(
                                                ws_msg_id =
                                                    msg_id_for_log.as_deref().unwrap_or("n/a"),
                                                "Received join decision notification"
                                            );
                                            self.handle_join_decision(join_decision_info).await?;
                                        }
                                        RTCMessageInContent::JoinRequest(_)
                                        | RTCMessageInContent::JoinRequestRemoved(_) => {
                                            unreachable!("join request frames are handled before MLS processing")
                                        }
                                        RTCMessageInContent::AgentBundle(
                                            _mls_agent_bundle_info,
                                        ) => {
                                            tracing::debug!(
                                                "Received AgentBundle message (not implemented yet)"
                                            );
                                        }
                                    }
                                }
                            }
                        }
                        Err(e) => {
                            tracing::error!("Failed to parse RTC message from payload: {:?}", e);
                        }
                    }
                } else {
                    tracing::warn!("No payload extracted from binary message");
                }

                if requires_ack {
                    if let Some(message_id) = msg_id {
                        // Encode UUID back to CBOR for ack
                        let mut ack_bytes = Vec::new();
                        ciborium::into_writer(
                            &ClientAck {
                                msg_type: "ack".to_string(),
                                id: message_id,
                            },
                            &mut ack_bytes,
                        )?;
                        self.ws_client
                            .send_message(WebSocketMessage::Binary(ack_bytes))
                            .await?;
                        #[cfg(debug_assertions)]
                        tracing::info!("Ack sent for message ID: {:?}", message_id);
                    }
                }

                #[cfg(debug_assertions)]
                tracing::info!("Binary message processing completed successfully");
            }
            WebSocketMessage::Close(reason) => {
                tracing::info!("Received close message: {:?}", reason);
            }
        }

        Ok(())
    }
}

#[cfg(not(target_family = "wasm"))]
#[cfg(test)]
impl Service {
    /// Returns the message cache backing `room_id`'s [`MessageQueue`].
    ///
    /// The cache moved from `Service` onto the per-room queue, so tests reach it through
    /// the service bundle rather than off a field.
    pub async fn get_cached_message(
        &self,
        room_id: &str,
    ) -> Result<Arc<dyn crate::domain::mls::ports::MessageCachePort>, anyhow::Error> {
        Ok(self
            .services()?
            .get_message_queue(room_id.to_string())
            .await?
            .msg_cache())
    }
}
