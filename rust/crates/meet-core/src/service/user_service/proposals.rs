use std::{cmp::Ordering, collections::HashSet, str::FromStr, time::Duration};

use crate::{
    domain::user::{
        models::{UserId, UserTokenInfo},
        ports::UserService,
    },
    errors::service::ServiceError,
    infra::mimi_subject_parser::MimiSubject,
    service::{
        service_state::MlsGroupState,
        user_service::{
            credential_is_agent, psk_id_for_commit, utils::group_has_agent, GroupKeyUpdateReason,
            ProposalType, QueuedProposal, Service,
        },
        utils::{convert_mls_spec_to_types, convert_mls_types_to_spec},
    },
    utils::{sleep, spawn_detached},
};
use identity::Disclosure;
use meet_identifiers::AsOwned;
use meet_type::fanout::{MlsCommitInfo, MlsProposalInfo};
use mls_rs::{
    framing::{Content, MlsMessagePayload},
    group::proposal::{Proposal, ProposalOrRef},
};
use mls_spec::{
    defs::ProtocolVersion,
    drafts::ratchet_tree_options::RatchetTreeOption,
    group::group_info::GroupInfo,
    messages::{ContentTypeInner, MlsMessage, MlsMessageContent},
};
use mls_trait::{
    meet_policy::UserRole, types::ReceivedMessage, AuthorizerExt, MlsGroupTrait, ProposalArg,
    ProtonMeetIdentityProvider,
};
use proton_meet_mls::{kv::MemKv, CipherSuite, MlsClientTrait, MlsGroup};

