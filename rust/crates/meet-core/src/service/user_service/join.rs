use std::time::Duration;

use crate::{
    domain::user::{
        models::{UserId, UserTokenInfo, meeting_link_name::MeetingLinkName},
        ports::UserService,
    },
    errors::{core::MeetCoreError, http_client::HttpClientError},
    service::{
        service_state::MlsGroupState,
        user_service::{
            JOIN_PROPOSAL_TIMEOUT, Service, psk_id_for_commit,
            utils::{SUPPORTED_GROUP_INFO_VERSIONS, ratchet_tree_option_has_agent},
        },
        utils::{convert_mls_spec_to_types, convert_mls_types_to_spec},
    },
    utils::{instant, sleep, timeout},
};
use meet_type::fanout::{MlsCommitInfo, VersionedGroupInfoData};
use mls_spec::{
    defs::ProtocolVersion, drafts::ratchet_tree_options::RatchetTreeOption,
    messages::MlsMessageContent,
};
use mls_trait::meet_policy::RoomKind;
use proton_meet_mls::MlsGroupTrait;
use rand::Rng;

impl Service {
    pub(super) async fn join_room_impl(
        &self,
        user_info_token: &UserTokenInfo,
        meeting_link_name: &str,
    ) -> Result<(), MeetCoreError> {
        let base64_sd_kbt = self.get_sd_kbt(&user_info_token.user_id()).await?;

        let cs = {
            let mls_store = self.mls_store.read().await;
            mls_store.config.ciphersuite
        };

        // Retry logic for the whole join process
        const MAX_RETRIES: u32 = 5;
        const BASE_DELAY_MS: u64 = 500;
        const MAX_DELAY_MS: u64 = 10000;
        let mut retry_count = 0;

        {
            let mut state = self.state.lock().await;
            state.mls_retry_count = 0;
        }

        tracing::info!("Retry logic for the whole join process");
        loop {
            let result = self.mls_api.get_group_info(&base64_sd_kbt).await;
            match result {
                // join by external commit
                Ok(ratchet_tree_and_group_info) => {
                    // check if the server version is supported
                    if !SUPPORTED_GROUP_INFO_VERSIONS.contains(&ratchet_tree_and_group_info.version)
                    {
                        let mut state = self.state.lock().await;
                        state.set_mls_group_state(MlsGroupState::ServerVersionNotSupported);
                        return Err(MeetCoreError::MlsServerVersionNotSupported);
                    }

                    if let MlsMessageContent::GroupInfo(group_info) =
                        ratchet_tree_and_group_info.data.group_info.content
                    {
                        tracing::info!("Join by external commit");

                        // Detect agent presence from the GroupInfo's ratchet tree before building the local group.
                        let psk_id_for_join = psk_id_for_commit(
                            meeting_link_name,
                            ratchet_tree_option_has_agent(
                                &ratchet_tree_and_group_info.data.ratchet_tree,
                            ),
                        );
                        let (mls_group, commit_bundle) = self
                            .create_external_commit_with_psks(
                                &user_info_token.user_id(),
                                meeting_link_name,
                                cs,
                                group_info,
                                ratchet_tree_and_group_info.data.ratchet_tree,
                                vec![psk_id_for_join],
                            )
                            .await?;

                        #[allow(unused_variables)]
                        let (epoch, roster, leaf_node_index) = {
                            let mls_group = mls_group.read().await;
                            let lead_node_index = mls_group.own_leaf_index()?;
                            (
                                mls_group.epoch(),
                                mls_group.roster().count(),
                                *lead_node_index,
                            )
                        };
                        #[cfg(debug_assertions)]
                        tracing::info!(
                            "Joined room {:?}. epoch: {:?}, roster: {:?}, lead_node_index: {:?}, participant_id: {:?}",
                            &meeting_link_name,
                            epoch,
                            roster,
                            &leaf_node_index,
                            &user_info_token.user_identifier.id.to_string(),
                        );

                        // Prepare commit info to send to the server
                        let welcome = commit_bundle.welcome.map(TryInto::try_into).transpose()?;
                        let ratchet_tree_option: RatchetTreeOption = commit_bundle
                            .ratchet_tree
                            .ok_or(anyhow::anyhow!("Expected commit to have a RatchetTree"))?
                            .try_into()?;

                        let mls_commit_info = MlsCommitInfo {
                            room_id: meeting_link_name.as_bytes().to_vec(),
                            welcome_message: welcome,
                            commit: convert_mls_types_to_spec(&commit_bundle.commit)?,
                        };

                        let group_info = commit_bundle
                            .group_info
                            .ok_or(anyhow::anyhow!("Expected commit to have a GroupInfo"))?;
                        let group_info_message = convert_mls_types_to_spec(&group_info)?;

                        match self
                            .mls_api
                            .update_group_info(
                                &base64_sd_kbt,
                                &group_info_message,
                                &ratchet_tree_option,
                                Some(&mls_commit_info),
                                None,
                            )
                            .await
                        {
                            Ok(_) => {
                                let mut state = self.state.lock().await;
                                state.set_mls_group_state(MlsGroupState::Success);
                                state.mls_retry_count = retry_count;
                                return Ok(());
                            }
                            Err(e) => {
                                if let HttpClientError::MlsStatusCode(status) = e
                                    && status == 422
                                {
                                    retry_count += 1;
                                    if retry_count >= MAX_RETRIES {
                                        {
                                            let mut state = self.state.lock().await;
                                            state.mls_retry_count = retry_count;
                                        }
                                        return Err(MeetCoreError::MaxRetriesReached);
                                    }
                                    let delay = BASE_DELAY_MS * (1 << retry_count);
                                    let jitter = rand::thread_rng().gen_range(0..delay);
                                    let sleep_duration = Duration::from_millis(std::cmp::min(
                                        delay + jitter,
                                        MAX_DELAY_MS,
                                    ));
                                    tracing::warn!(
                                        retry_count,
                                        delay_ms = sleep_duration.as_millis(),
                                        "Retrying join_room due to 422 error for {:?} ms",
                                        sleep_duration.as_millis(),
                                    );
                                    sleep(sleep_duration).await;
                                    continue;
                                }
                                return Err(e.into());
                            }
                        }
                    }
                }
                // create group and upload group info
                Err(e) => {
                    if !matches!(e, HttpClientError::GroupInfoEmpty) {
                        return Err(e.into());
                    }

                    // Generate unique meeting link name to avoid conflicts
                    let unique_meeting_link_name =
                        Self::generate_unique_group_id(meeting_link_name);
                    let (_, commit_bundle) = self
                        .create_mls_group(
                            &user_info_token.user_id(),
                            &unique_meeting_link_name,
                            meeting_link_name,
                            cs,
                        )
                        .await?;

                    let group_info = commit_bundle
                        .group_info
                        .ok_or(anyhow::anyhow!("Expected commit to have a GroupInfo"))?;
                    let group_info_message = convert_mls_types_to_spec(&group_info)?;
                    let ratchet_tree_option = commit_bundle
                        .ratchet_tree
                        .ok_or(anyhow::anyhow!("Expected commit to have a RatchetTree"))?
                        .try_into()?;

                    match self
                        .mls_api
                        .update_group_info(
                            &base64_sd_kbt,
                            &group_info_message,
                            &ratchet_tree_option,
                            None,
                            None,
                        )
                        .await
                    {
                        Ok(_) => {
                            let mut state = self.state.lock().await;
                            state.set_mls_group_state(MlsGroupState::Success);
                            return Ok(());
                        }
                        Err(e) => {
                            if let HttpClientError::MlsStatusCode(status) = e
                                && status == 422
                            {
                                if retry_count >= MAX_RETRIES {
                                    return Err(e.into());
                                }
                                let delay = BASE_DELAY_MS * (1 << retry_count);
                                let jitter = rand::thread_rng().gen_range(0..delay);
                                let sleep_duration = Duration::from_millis(std::cmp::min(
                                    delay + jitter,
                                    MAX_DELAY_MS,
                                ));
                                tracing::warn!(
                                    retry_count,
                                    delay_ms = sleep_duration.as_millis(),
                                    "Retrying join_room due to 422 error"
                                );
                                sleep(sleep_duration).await;
                                retry_count += 1;
                                continue;
                            }
                            return Err(e.into());
                        }
                    }
                }
            }
        }
    }