impl Service {
    pub(super) async fn handle_batched_proposals(
        &self,
        room_id: &str,
        queued_proposals: Vec<QueuedProposal>,
        mls_rank_group: u64,
    ) -> Result<(), anyhow::Error> {
        if queued_proposals.is_empty() {
            return Ok(());
        }

        let mls_group_lock = {
            let store_lock = self.mls_store.read().await;
            store_lock
                .group_map
                .get(room_id)
                .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
                .clone()
        };
        let mut mls_group = mls_group_lock.write().await;

        // separate add and remove proposals
        let mut add_proposals = Vec::new();
        let mut remove_proposals = Vec::new();
        let mut app_data_update_proposals = Vec::new();

        // prepare indices for remove proposal validation
        let own_leaf_index = *mls_group.own_leaf_index()?;
        let all_leaf_indices: Vec<u32> = mls_group
            .roster()
            .map(|member| *member.leaf_index())
            .collect();

        for queued_proposal in &queued_proposals {
            let result = mls_group
                .decrypt_message(queued_proposal.proposal_message.clone())
                .await;

            let is_ok = match &result {
                Ok((ReceivedMessage::Proposal, _)) => true,
                Ok((ReceivedMessage::Duplicate, _)) => {
                    #[cfg(debug_assertions)]
                    tracing::warn!("Received duplicate proposal in batched processing");
                    false
                }
                Ok((_received, _)) => {
                    #[cfg(debug_assertions)]
                    tracing::error!(
                        "Unexpected message type in batched proposal processing: {:?}",
                        _received
                    );
                    false
                }
                Err(e) => {
                    tracing::warn!("Failed to decrypt proposal in batched processing: {:?}", e);
                    false
                }
            };

            if is_ok {
                match queued_proposal.proposal_type {
                    ProposalType::AppDataUpdate => app_data_update_proposals.push(queued_proposal),
                    ProposalType::Add => add_proposals.push(queued_proposal),
                    ProposalType::Remove => {
                        // validate remove proposal
                        let proposal = match queued_proposal.proposal_message.clone().as_proposal()
                        {
                            Some(p) => {
                                let mls_types_proposal: mls_types::Proposal =
                                    p.clone().try_into()?;
                                mls_types_proposal
                            }
                            None => continue,
                        };

                        // get the remove leaf node index of the proposal
                        let remove_leaf_node_index = match &proposal.to_remove_index() {
                            Some(index) => *index,
                            None => continue,
                        };

                        // check if this client is the smallest leaf node, which is responsible to be commit
                        if own_leaf_index == remove_leaf_node_index {
                            #[cfg(debug_assertions)]
                            tracing::info!("This client is the node we want to remove, skip");
                            continue;
                        }

                        // check if this node is already removed
                        if !all_leaf_indices.contains(&remove_leaf_node_index) {
                            #[cfg(debug_assertions)]
                            tracing::info!("The node is removed from mls group, skip");
                            continue;
                        }

                        remove_proposals.push(queued_proposal);
                    }
                }
            }
        }

        // combine all proposals
        let all_proposals: Vec<_> = add_proposals
            .into_iter()
            .chain(remove_proposals)
            .chain(app_data_update_proposals)
            .collect();

        #[cfg(debug_assertions)]
        tracing::info!(
            "Processing {} batched proposals. epoch: {:?}, roster: {:?}",
            all_proposals.len(),
            mls_group.epoch(),
            mls_group.roster().count()
        );

        let mut proposal_infos = vec![];
        for queued_proposal in &all_proposals {
            match convert_mls_types_to_spec(&queued_proposal.proposal_message) {
                Ok(proposal) => {
                    let proposal_info = MlsProposalInfo {
                        room_id: room_id.as_bytes().to_vec(),
                        proposal,
                    };
                    proposal_infos.push(proposal_info);
                }
                Err(e) => {
                    tracing::warn!(
                        "Failed to convert proposal to spec for room {}: {:?}",
                        room_id,
                        e
                    );
                    continue;
                }
            }
        }

        if proposal_infos.is_empty() {
            tracing::info!("No valid proposals to process after filtering");
            return Ok(());
        }

        let roster = mls_group.all_device_ids().collect::<HashSet<_>>();
        let mut added_user_identifiers = HashSet::new();
        let mut agent_user_identifiers = HashSet::new();

        for proposal_info in &proposal_infos {
            // Extract Add proposal from nested structure
            let MlsMessageContent::MlsPublicMessage(message) = &proposal_info.proposal.content
            else {
                continue;
            };

            let ContentTypeInner::Proposal {
                proposal: mls_spec::group::proposals::Proposal::Add(add_proposal),
            } = &message.content.content
            else {
                continue;
            };

            // Convert key package and extract device ID
            let Ok(kp) = mls_types::KeyPackage::try_from(add_proposal.key_package.clone()) else {
                tracing::warn!("Failed to convert key package to mls_types for proposal");
                continue;
            };

            let Ok(mut cred) = kp.credential() else {
                tracing::warn!("Failed to extract credential from key package");
                continue;
            };

            let Ok(device_id) = cred.device_id() else {
                tracing::warn!("Failed to extract device_id from credential");
                continue;
            };

            // Skip if device is already in roster
            if roster.contains(&device_id) {
                continue;
            }

            let owning_identity_id = device_id.owning_identity_id().as_owned();
            if credential_is_agent(&cred) {
                agent_user_identifiers.insert(owning_identity_id.clone());
            }
            added_user_identifiers.insert(owning_identity_id);
        }
        let mut role_proposals = Vec::with_capacity(added_user_identifiers.len());
        let participant_list: HashSet<_> = mls_group
            .participant_list()?
            .map(|l| l.participants.into_iter().map(|p| p.user).collect())
            .unwrap_or_default();
        let epoch = *mls_group.epoch();
        for user_identifier in added_user_identifiers {
            let identifier = ProtonMeetIdentityProvider::user_identifier(&user_identifier);
            if participant_list.contains(&identifier) {
                #[cfg(debug_assertions)]
                tracing::debug!("Skipped adding existing user identifier: {:?}", &identifier);
                continue;
            }
            let role = if agent_user_identifiers.contains(&user_identifier) {
                UserRole::Agent
            } else {
                UserRole::Member
            };
            let Some(role_update) = mls_group
                .authorizer()?
                .role_proposal_for_added_user(epoch, identifier, role)?
                .map(|component| ProposalArg::UpdateComponent {
                    id: component.component_id,
                    data: component.data,
                })
            else {
                tracing::error!(
                    "Failed to compute role for user identifier: {:?}",
                    user_identifier
                );
                continue;
            };
            role_proposals.push(role_update);
        }

        role_proposals.push(ProposalArg::PskExternal {
            id: psk_id_for_commit(room_id, group_has_agent(&mls_group)),
        });

        // process all proposals in the same commit
        let (commit_bundle, ..) = mls_group.new_commit(role_proposals).await?;

        let own_device_id = mls_group.own_device_id()?;
        let mimi_subject = MimiSubject::from_str(own_device_id.to_string().as_str())?;
        let user_token_info = UserTokenInfo {
            user_identifier: mls_group.own_user_id()?,
            device_id: mimi_subject.device_id().to_string(),
        };

        // Update group info to the server
        let group_info = commit_bundle
            .group_info
            .ok_or_else(|| anyhow::anyhow!("Expected commit to have a GroupInfo"))?;
        let group_info_message = convert_mls_types_to_spec(&group_info)?;
        let ratchet_tree_option = commit_bundle
            .ratchet_tree
            .ok_or_else(|| anyhow::anyhow!("Expected commit to have a RatchetTree"))?
            .try_into()
            .map_err(|e| anyhow::anyhow!("Failed to convert ratchet tree: {e}"))?;

        let base64_sd_kbt = self.get_sd_kbt(&user_token_info.user_id()).await?;

        let welcome = commit_bundle.welcome.map(TryInto::try_into).transpose()?;

        let commit_info = MlsCommitInfo {
            room_id: room_id.as_bytes().to_vec(),
            welcome_message: welcome,
            commit: convert_mls_types_to_spec(&commit_bundle.commit)?,
        };

        let result = self
            .mls_api
            .update_group_info(
                &base64_sd_kbt,
                &group_info_message,
                &ratchet_tree_option,
                Some(&commit_info),
                Some(proposal_infos),
            )
            .await;

        match result {
            Ok(_) => {
                #[cfg(debug_assertions)]
                tracing::info!("Update group info success for batched proposals");
            }
            Err(e) => {
                tracing::info!("Update group info failed: {:?}", e);
                // Clean up the stored group's state so MemKv stays consistent
                mls_group.clear_pending_commit();
                mls_group.clear_pending_proposals();
                mls_group.write_to_storage().await?;
                return Err(e.into());
            }
        }

        let old_epoch = *mls_group.epoch();
        mls_group.merge_pending_commit().await?;
        let new_epoch = *mls_group.epoch();
        tracing::info!(
            "After handle batched proposals. epoch: {:?}, roster: {:?}",
            new_epoch,
            mls_group.roster().count()
        );

        let new_epoch_u32 = new_epoch as u32;

        drop(mls_group);

        // Check if epoch advanced and update host role if needed
        if new_epoch > old_epoch {
            if let Err(e) = self.check_and_update_host_role(room_id).await {
                tracing::warn!(
                    "Failed to check and update host role after batched proposals epoch change: {:?}",
                    e
                );
                // Don't fail the operation if role update fails
            }
        }

        // update the designated committer metrics
        {
            let mut state = self.state.lock().await;
            state.set_mls_designated_committer_metrics(new_epoch_u32, true, mls_rank_group);
        }
        // trigger the mls group update handler to update the meeting room key
        let key_update_reason = {
            let has_add = all_proposals
                .iter()
                .any(|p| matches!(p.proposal_type, ProposalType::Add));
            let has_remove = all_proposals
                .iter()
                .any(|p| matches!(p.proposal_type, ProposalType::Remove));
            match (has_add, has_remove) {
                (true, true) => GroupKeyUpdateReason::Mixed,
                (true, false) => GroupKeyUpdateReason::Join,
                (false, true) => GroupKeyUpdateReason::Leave,
                _ => GroupKeyUpdateReason::Unknown,
            }
        };
        if let Some(handler) = self.mls_group_update_handler.as_ref() {
            let mut handler = handler.lock().await;
            handler(room_id.to_string(), key_update_reason).await;
        }
        Ok(())
    }