    pub(super) async fn join_room_with_proposal_impl(
        &self,
        participant_id: &UserId,
        meeting_link_name: &str,
    ) -> Result<(), MeetCoreError> {
        let base64_sd_kbt = self.get_sd_kbt(participant_id).await?;

        let cs = {
            let mls_store = self.mls_store.read().await;
            mls_store.config.ciphersuite
        };

        // Retry logic for the whole join process
        const MAX_RETRIES: u32 = 2;
        const BASE_DELAY_MS: u64 = 200;
        let mut retry_count = 0;
        let mut cached_group_info: Option<VersionedGroupInfoData> = None;

        {
            let mut state = self.state.lock().await;
            state.mls_retry_count = 0;
        }

        loop {
            let result = if let Some(cached) = cached_group_info.clone() {
                Ok(cached)
            } else {
                self.mls_api.get_group_info(&base64_sd_kbt).await
            };

            match result {
                // join by external proposal
                Ok(ratchet_tree_and_group_info) => {
                    cached_group_info = Some(ratchet_tree_and_group_info.clone());

                    // check if the server version is supported
                    if !SUPPORTED_GROUP_INFO_VERSIONS.contains(&ratchet_tree_and_group_info.version)
                    {
                        let mut state = self.state.lock().await;
                        state.set_mls_group_state(MlsGroupState::ServerVersionNotSupported);
                        return Err(MeetCoreError::MlsServerVersionNotSupported);
                    }

                    if let MlsMessageContent::GroupInfo(group_info) =
                        ratchet_tree_and_group_info.data.group_info.content
                    {
                        tracing::info!("Join by external proposal");

                        let proposal = self
                            .create_external_proposal(
                                participant_id,
                                cs,
                                group_info,
                                ratchet_tree_and_group_info.data.ratchet_tree.clone(),
                            )
                            .await?;
                        let proposal_message = convert_mls_types_to_spec(&proposal)?;
                        match self
                            .mls_api
                            .join_group_by_proposal(&base64_sd_kbt, &proposal_message)
                            .await
                        {
                            Ok(_) => {
                                // mark state to waiting for join proposal welcome
                                let mut state = self.state.lock().await;
                                state.set_mls_group_state(
                                    MlsGroupState::WaitingForJoinProposalWelcome,
                                );
                            }
                            Err(e) => {
                                tracing::warn!("Failed to join group by proposal: {:?}", e);
                                if let HttpClientError::MlsStatusCode(status) = &e
                                    && (400..500).contains(status)
                                {
                                    cached_group_info = None;
                                }
                                if retry_count >= MAX_RETRIES {
                                    {
                                        let mut state = self.state.lock().await;
                                        state.mls_retry_count = retry_count;
                                    }
                                    return Err(e.into());
                                }
                                tracing::warn!(
                                    retry_count,
                                    "Retrying join_room_with_proposal due to error: {:?}",
                                    e
                                );
                                retry_count += 1;

                                sleep(Duration::from_millis(BASE_DELAY_MS)).await;
                                continue;
                            }
                        }
                        let start_time = instant::now();
                        // waiting for websocket to receive the welcome message from the server
                        loop {
                            let mut state = self.state.lock().await;
                            if state.mls_group_state == MlsGroupState::Success {
                                // we had recevied the join proposal welcome and estiblish the mls group successfully
                                break;
                            }
                            if state.mls_group_state == MlsGroupState::WaitingForJoinProposalWelcome
                            {
                                if let Some(welcome_info) = state.get_welcome_info() {
                                    // we had recevied the join proposal welcome and establish the mls group successfully
                                    let welcome = welcome_info.welcome;
                                    let welcome_mls =
                                        welcome.into_mls_message(ProtocolVersion::Mls10);
                                    let welcome_message = convert_mls_spec_to_types(&welcome_mls)?;
                                    self.join_group(
                                        participant_id,
                                        meeting_link_name,
                                        welcome_message,
                                        welcome_info.ratchet_tree,
                                    )
                                    .await
                                    .map_err(|e| {
                                        tracing::warn!(
                                            "Failed to join group with welcome info: {:?}",
                                            e
                                        );
                                        MeetCoreError::RoomJoinFailed {
                                            room_id: meeting_link_name.to_string(),
                                            reason: "Failed to join group with welcome info"
                                                .to_string(),
                                        }
                                    })?;
                                    state.set_mls_group_state(MlsGroupState::Success);
                                    state.mls_retry_count = retry_count;
                                    state.set_welcome_info(None);
                                    drop(state);
                                    tracing::info!("Join group with welcome info successfully");
                                    return Ok(());
                                } else {
                                    tracing::debug!("Waiting for join proposal welcome");
                                }
                            } else {
                                tracing::warn!(
                                    "Join proposal state is not valid: {:?}",
                                    state.mls_group_state
                                );
                                drop(state);
                                return Err(MeetCoreError::RoomJoinFailed {
                                    room_id: meeting_link_name.to_string(),
                                    reason: "Join proposal state is not valid".to_string(),
                                });
                            }
                            drop(state);

                            if start_time.elapsed().as_secs() > JOIN_PROPOSAL_TIMEOUT {
                                if retry_count >= MAX_RETRIES {
                                    return  Err(MeetCoreError::RoomJoinFailed {
                                        room_id: meeting_link_name.to_string(),
                                        reason: "External proposal join timeout, didn't receive the welcome message from the server, please try agian"
                                            .to_string(),
                                    });
                                } else {
                                    tracing::warn!(
                                        retry_count,
                                        "Retrying join_room_with_proposal due to timeout"
                                    );
                                    retry_count += 1;
                                    sleep(Duration::from_millis(BASE_DELAY_MS)).await;
                                    break;
                                }
                            } else {
                                sleep(Duration::from_millis(BASE_DELAY_MS)).await;
                            }
                        }
                    } else {
                        tracing::warn!(
                            "Expected GroupInfo but received {:?} for room {}",
                            ratchet_tree_and_group_info.data.group_info.content,
                            meeting_link_name
                        );
                        if retry_count >= MAX_RETRIES {
                            return Err(MeetCoreError::RoomJoinFailed {
                                room_id: meeting_link_name.to_string(),
                                reason: format!(
                                    "Invalid message content type: expected GroupInfo, got {:?}",
                                    ratchet_tree_and_group_info.data.group_info.content
                                ),
                            });
                        }
                        tracing::warn!(
                            retry_count,
                            "Retrying join_room_with_proposal due to invalid message content type"
                        );
                        retry_count += 1;
                        sleep(Duration::from_millis(BASE_DELAY_MS)).await;
                        continue;
                    }
                }
                // create group and upload group info
                Err(e) => {
                    cached_group_info = None;
                    if !matches!(e, HttpClientError::GroupInfoEmpty) {
                        return Err(e.into());
                    }

                    // Generate unique meeting link name to avoid conflicts
                    let unique_meeting_link_name =
                        Self::generate_unique_group_id(meeting_link_name);
                    let (_, commit_bundle) = self
                        .create_mls_group(
                            participant_id,
                            &unique_meeting_link_name,
                            meeting_link_name,
                            cs,
                        )
                        .await?;

                    let group_info = commit_bundle
                        .group_info
                        .ok_or(anyhow::anyhow!("Expected commit to have a GroupInfo"))?;
                    let group_info_message = convert_mls_types_to_spec(&group_info)?;
                    let ratchet_tree_option = commit_bundle
                        .ratchet_tree
                        .ok_or(anyhow::anyhow!("Expected commit to have a RatchetTree"))?
                        .try_into()?;

                    match self
                        .mls_api
                        .update_group_info(
                            &base64_sd_kbt,
                            &group_info_message,
                            &ratchet_tree_option,
                            None,
                            None,
                        )
                        .await
                    {
                        Ok(_) => {
                            let mut state = self.state.lock().await;
                            state.set_mls_group_state(MlsGroupState::Success);
                            state.mls_retry_count = retry_count;
                            return Ok(());
                        }
                        Err(e) => {
                            if let HttpClientError::MlsStatusCode(status) = e
                                && status == 422
                            {
                                // the other client has joined room first, need retry again to join with extenral proposal
                                if retry_count >= MAX_RETRIES {
                                    {
                                        let mut state = self.state.lock().await;
                                        state.mls_retry_count = retry_count;
                                    }
                                    return Err(e.into());
                                }
                                sleep(Duration::from_millis(BASE_DELAY_MS)).await;
                                retry_count += 1;
                                continue;
                            }
                            return Err(e.into());
                        }
                    }
                }
            }
        }
    }