    pub(super) fn start_proposal_timer(
        self,
        room_id: String,
        delay_ms: u64,
        epoch_at: u64,
        mls_rank_group: u64,
    ) {
        const BASE_PROPOSAL_DELAY_MS: u64 = 2000; // execute propsoal every 2s
        let service_clone = self.clone();
        let room_id_clone = room_id.clone();

        spawn_detached(async move {
            // Check if there's already a timer for this room_id and epoch_at
            {
                let mut timer_map = service_clone.proposal_timer.lock().await;
                if let Some(existing_epoch_at) = timer_map.get(&room_id_clone) {
                    if *existing_epoch_at == epoch_at {
                        tracing::debug!(
                            "Proposal timer for room {} with epoch {} already exists, skipping",
                            room_id_clone,
                            epoch_at
                        );
                        return;
                    }
                }
                // Register this timer
                timer_map.insert(room_id_clone.clone(), epoch_at);
            }
            tracing::debug!(
                "Proposal timer for room {}: starting timer with delay {}ms for epoch {}",
                room_id_clone,
                delay_ms + BASE_PROPOSAL_DELAY_MS,
                epoch_at
            );

            // Wait for the timer to complete
            sleep(Duration::from_millis(delay_ms + BASE_PROPOSAL_DELAY_MS)).await;

            tracing::debug!(
                "Proposal timer for room {}: timer completed, processing proposals for epoch {}",
                room_id_clone,
                epoch_at
            );

            // Remove timer from map when it completes
            {
                let mut timer_map = service_clone.proposal_timer.lock().await;
                // Only remove if it's still the same epoch_at (in case epoch changed)
                if let Some(&stored_epoch_at) = timer_map.get(&room_id_clone) {
                    if stored_epoch_at == epoch_at {
                        timer_map.remove(&room_id_clone);
                    }
                }
            }

            let state = service_clone.state.lock().await;
            let mls_state_ok = state.mls_group_state == MlsGroupState::Success;
            drop(state);
            if !mls_state_ok {
                tracing::debug!(
                    "Proposal timer for room {}: mls group state is not Success, skipping",
                    room_id_clone
                );
                return;
            }

            // Check if epoch has changed, skip if not equal
            match service_clone.get_current_epoch(&room_id_clone).await {
                Ok(current_epoch) => {
                    if current_epoch != epoch_at {
                        #[cfg(debug_assertions)]
                        tracing::info!(
                            "Proposal timer for room {}: epoch changed from {} to {}, skipping",
                            room_id_clone,
                            epoch_at,
                            current_epoch
                        );
                        return;
                    }
                }
                Err(_e) => {
                    #[cfg(debug_assertions)]
                    tracing::warn!(
                        "Proposal timer for room {}: failed to get current epoch: {:?}, skipping",
                        room_id_clone,
                        _e
                    );
                    return;
                }
            }

            let room_processing_lock = service_clone.room_processing_lock(&room_id_clone).await;
            let _room_processing_guard = room_processing_lock.lock().await;

            // Swap queue: take proposals out first to minimize lock time
            let queued_proposals = {
                let mut queue_lock = service_clone.proposal_queue.lock().await;
                queue_lock.remove(&room_id_clone).unwrap_or_else(Vec::new)
            };

            if let Err(e) = service_clone
                .handle_batched_proposals(&room_id_clone, queued_proposals.clone(), mls_rank_group)
                .await
            {
                tracing::warn!("Batched proposal timer: {:?}", e);
                if let Ok(current_epoch) = service_clone.get_current_epoch(&room_id_clone).await {
                    // Restore proposals on error
                    let filtered_queued_proposals =
                        service_clone.filter_queued_proposals(current_epoch, queued_proposals);
                    if !filtered_queued_proposals.is_empty() {
                        crate::service::utils::restore_to_queue_sync(
                            service_clone.proposal_queue.clone(),
                            room_id_clone.clone(),
                            filtered_queued_proposals,
                            "Batched proposal timer failed",
                        )
                        .await;
                    }
                }
            }
        });
    }