    pub(super) async fn join_room_with_switch_join_type_impl(
        &self,
        user_info_token: &UserTokenInfo,
        meeting_link_name: &MeetingLinkName,
        switch_join_type: bool,
        is_waiting_room: bool,
    ) -> Result<(), MeetCoreError> {
        let base64_sd_kbt = self.get_sd_kbt(&user_info_token.user_id()).await?;

        tracing::info!(
            switch_join_type,
            is_waiting_room,
            "[WS-HANG] join_room_with_switch_join_type_impl: fetching group info (get_group_info)"
        );
        let ratchet_tree_and_group_info = match self.mls_api.get_group_info(&base64_sd_kbt).await {
            Ok(ratchet_tree_and_group_info) => ratchet_tree_and_group_info,
            Err(e) => {
                if matches!(e, HttpClientError::GroupInfoEmpty) {
                    // create group and upload group info
                    let room_kind: Option<RoomKind> = if is_waiting_room {
                        Some(RoomKind::BasicRoomWithWaiting {
                            other_users: vec![],
                        })
                    } else {
                        None
                    };
                    let (group_info_message, ratchet_tree_option) = self
                        .mls_service
                        .create_mls_group(meeting_link_name, &user_info_token.user_id(), room_kind)
                        .await?;

                    self.mls_api
                        .update_group_info(
                            &base64_sd_kbt,
                            &group_info_message,
                            &ratchet_tree_option,
                            None,
                            None,
                        )
                        .await?;

                    {
                        let mut state = self.state.lock().await;
                        state.set_mls_group_state(MlsGroupState::Success);
                    }

                    return Ok(());
                }
                if let HttpClientError::MlsStatusCode(status) = &e
                    && (400..500).contains(status)
                {
                    tracing::error!("Failed to get group info: {:?}, stopping retry", status);
                    return Err(e.into());
                }
                return Err(e.into());
            }
        };

        if !SUPPORTED_GROUP_INFO_VERSIONS.contains(&ratchet_tree_and_group_info.version) {
            let mut state = self.state.lock().await;
            state.set_mls_group_state(MlsGroupState::ServerVersionNotSupported);
            return Err(MeetCoreError::MlsServerVersionNotSupported);
        }

        let ratchet_tree = if let RatchetTreeOption::Full { ratchet_tree } =
            &ratchet_tree_and_group_info.data.ratchet_tree
        {
            ratchet_tree
        } else {
            return Err(MeetCoreError::RatchetTreeNotFound);
        };

        let group_info = if let MlsMessageContent::GroupInfo(group_info) =
            ratchet_tree_and_group_info.data.group_info.content
        {
            group_info
        } else {
            return Err(MeetCoreError::UnExpectedMlsMessageContent {
                content_type: ratchet_tree_and_group_info
                    .data
                    .group_info
                    .content
                    .content_type()
                    .map(|c| c.to_string()),
            });
        };

        tracing::info!("Joining MLS join");
        let member_count = ratchet_tree
            .iter()
            .filter_map(|slot| slot.as_ref())
            .filter_map(|node| node.as_leaf_node())
            .count() as u32;
        let ratchet_tree_option = ratchet_tree_and_group_info.data.ratchet_tree;
        if switch_join_type && member_count >= crate::JOIN_TYPE_SWITCH_THRESHOLD {
            let proposal_message = self
                .mls_service
                .create_proposal_to_join_group(
                    &user_info_token.user_id(),
                    group_info,
                    ratchet_tree_option.clone(),
                )
                .await?;
            self.mls_api
                .join_group_by_proposal(&base64_sd_kbt, &proposal_message)
                .await?;

            {
                let mut state = self.state.lock().await;
                state.set_mls_group_state(MlsGroupState::WaitingForJoinProposalWelcome);
            }
            tracing::info!(
                "[WS-HANG] join (external proposal): proposal sent, waiting for welcome (holds user_service.read())"
            );

            let join_deadline = Duration::from_secs(JOIN_PROPOSAL_TIMEOUT);
            let start_time = instant::now();

            loop {
                let welcome_notify = self.join_proposal_welcome_notify.notified();
                {
                    let state = self.state.lock().await;
                    if state.mls_group_state == MlsGroupState::Success {
                        break;
                    }
                    if state.mls_group_state == MlsGroupState::WaitingForJoinProposalWelcome {
                        if let Some(welcome_info) = state.get_welcome_info() {
                            drop(state);
                            self.mls_service
                                .join_group_via_welcome(
                                    &user_info_token.user_id(),
                                    meeting_link_name,
                                    welcome_info,
                                )
                                .await
                                .map_err(|e| {
                                    tracing::warn!(
                                        "Failed to join group with welcome info: {:?}",
                                        e
                                    );
                                    MeetCoreError::RoomJoinFailed {
                                        room_id: meeting_link_name.as_str().to_string(),
                                        reason: "Failed to join group with welcome info"
                                            .to_string(),
                                    }
                                })?;
                            let mut state = self.state.lock().await;
                            state.set_mls_group_state(MlsGroupState::Success);
                            state.set_welcome_info(None);
                            tracing::info!("Join group with welcome info successfully");
                            break;
                        }
                    } else {
                        tracing::warn!(
                            "Join proposal state is not valid: {:?}",
                            state.mls_group_state
                        );
                        return Err(MeetCoreError::RoomJoinFailed {
                            room_id: meeting_link_name.to_string(),
                            reason: "Join proposal state is not valid".to_string(),
                        });
                    }
                }

                let elapsed = start_time.elapsed();
                if elapsed >= join_deadline {
                    return Err(MeetCoreError::RoomJoinFailed {
                        room_id: meeting_link_name.to_string(),
                        reason: "Join proposal timeout, didn't receive the welcome message from the server, please try again"
                            .to_string(),
                    });
                }
                let remaining = join_deadline.saturating_sub(elapsed);
                if timeout(remaining, welcome_notify).await.is_err() {
                    return Err(MeetCoreError::RoomJoinFailed {
                        room_id: meeting_link_name.to_string(),
                        reason: "Join proposal timeout, didn't receive the welcome message from the server, please try again"
                            .to_string(),
                    });
                }
            }
            Ok(())
        } else {
            tracing::info!(
                "[WS-HANG] join (external commit): building commit via join_group_via_external_commit"
            );
            let (group_info_message, ratchet_tree_option, commit_info) = self
                .mls_service
                .join_group_via_external_commit(
                    meeting_link_name,
                    &user_info_token.user_id(),
                    group_info,
                    ratchet_tree_option.clone(),
                )
                .await?;
            tracing::info!(
                "[WS-HANG] join (external commit): commit built, calling update_group_info (HTTP)"
            );
            self.mls_api
                .update_group_info(
                    &base64_sd_kbt,
                    &group_info_message,
                    &ratchet_tree_option,
                    Some(&commit_info),
                    None,
                )
                .await?;
            tracing::info!(
                "[WS-HANG] join (external commit): update_group_info done, setting state=Success"
            );
            {
                let mut state = self.state.lock().await;
                state.set_mls_group_state(MlsGroupState::Success);
            }

            Ok(())
        }
    }
}