    /// Filters out stale proposals that are from epochs older than the current epoch.
    /// Only keeps proposals that are still valid (from current epoch or future epochs).
    pub(super) fn filter_queued_proposals(
        &self,
        current_epoch: u64,
        queued_proposals: Vec<QueuedProposal>,
    ) -> Vec<QueuedProposal> {
        queued_proposals
            .into_iter()
            .filter(|proposal| {
                let proposal_epoch = proposal.proposal_message.epoch().unwrap_or(0);
                proposal_epoch >= current_epoch
            })
            .collect()
    }

    pub(super) async fn restore_proposal_queue_on_failure(
        &self,
        room_id: &str,
        queued_proposals: &mut Vec<QueuedProposal>,
        error_context: &str,
    ) {
        crate::service::utils::restore_to_queue_sync(
            self.proposal_queue.clone(),
            room_id.to_string(),
            std::mem::take(queued_proposals),
            error_context,
        )
        .await;
    }

    /// Validate the PSK proposal in the incoming commit message.
    /// If the MLS message is a commit message, validate the PSK proposal in the commit message.
    /// It must reference either the meeting PSK (id = `room_id.as_bytes()`)
    /// or the meeting-scoped agent PSK (id = `agent-psk-id.{room_id}`).
    pub(super) fn validate_psk_proposal(
        mls_message: mls_types::MlsMessage,
        room_id: &str,
    ) -> Result<(), anyhow::Error> {
        use crate::service::agent_host_service::agent_psk_id_for_meeting;
        let expected_agent_id = agent_psk_id_for_meeting(room_id);
        if let MlsMessagePayload::Plain(public_message) = mls_message.mls_message.payload {
            if let Content::Commit(commit) = public_message.content.content {
                let proposals = commit.proposals;
                let mut has_psk = false;
                for proposal in proposals {
                    if let ProposalOrRef::Proposal(proposal) = proposal {
                        if let Proposal::Psk(psk) = proposal.as_ref() {
                            if let Some(psk_id) = psk.external_psk_id() {
                                has_psk = true;
                                let id_bytes = psk_id.to_vec();
                                if id_bytes != room_id.as_bytes()
                                    && id_bytes.as_slice() != expected_agent_id.as_slice()
                                {
                                    tracing::error!("PSK ID mismatch for room {room_id}");
                                    return Err(anyhow::Error::from(
                                        ServiceError::PskProposalMissing,
                                    ));
                                }
                            }
                        }
                    }
                }
                if !has_psk {
                    tracing::error!("PSK proposal missing for room {room_id}");
                    return Err(anyhow::Error::from(ServiceError::PskProposalMissing));
                }
            }
        }
        Ok(())
    }

    pub(super) async fn create_external_proposal_impl(
        &self,
        participant_id: &UserId,
        cs: CipherSuite,
        group_info: GroupInfo,
        ratchet_tree_option: RatchetTreeOption,
    ) -> Result<mls_types::MlsMessage, anyhow::Error> {
        let mls_store = self.mls_store.read().await;
        let client = mls_store.find_client(&participant_id.to_string(), &cs)?;

        let app_message = MlsMessage {
            version: ProtocolVersion::Mls10,
            content: MlsMessageContent::GroupInfo(group_info),
        };

        let gi_mls_message = convert_mls_spec_to_types(&app_message)?;

        let ratchet_tree = ratchet_tree_option.try_into().map_err(|e| {
            anyhow::anyhow!("Failed to convert ratchet tree option to mls_types::RatchetTree: {e}")
        })?;

        let mls_message = client
            .join_via_external_proposal(
                gi_mls_message,
                ratchet_tree,
                Disclosure::Full,
                self.server_time_tracker.server_time_as_duration(),
            )
            .await?;

        Ok(mls_message)
    }

    pub(super) async fn create_leave_proposal_impl(
        &self,
        participant_id: &UserId,
        mls_group: &mut MlsGroup<MemKv>,
        cs: CipherSuite,
    ) -> Result<mls_types::MlsMessage, anyhow::Error> {
        let mls_store = self.mls_store.read().await;
        let _client = mls_store.find_client(&participant_id.to_string(), &cs)?;

        let leaf = mls_group.own_leaf_index()?;

        // create self remove proposal
        let mut p = mls_group.new_proposals([ProposalArg::Remove(leaf)]).await?;
        let remove_proposal = p.remove(0);

        Ok(remove_proposal)
    }

    pub(super) async fn create_self_remove_participant_update_proposal_impl(
        &self,
        mls_group: &mut MlsGroup<MemKv>,
    ) -> Result<Option<mls_types::MlsMessage>, anyhow::Error> {
        let authorizer = mls_group.authorizer()?;
        let leaf = mls_group.own_leaf_index()?;
        let mut member = mls_group.find_member(leaf)?;
        let current_user_id = member.user_id()?;
        let identity = ProtonMeetIdentityProvider::user_identifier(&current_user_id);
        let active_participants = mls_group
            .all_device_ids()
            .map(|d| ProtonMeetIdentityProvider::user_identifier_ref(d.owning_identity_id()))
            .collect::<HashSet<_>>();
        let participant_update = match authorizer.participant_update_for_removed_user(
            *mls_group.epoch(),
            &identity,
            &active_participants,
        ) {
            Ok(Some(participant_update)) => participant_update,
            Ok(None) => return Ok(None),
            Err(e) => {
                tracing::error!("Failed to create participant update: {:?}", e);
                return Err(anyhow::anyhow!(
                    "Failed to create participant update: {e:?}"
                ));
            }
        };

        let proposal_args = vec![ProposalArg::update_component(&participant_update)?];
        let mut p = mls_group.new_proposals(proposal_args).await?;
        let proposal = p.remove(0);

        Ok(Some(proposal))
    }

    pub(super) async fn handle_proposal_impl(
        &self,
        room_id: &str,
        proposal: mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error> {
        let epoch_of_proposal = proposal
            .epoch()
            .ok_or(anyhow::anyhow!("Expected proposal to have an epoch"))?;

        let mls_group_epoch = self.get_current_epoch(room_id).await?;

        match epoch_of_proposal.cmp(&mls_group_epoch) {
            Ordering::Less => {
                // check if the proposal is an external add proposal, so we can recreate the proposal
                // and send to server to broadcast to all other clients
                let _ = match proposal.clone().as_proposal() {
                    Some(p) => {
                        let mls_types_proposal: mls_types::Proposal = p.clone().try_into()?;
                        mls_types_proposal
                    }
                    None => {
                        tracing::info!("Received proposal message with old epoch. proposal epoch: {epoch_of_proposal:?}, group epoch: {mls_group_epoch:?}",);
                        return Err(ServiceError::OldEpochProposal.into());
                    }
                };
                {
                    tracing::info!("Received proposal message with old epoch. proposal epoch: {epoch_of_proposal:?}, group epoch: {mls_group_epoch:?}",);
                    return Err(ServiceError::OldEpochProposal.into());
                }
            }
            Ordering::Equal => {}
            Ordering::Greater => {
                tracing::info!("Received proposal message with future epoch. proposal epoch: {:?}, group epoch: {:?}", epoch_of_proposal, mls_group_epoch);
                self.cache_proposal_message(room_id, proposal).await?;
                return Err(ServiceError::FutureEpochProposal.into());
            }
        }

        // Re-acquire locks for message processing
        let store = self.mls_store.read().await;
        let mut mls_group = store
            .group_map
            .get(room_id)
            .ok_or(anyhow::anyhow!(
                "Failed to find mls group for room {room_id}"
            ))?
            .write()
            .await;

        let (received_message, _) = mls_group.decrypt_message(proposal).await?;
        match received_message {
            ReceivedMessage::Proposal => {
                tracing::debug!(
                    "Received proposal is processed. epoch: {:?}",
                    epoch_of_proposal
                );
            }
            ReceivedMessage::Duplicate => {
                #[cfg(debug_assertions)]
                tracing::warn!("Received duplicate message");
            }
            _ => {
                #[cfg(debug_assertions)]
                tracing::error!("Received message is not a proposal: {:?}", received_message);
                return Err(ServiceError::ProposalDecryptionFailed.into());
            }
        }

        Ok(())
    }
}
