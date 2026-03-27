use std::{
    cmp::Ordering,
    collections::{HashMap, HashSet},
    future::Future,
    str::FromStr,
    sync::Arc,
    time::Duration,
};

use crate::{
    domain::user::ports::ArcWebSocketClient,
    infra::crypto_client::derive_external_psk,
    service::service_state::MlsSyncState,
    utils::{instant, spawn, spawn_detached},
};
use crate::{infra::dto::realtime::VersionedGroupInfoData, utils::join};
use base64::{engine::general_purpose, Engine};
use ed25519_dalek::pkcs8::DecodePublicKey;
use meet_mls::reexports::meet_policy::UserRole;
use meet_type::RejoinReason;
use mls_rs::{
    framing::{Content, FramedContent, MlsMessagePayload},
    group::proposal::{Proposal, ProposalOrRef},
};
use mls_rs_codec::MlsEncode;
use mls_spec::{
    defs::ProtocolVersion,
    drafts::ratchet_tree_options::RatchetTreeOption,
    group::group_info::GroupInfo,
    messages::{ContentTypeInner, MlsMessage, MlsMessageContent},
    Parsable, Serializable,
};
use mls_trait::{types::ReceivedMessage, AuthorizerExt, ProposalArg, ProtonMeetIdentityProvider};
use mls_types::{ContentType, ExternalPskId, MediaType, Member};
use proton_claims::reexports::{cose_key_set::CoseKeySet, CwtAny};
use proton_meet_common::models::{ProtonUser, ProtonUserKey};
use proton_meet_macro::async_trait;
use proton_meet_mls::{
    kv::MemKv, CipherSuite, CommitBundle, MlsClient, MlsClientConfig, MlsClientTrait, MlsGroup,
    MlsGroupConfig, MlsGroupTrait, MlsStore,
};
use rand::seq::SliceRandom;
use rand::{Rng, SeedableRng};
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, RwLock};
use uuid::Uuid;

#[cfg(not(target_family = "wasm"))]
use tokio::time::sleep;
#[cfg(target_family = "wasm")]
use wasmtimer::tokio::sleep;

//TODO:(fix) the whole file need to be refactored, there are too many code duplication and not enough abstraction
use crate::{
    domain::user::{
        models::{user_settings::UserSettings, Address, UserId, UserTokenInfo},
        ports::{user_api::UserApi, ArcUserRepository, ConnectionState, HttpClient, UserService},
    },
    errors::{
        core::MeetCoreError, http_client::HttpClientError, login::LoginError, service::ServiceError,
    },
    infra::{
        dto::{
            proton_user::UserData,
            realtime::{
                ConnectionLostType, GroupInfoVersion, JoinRoomResponse, LeaveRoomMessage,
                MlsCommitInfo, MlsProposalInfo, RTCMessageIn, RTCMessageInContent,
            },
            websocket::{ClientAck, WebSocketTextRequestCommand},
        },
        message_cache::{CachedMessageType, MlsMessageCache},
        mimi_subject_parser::MimiSubject,
        ws_client::{self, WebSocketMessage},
    },
    service::{
        service_state::{MlsGroupState, ServiceState},
        utils::{
            convert_mls_spec_to_types, convert_mls_types_to_spec, describe_proposal_kind,
            get_uuid_from_member,
        },
    },
};

use identity::{Disclosure, PresentationContext, ProtonMeetIdentity, SdCwt};
use meet_identifiers::{AsOwned, Domain, GroupId, Id, LeafIndex};

const DELAY_PER_RANK_MS: u64 = 100;
const RANK_GROUP_SIZE: u64 = 3;
const RANK_GROUP_DELAY_MS: u64 = 5000;

// Kick participant retry configuration
const KICK_MAX_ATTEMPTS: u32 = 4; // 1 initial + 3 retries
const KICK_BASE_DELAY_MS: u64 = 500;
const KICK_MAX_DELAY_MS: u64 = 10000;

/// Message wrapper received from server (must match server-side struct)
#[derive(Debug, Clone, Serialize, Deserialize)]
struct MessageWithId {
    #[serde(with = "uuid::serde::compact")]
    id: Uuid,
    #[serde(with = "serde_bytes")]
    payload: Vec<u8>,
}

/// Queued proposal waiting to be processed in batch
#[derive(Clone)]
pub(crate) struct QueuedProposal {
    proposal_message: mls_types::MlsMessage,
    proposal_type: ProposalType,
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum ProposalType {
    Add,
    Remove,
    AppDataUpdate,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CommitProcessingOutcome {
    Applied,
    DeferredFutureEpoch,
    NoStateChange,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum ProposalProcessingOutcome {
    Applied,
    DeferredFutureEpoch,
    NoStateChange,
}

#[cfg(not(target_family = "wasm"))]
pub type MlsGroupUpdateHandler =
    Box<dyn FnMut(String) -> Box<dyn Future<Output = ()> + Unpin + Send> + Send + 'static>;

#[cfg(target_family = "wasm")]
pub type MlsGroupUpdateHandler =
    Box<dyn FnMut(String) -> Box<dyn Future<Output = ()> + Unpin> + 'static>;

#[cfg(not(target_family = "wasm"))]
pub type LiveKitAdminChangeHandler = Box<
    dyn FnMut(String, String, u32) -> Box<dyn Future<Output = ()> + Unpin + Send> + Send + 'static,
>;

#[cfg(target_family = "wasm")]
pub type LiveKitAdminChangeHandler =
    Box<dyn FnMut(String, String, u32) -> Box<dyn Future<Output = ()> + Unpin> + 'static>;

#[cfg(not(target_family = "wasm"))]
pub type MlsSyncStateUpdateHandler = Box<
    dyn FnMut(MlsSyncState, Option<RejoinReason>) -> Box<dyn Future<Output = ()> + Unpin + Send>
        + Send
        + 'static,
>;

#[cfg(target_family = "wasm")]
pub type MlsSyncStateUpdateHandler = Box<
    dyn FnMut(MlsSyncState, Option<RejoinReason>) -> Box<dyn Future<Output = ()> + Unpin> + 'static,
>;

#[derive(Clone)]
pub struct Service {
    http_client: Arc<dyn HttpClient>,
    user_api: Arc<dyn UserApi>,
    user_repository: ArcUserRepository,
    mls_group_update_handler: Option<Arc<Mutex<MlsGroupUpdateHandler>>>,
    livekit_admin_change_handler: Option<Arc<Mutex<LiveKitAdminChangeHandler>>>,
    mls_sync_state_update_handler: Option<Arc<Mutex<MlsSyncStateUpdateHandler>>>,
    ws_client: ArcWebSocketClient,
    mls_store: Arc<RwLock<MlsStore>>,
    state: Arc<Mutex<ServiceState>>,
    message_cache: Arc<Mutex<MlsMessageCache>>,
    proposal_queue: Arc<Mutex<HashMap<String, Vec<QueuedProposal>>>>,
    proposal_timer: Arc<Mutex<HashMap<String, u64>>>, // room_id -> epoch_at
    // MLS message service for processing commits and proposals
    mls_service: Arc<crate::domain::mls::mls_message_service::MlsMessageService>,
    handling_offline_members: Arc<Mutex<bool>>,
    use_psk: Arc<Mutex<bool>>,
}

/// Calculate retry delay with exponential backoff and jitter
/// - attempt_num: 0-indexed attempt number (0 = first retry after initial failure)
/// - base_ms: base delay in milliseconds
/// - max_ms: maximum delay cap
fn calculate_retry_delay(attempt_num: u32, base_ms: u64, max_ms: u64) -> u64 {
    use rand::Rng;

    // Exponential backoff: base * 2^attempt_num
    let exponential_delay = base_ms.saturating_mul(1u64 << attempt_num);
    let capped_delay = exponential_delay.min(max_ms);

    // Add jitter: ±10%
    let jitter_range = (capped_delay as f64 * 0.1) as u64;
    let jitter = rand::thread_rng().gen_range(0..=jitter_range * 2);

    capped_delay
        .saturating_sub(jitter_range)
        .saturating_add(jitter)
}

/// Restore queued proposals back to the proposal queue on failure
fn restore_proposals_to_queue(
    proposal_queue: &Arc<Mutex<HashMap<String, Vec<QueuedProposal>>>>,
    meeting_link_name: String,
    proposals: Vec<QueuedProposal>,
    reason: &str,
) {
    if proposals.is_empty() {
        return;
    }

    let reason = reason.to_string();
    spawn({
        let queue = proposal_queue.clone();
        async move {
            let mut queue_lock = queue.lock().await;
            queue_lock.insert(meeting_link_name.clone(), proposals);
            tracing::debug!(
                "Restored {} proposals to queue for {}: {}",
                queue_lock
                    .get(&meeting_link_name)
                    .map(|v| v.len())
                    .unwrap_or(0),
                meeting_link_name,
                reason
            );
        }
    });
}

impl Service {
    pub fn new(
        http_client: Arc<dyn HttpClient>,
        user_api: Arc<dyn UserApi>,
        user_repository: ArcUserRepository,
        ws_client: ArcWebSocketClient,
        mls_store: Arc<RwLock<MlsStore>>,
    ) -> Self {
        let state = Arc::new(Mutex::new(ServiceState::new()));
        let message_cache = Arc::new(Mutex::new(MlsMessageCache::new()));

        // Create infrastructure adapters
        let mls_store_adapter = Arc::new(
            crate::infra::adapters::mls::mls_store_adapter::MlsStoreAdapter::new(mls_store.clone()),
        );
        let message_cache_adapter = Arc::new(
            crate::infra::adapters::mls::message_cache_adapter::MessageCacheAdapter::new(
                message_cache.clone(),
            ),
        );
        let state_repository_adapter = Arc::new(
            crate::infra::adapters::mls::state_repository_adapter::StateRepositoryAdapter::new(
                state.clone(),
            ),
        );

        // Create MLS message service
        let mls_service = Arc::new(
            crate::domain::mls::mls_message_service::MlsMessageService::new(
                mls_store_adapter as Arc<dyn crate::domain::mls::ports::MlsStorePort>,
                message_cache_adapter as Arc<dyn crate::domain::mls::ports::MessageCachePort>,
                state_repository_adapter as Arc<dyn crate::domain::mls::ports::StateRepositoryPort>,
            ),
        );

        Self {
            http_client,
            user_api,
            user_repository,
            mls_group_update_handler: None,
            livekit_admin_change_handler: None,
            mls_sync_state_update_handler: None,
            ws_client,
            mls_store,
            state,
            message_cache,
            proposal_queue: Arc::new(Mutex::new(HashMap::new())),
            proposal_timer: Arc::new(Mutex::new(HashMap::new())),
            mls_service,
            handling_offline_members: Arc::new(Mutex::new(false)),
            use_psk: Arc::new(Mutex::new(true)),
        }
    }
}

impl Service {
    /// Generates a unique group id by appending a UUID suffix.
    /// This is used to avoid conflicts when creating MLS groups with the same base name.
    fn generate_unique_group_id(base_name: &str) -> String {
        let uuid_suffix = Uuid::new_v4();
        format!("{base_name}_{uuid_suffix}")
    }

    pub async fn set_livekit_active_uuids(
        &self,
        room_id: &str,
        livekit_active_uuid_list: Vec<String>,
    ) -> Result<(), anyhow::Error> {
        let mut state = self.state.lock().await;
        state.set_livekit_active_uuids(livekit_active_uuid_list);
        drop(state);

        // check if any new offline members need to be handled
        self.handle_offline_members(room_id)
            .await
            .map_err(|e| anyhow::anyhow!("Failed to handle offline members: {e:?}"))?;

        Ok(())
    }

    async fn handle_batched_proposals(
        &self,
        room_id: &str,
        queued_proposals: Vec<QueuedProposal>,
        mls_rank_group: u64,
    ) -> Result<(), anyhow::Error> {
        // lock whole handle_batched_proposals
        let proposal_lock = self.proposal_queue.lock().await;
        if queued_proposals.is_empty() {
            return Ok(());
        }

        // separate add and remove proposals
        let mut add_proposals = Vec::new();
        let mut remove_proposals = Vec::new();
        let mut app_data_update_proposals = Vec::new();

        let mls_group = {
            let mls_group_lock = {
                let store_lock = self.mls_store.read().await;
                store_lock
                    .group_map
                    .get(room_id)
                    .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
                    .clone()
            };
            let mls_group = mls_group_lock.read().await;
            mls_group.clone()
        };

        // prepare indices for remove proposal validation
        let own_leaf_index = *mls_group.own_leaf_index()?;
        let all_leaf_indices: Vec<u32> = mls_group
            .roster()
            .map(|member| *member.leaf_index())
            .collect();

        for queued_proposal in &queued_proposals {
            let result = self
                .handle_proposal(room_id, queued_proposal.proposal_message.clone())
                .await;

            if result.is_ok() {
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

        // get the mls group again to ensure the mls group is up to date
        // since we had handle proposal in the loop, the mls group might be updated
        let mut mls_group = {
            let mls_group_lock = {
                let store_lock = self.mls_store.read().await;
                store_lock
                    .group_map
                    .get(room_id)
                    .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
                    .clone()
            };
            let mls_group = mls_group_lock.read().await;
            mls_group.clone()
        };

        // combine all proposals
        let all_proposals: Vec<_> = add_proposals
            .into_iter()
            .chain(remove_proposals.into_iter())
            .chain(app_data_update_proposals.into_iter())
            .collect();

        #[cfg(debug_assertions)]
        tracing::info!(
            "Processing {} batched proposals. epoch: {:?}, roster: {:?}",
            all_proposals.len(),
            mls_group.epoch(),
            mls_group.roster().count()
        );

        // prepare all proposals for the commit (cached proposals are already added to the group via new_proposals)
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

            added_user_identifiers.insert(device_id.owning_identity_id().as_owned());
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
            let Some(role_update) = mls_group
                .authorizer()?
                .role_proposal_for_added_user(epoch, identifier, UserRole::Member)?
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

        let use_psk = {
            let use_psk_guard = self.use_psk.lock().await;
            *use_psk_guard
        };

        if use_psk {
            role_proposals.push(ProposalArg::PskExternal {
                id: ExternalPskId(room_id.as_bytes().to_vec()),
            });
        }

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
            .http_client
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
                // return error because we cannot update group info correctly
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

        // save the mls group
        self.mls_store
            .write()
            .await
            .group_map
            .entry(room_id.to_string())
            .and_modify(|group| {
                *group = Arc::new(RwLock::new(mls_group));
            });

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
        if let Some(handler) = self.mls_group_update_handler.as_ref() {
            let mut handler = handler.lock().await;
            handler(room_id.to_string()).await;
        }
        drop(proposal_lock);
        Ok(())
    }

    fn start_proposal_timer(
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
                Err(e) => {
                    #[cfg(debug_assertions)]
                    tracing::warn!(
                        "Proposal timer for room {}: failed to get current epoch: {:?}, skipping",
                        room_id_clone,
                        e
                    );
                    return;
                }
            }

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
                        crate::service::utils::restore_to_queue(
                            service_clone.proposal_queue.clone(),
                            room_id_clone.clone(),
                            filtered_queued_proposals,
                            "Batched proposal timer failed",
                        );
                    }
                }
            }
        });
    }

    /// Filters out stale proposals that are from epochs older than the current epoch.
    /// Only keeps proposals that are still valid (from current epoch or future epochs).
    fn filter_queued_proposals(
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

    /// Returns the deterministic rank of `own_leaf_index` in the roster.
    /// The roster is sorted and shuffled using `epoch_at` as seed.
    /// Returns the position of `own_leaf_index` in the shuffled list.
    /// The deterministic rank is used purely for commit scheduling and does not participate in any cryptographic operation or entropy generation.
    /// Returns the deterministic rank of `own_leaf_index` in the roster.
    /// The roster is sorted and shuffled using `epoch_at` as seed.
    /// Returns the position of `own_leaf_index` in the shuffled list.
    /// The deterministic rank is used purely for commit scheduling and does not participate in any cryptographic operation or entropy generation.
    async fn get_deterministic_random_rank(
        &self,
        own_leaf_index: u32,
        epoch_at: u64,
        roster: Vec<Member>,
    ) -> Result<u64, anyhow::Error> {
        // Filter out offline members to avoid scheduling commits for offline members because only host can kickout ungraceful offline members now
        let offline_indices = self.get_offline_indices(roster.clone()).await?;
        let offline_set: HashSet<u32> = offline_indices.iter().copied().collect();
        let mut all_leaf_indices: Vec<u32> = roster
            .iter()
            .map(|m| *m.leaf_index())
            .filter(|index| !offline_set.contains(index))
            .collect();

        all_leaf_indices.sort();
        all_leaf_indices.dedup(); // optional, for safety

        let mut rng = rand::rngs::StdRng::seed_from_u64(epoch_at);
        // shuffle the sorted and deduped leaf indices with the epoch_at as seed, so the rank is deterministic
        all_leaf_indices.shuffle(&mut rng);

        let rank = all_leaf_indices
            .iter()
            .position(|&x| x == own_leaf_index)
            .ok_or_else(|| {
                anyhow::anyhow!("own_leaf_index {own_leaf_index} not found in roster")
            })?;
        Ok(rank as u64)
    }

    /// Get leaf indices of members who have been offline for more than the threshold
    /// Based on the last_seen timestamp in livekit_active_uuid_hashmap and last_livekit_active_uuid_update_time
    pub async fn get_offline_indices(
        &self,
        roster: Vec<Member>,
    ) -> Result<Vec<u32>, anyhow::Error> {
        const OFFLINE_THRESHOLD_MS: u64 = 60_000; // 60 seconds in milliseconds

        let state_lock = self.state.lock().await;
        let livekit_active_uuid_hashmap = state_lock.get_livekit_active_uuid_hashmap();
        let last_livekit_active_uuid_update_time = state_lock.last_livekit_active_uuid_update_time;
        drop(state_lock);

        let offline_indices: Vec<u32> = roster
            .into_iter()
            .filter_map(|mut member| {
                match get_uuid_from_member(&mut member) {
                    Ok(uuid) => {
                        if let Some(uuid_info) = livekit_active_uuid_hashmap.get(&uuid) {
                            // Check if last_seen is older than threshold
                            if last_livekit_active_uuid_update_time
                                .saturating_sub(uuid_info.last_seen)
                                > OFFLINE_THRESHOLD_MS
                            {
                                Some(*member.leaf_index())
                            } else {
                                None
                            }
                        } else {
                            // UUID not in hashmap, ignore
                            None
                        }
                    }
                    Err(_) => None,
                }
            })
            .collect();

        Ok(offline_indices)
    }

    pub async fn get_mls_retry_count(&self) -> u32 {
        let state = self.state.lock().await;
        state.mls_retry_count
    }

    pub async fn get_mls_sync_metrics(
        &self,
    ) -> Option<crate::service::service_state::MlsSyncMetrics> {
        let state = self.state.lock().await;
        state.get_mls_sync_metrics()
    }

    pub async fn get_mls_designated_committer_metrics_at_epoch(
        &self,
        epoch: u32,
    ) -> Option<crate::service::service_state::MLSDesignatedCommitterMetrics> {
        let state = self.state.lock().await;
        state.get_mls_designated_committer_metrics_at_epoch(epoch)
    }

    /// Checks whether the local MLS (Message Layer Security) state for the currently active participant is up-to-date.
    /// Do not call this function too often
    /// Ideally, call it every 5 seconds when the websocket had reconnected;
    /// Otherwise, call it every 30 seconds to avoid too many requests to the server
    ///
    /// # Returns
    /// - `Ok(true)` if the MLS state is up-to-date.
    /// - `Ok(false)` if the MLS state is outdated.
    /// - `Err(MeetCoreError::ParticipantNotFound)` if there is no active participant.
    /// - `Err(MeetCoreError::...)` for other errors from the user service.
    ///
    pub async fn is_mls_up_to_date(
        &self,
        user_identifier: &UserId,
        room_id: &str,
        has_trigger_reconnect: bool,
    ) -> Result<bool, anyhow::Error> {
        let base64_sd_kbt = self.get_sd_kbt(user_identifier).await?;
        let mut retry_count = 0;
        let max_retry_count = 4;
        let retry_delay_ms = 500;
        // delay to check the epoch, to make sure the client can recevie in coming proposals and commits to update to latest status
        let epoch_check_delay_ms = 5000;

        loop {
            if retry_count >= max_retry_count {
                // reached max retries
                let state = if has_trigger_reconnect {
                    MlsSyncState::Failed
                } else {
                    MlsSyncState::Retrying
                };
                // Get reason from metrics if available
                let reason = {
                    let state_lock = self.state.lock().await;
                    state_lock.get_mls_sync_metrics().and_then(|metrics| {
                        metrics.connection_lost_type.map(|lost_type| {
                            Self::connection_lost_type_to_rejoin_reason(&lost_type)
                        })
                    })
                };
                self.set_mls_sync_state_with_callback(state, reason).await;
                return Ok(false);
            }
            {
                self.set_mls_sync_state_with_callback(
                    if has_trigger_reconnect {
                        MlsSyncState::Retrying
                    } else {
                        MlsSyncState::Checking
                    },
                    None,
                )
                .await;
            }

            let local_mls_epoch_before = {
                let mls_group_lock = {
                    let store_lock = self.mls_store.read().await;
                    store_lock
                        .group_map
                        .get(room_id)
                        .ok_or_else(|| {
                            anyhow::anyhow!("Failed to find mls group for room {room_id}")
                        })?
                        .clone()
                };
                let mls_group = mls_group_lock.read().await;
                *mls_group.epoch()
                // mls_group lock release here
            };

            // get the websocket connection state
            let ws_connection_state = self.ws_client.get_connection_state().await;
            let is_websocket_disconnected = ws_connection_state == ConnectionState::Disconnected;
            let has_websocket_reconnected = self.ws_client.get_has_reconnected().await;

            if is_websocket_disconnected {
                tracing::error!("Websocket is disconnected, return false directly");
                // Record metrics before returning
                let mut state = self.state.lock().await;
                state.set_mls_sync_metrics(crate::service::service_state::MlsSyncMetrics {
                    local_epoch: local_mls_epoch_before as u32,
                    server_epoch: 0,
                    is_user_device_in_group_info: false,
                    is_websocket_disconnected,
                    has_websocket_reconnected,
                    is_get_group_info_success: false,
                    connection_lost_type: Some(ConnectionLostType::WebsocketDisconnected),
                });
                drop(state);
                let sync_state = if has_trigger_reconnect {
                    MlsSyncState::Failed
                } else {
                    MlsSyncState::Retrying
                };
                let reason = if matches!(sync_state, MlsSyncState::Failed) {
                    Some(RejoinReason::WebsocketDisconnected)
                } else {
                    None
                };
                self.set_mls_sync_state_with_callback(sync_state, reason)
                    .await;
                return Ok(false);
            }

            // get the group info from the server
            // let group_info_summary = self.ws_client.get_group_info_summary().await;
            let group_info_summary = self
                .http_client
                .get_group_info_summary(&base64_sd_kbt)
                .await;

            // wait for the epoch check delay to make sure the client can recevie in coming proposals and commits to update to latest status
            sleep(Duration::from_millis(epoch_check_delay_ms)).await;
            match group_info_summary {
                Ok(group_info_summary) => {
                    let server_tree_epoch = group_info_summary.epoch;
                    let server_group_id = group_info_summary.group_id;
                    let local_mls_epoch_after = self.get_current_epoch(room_id).await?;
                    let local_group_id = self.get_current_group_id(room_id).await?;
                    let group_id_matches = local_group_id == server_group_id;

                    // since we have latency when getting the group info from the server, we need to check if the local mls epoch is within the range of the server mls epoch
                    if local_mls_epoch_before <= server_tree_epoch
                        && local_mls_epoch_after >= server_tree_epoch
                    {
                        // Record metrics
                        let mut state = self.state.lock().await;
                        state.set_mls_sync_metrics(crate::service::service_state::MlsSyncMetrics {
                            local_epoch: local_mls_epoch_before as u32,
                            server_epoch: server_tree_epoch as u32,
                            is_user_device_in_group_info: group_id_matches,
                            is_websocket_disconnected,
                            has_websocket_reconnected,
                            is_get_group_info_success: true,
                            connection_lost_type: if group_id_matches {
                                None
                            } else {
                                Some(ConnectionLostType::MemberNotFoundInMLS)
                            },
                        });
                        drop(state);
                        if !group_id_matches {
                            let sync_state = if has_trigger_reconnect {
                                MlsSyncState::Failed
                            } else {
                                MlsSyncState::Retrying
                            };
                            let reason = if matches!(sync_state, MlsSyncState::Failed) {
                                Some(RejoinReason::MemberNotFoundInMLS)
                            } else {
                                None
                            };
                            self.set_mls_sync_state_with_callback(sync_state, reason)
                                .await;
                            return Ok(false);
                        }
                        self.set_mls_sync_state_with_callback(MlsSyncState::Success, None)
                            .await;
                        return Ok(true);
                    }

                    // epoch mismatch, record metrics before retry
                    let mut state = self.state.lock().await;
                    state.set_mls_sync_metrics(crate::service::service_state::MlsSyncMetrics {
                        local_epoch: local_mls_epoch_before as u32,
                        server_epoch: server_tree_epoch as u32,
                        is_user_device_in_group_info: false,
                        is_websocket_disconnected,
                        has_websocket_reconnected,
                        is_get_group_info_success: true,
                        connection_lost_type: Some(ConnectionLostType::EpochMismatch),
                    });
                    drop(state);

                    // epoch mismatch, retry
                    retry_count += 1;
                    tracing::warn!(
                        "Epoch check failed (local: {}, server: {}), retry: {}/{}",
                        local_mls_epoch_before,
                        server_tree_epoch,
                        retry_count,
                        max_retry_count
                    );
                    sleep(Duration::from_millis(retry_delay_ms)).await;
                }
                Err(e) => {
                    // http error, 404, 500, etc. - record metrics before retry
                    let mut state = self.state.lock().await;
                    state.set_mls_sync_metrics(crate::service::service_state::MlsSyncMetrics {
                        local_epoch: local_mls_epoch_before as u32,
                        server_epoch: 0,
                        is_user_device_in_group_info: false,
                        is_websocket_disconnected,
                        has_websocket_reconnected,
                        is_get_group_info_success: false,
                        connection_lost_type: Some(ConnectionLostType::FetchTimeout),
                    });

                    retry_count += 1;
                    tracing::error!(
                        "Failed to get group info: {:?}, retry: {}/{}",
                        e,
                        retry_count,
                        max_retry_count
                    );
                    sleep(Duration::from_millis(retry_delay_ms)).await;
                }
            }
        }
    }

    pub async fn is_websocket_has_reconnected(&self) -> bool {
        // get the websocket connection state
        self.ws_client.get_has_reconnected().await
    }

    pub async fn reset_service_state(&self) {
        let mut state = self.state.lock().await;
        state.reset();
        drop(state);
    }
}

#[async_trait]
impl UserService for Service {
    async fn login(
        &self,
        username: &str,
        password: &str,
    ) -> Result<(UserData, ProtonUser, Vec<ProtonUserKey>, Vec<Address>), LoginError> {
        let login_response = self.user_api.login(username, password).await?;

        self.user_repository
            .init_tables(&login_response.user.id)
            .await?;

        let user = login_response.user.clone();
        self.user_repository.save_user(&user).await?;

        let user_keys: Vec<ProtonUserKey> = login_response.user.keys.clone().unwrap_or_default();

        self.user_repository
            .save_user_keys(&user.id, &user_keys)
            .await?;

        let user_addresses = self.user_api.get_user_addresses().await?;

        Ok((login_response, user, user_keys, user_addresses))
    }

    async fn login_with_two_factor(&self, two_factor_code: &str) -> Result<UserData, LoginError> {
        let user_data = self.user_api.login_with_two_factor(two_factor_code).await?;
        self.user_repository.init_tables(&user_data.user.id).await?;
        let user = user_data.user.clone();
        self.user_repository.save_user(&user).await?;
        Ok(user_data)
    }

    async fn get_user(&self, user_id: &UserId) -> Result<ProtonUser, ServiceError> {
        let user = self.user_repository.get_user(user_id.as_str()).await?;
        if user.is_none() {
            let proton_user = self.user_api.get_user_info().await?;
            self.user_repository.save_user(&proton_user).await?;
            let user_keys = self.user_repository.get_user_keys(user_id.as_str()).await?;
            if user_keys.is_empty() {
                let user_keys = proton_user.keys.clone().unwrap_or_default();
                self.user_repository
                    .save_user_keys(&proton_user.id, &user_keys)
                    .await?;
            }
            return Ok(proton_user);
        }
        user.ok_or(ServiceError::UserNotFound)
    }

    async fn get_user_keys(&self, user_id: &UserId) -> Result<Vec<ProtonUserKey>, anyhow::Error> {
        let user_keys = self.user_repository.get_user_keys(user_id.as_str()).await?;
        if user_keys.is_empty() {
            let proton_user = self.user_api.get_user_info().await?;
            if let Some(keys) = proton_user.keys {
                let proton_keys: Vec<ProtonUserKey> = keys;
                self.user_repository
                    .save_user_keys(user_id.as_str(), &proton_keys)
                    .await?;
                return Ok(proton_keys);
            }
            return Ok(vec![]);
        }
        Ok(user_keys)
    }

    async fn get_user_addresses(&self) -> Result<Vec<Address>, anyhow::Error> {
        let user_addresses = self.user_api.get_user_addresses().await?;
        Ok(user_addresses)
    }

    async fn logout(&self, user_id: &UserId) -> Result<(), anyhow::Error> {
        self.user_api.logout().await;
        self.user_repository.delete_user(user_id.as_str()).await?;
        Ok(())
    }

    async fn create_mls_client(
        &self,
        access_token: &str,
        meet_link_name: &str,
        meeting_password: &str,
        use_psk: bool,
        session_id: Option<&str>,
    ) -> Result<UserTokenInfo, anyhow::Error> {
        let total_start = instant::now();

        {
            let mut use_psk_guard = self.use_psk.lock().await;
            *use_psk_guard = use_psk;
        }

        let client_start = instant::now();
        let (client, _) = MlsClient::new(MemKv::new(), MlsClientConfig::default()).await?;
        tracing::debug!(
            "create_mls_client step=client_new ms={}",
            client_start.elapsed().as_millis()
        );

        let cnf_start = instant::now();
        let cnf = client
            .get_holder_confirmation_key_pem()
            .map_err(|e| anyhow::anyhow!("Failed to get holder confirmation key: {e}"))?; // TODO::remove anyhow
        tracing::debug!(
            "create_mls_client step=get_holder_confirmation_key ms={}",
            cnf_start.elapsed().as_millis(),
        );
        let holder_signing_key = ed25519_dalek::VerifyingKey::from_public_key_pem(&cnf)?;
        let base64_holder_signing_key =
            general_purpose::STANDARD.encode(holder_signing_key.to_bytes());

        let fetch_sd_cwt_future = self.http_client.fetch_sd_cwt(
            meet_link_name,
            access_token,
            &base64_holder_signing_key,
            session_id,
        );
        let fetch_cks_future = self.http_client.fetch_cose_key_set();
        // Fetch the external sender here to not add another latency in the MLS group creation.
        // The data will be cached in the http client.
        // Enable it later
        // let fetch_external_sender_future = self.http_client.fetch_external_sender();

        let join_task_start = instant::now();

        // let (base64_sd_cwt, cks, external_sender) = join3(
        //     fetch_sd_cwt_future,
        //     fetch_cks_future,
        //     fetch_external_sender_future,
        // )
        // .await;
        let (base64_sd_cwt, cks) = join(fetch_sd_cwt_future, fetch_cks_future).await;

        let base64_sd_cwt = base64_sd_cwt.map_err(|e| {
            tracing::error!(
                "Failed to fetch SD-CWT for meeting {}: {:?} ms={}",
                meet_link_name,
                e,
                join_task_start.elapsed().as_millis()
            );
            e
        })?;
        let cks_bytes = cks.map_err(|e| {
            tracing::error!(
                "Failed to fetch CKS: {:?} ms={}",
                e,
                join_task_start.elapsed().as_millis()
            );
            e
        })?;
        tracing::debug!(
            "create_mls_client step=fetch_sd_cwt ms={}",
            join_task_start.elapsed().as_millis(),
        );
        // let _external_sender_bytes = external_sender.map_err(|e| {
        //     tracing::error!(
        //         "Failed to fetch external sender: {:?} ms={}",
        //         e,
        //         join_task_start.elapsed().as_millis()
        //     );
        //     e
        // })?;

        let cks = CoseKeySet::from_cbor_bytes(&cks_bytes)?;

        let decode_start = instant::now();
        let sd_cwt_bytes = base64::engine::general_purpose::STANDARD.decode(base64_sd_cwt)?;
        let sd_cwt = SdCwt::from_cbor_bytes(&sd_cwt_bytes)?;
        tracing::debug!(
            "create_mls_client step=decode_sd_cwt ms={}",
            decode_start.elapsed().as_millis(),
        );

        // TODO: fetch server cks from the server after we have auth server and meet server
        let init_start = instant::now();
        let mut client = client.initialize(MemKv::new(), sd_cwt, &cks, &cks)?;
        tracing::debug!(
            "create_mls_client step=initialize_client ms={}",
            init_start.elapsed().as_millis()
        );

        let psk_id = mls_types::ExternalPskId(meet_link_name.as_bytes().to_vec());
        let psk_value = derive_external_psk(meeting_password, meet_link_name)?;
        client.insert_external_psk(psk_id, psk_value).await?;
        tracing::debug!(
            "create_mls_client step=insert_external_psk ms={}",
            init_start.elapsed().as_millis()
        );

        let sub_start = instant::now();
        let sub = client.sd_cwt_mut()?.sub()?;
        let mime_subject = MimiSubject::from_str(sub)?;
        let user_identifier = meet_identifiers::UserId::from_str(sub)?;
        tracing::debug!(
            "create_mls_client step=parse_subject ms={}",
            sub_start.elapsed().as_millis(),
        );
        let user_info = UserTokenInfo {
            user_identifier,
            device_id: mime_subject.device_id().to_string(),
        };
        tracing::debug!(
            "create_mls_client step=user_info ms={}",
            sub_start.elapsed().as_millis(),
        );

        let store_start = instant::now();
        self.mls_store
            .write()
            .await
            .clients
            .entry(user_info.user_id().to_string())
            .or_default()
            .insert(client.cs, client);
        tracing::debug!(
            "create_mls_client step=store_client ms={}",
            store_start.elapsed().as_millis()
        );

        tracing::debug!(
            "create_mls_client step=done total_ms={}",
            total_start.elapsed().as_millis()
        );

        Ok(user_info)
    }

    async fn create_mls_group(
        &self,
        user_identifier: &UserId,
        group_id: &str,
        meeting_link_name: &str,
        cs: CipherSuite,
    ) -> Result<(Arc<RwLock<MlsGroup<MemKv>>>, CommitBundle), anyhow::Error> {
        let mut mls_store = self.mls_store.write().await;
        let client = mls_store.find_client(&user_identifier.to_string(), &cs)?;

        let user_id = client.user_id()?;
        let group_id = GroupId {
            id: Id::from_str(group_id)?,
            domain: Domain::from_str("meet.proton.me")?,
        };

        let is_host = client
            .new_sd_kbt(Disclosure::Full, None, &PresentationContext::Default)?
            .0
            .sd_cwt_payload()?
            .inner
            .extra
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("no extra payload"))?
            .is_host;
        let group_config = MlsGroupConfig::default(user_id.clone(), is_host);
        // TODO: Enable it later
        // let external_sender_bytes = self.http_client.fetch_external_sender().await?;
        // if external_sender_bytes.is_empty() {
        //     tracing::warn!(
        //         "External sender response empty; creating group without external sender"
        //     );
        // } else {
        //     let external_sender = ExternalSender::from_tls_bytes(&external_sender_bytes)?;
        //     group_config.external_senders.push(external_sender);
        // }

        let mut group = client
            .new_group(&group_id, Disclosure::Full, group_config)
            .await?
            .store()
            .await?;

        let use_psk = {
            let use_psk_guard = self.use_psk.lock().await;
            *use_psk_guard
        };

        let mut proposals = Vec::new();

        if use_psk {
            proposals.push(ProposalArg::PskExternal {
                id: ExternalPskId(meeting_link_name.as_bytes().to_vec()),
            });
        }

        let (bundle, ..) = group.new_commit(proposals).await?;
        group.merge_pending_commit().await?;

        assert!(group.roster().count() == 1);
        assert!(bundle.group_info.is_some());
        assert!(bundle.ratchet_tree.is_some());

        let group_to_save = Arc::new(RwLock::new(group));
        mls_store
            .group_map
            .insert(meeting_link_name.to_string(), group_to_save.clone());

        Ok((group_to_save, bundle))
    }

    async fn create_external_proposal(
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
            .join_via_external_proposal(gi_mls_message, ratchet_tree, Disclosure::Full)
            .await?;

        Ok(mls_message)
    }

    async fn join_group(
        &self,
        participant_id: &UserId,
        meeting_link_name: &str,
        welcome_message: mls_types::MlsMessage,
        ratchet_tree_option: RatchetTreeOption,
    ) -> Result<Arc<RwLock<MlsGroup<MemKv>>>, anyhow::Error> {
        let cs = self.mls_store.read().await.config.ciphersuite;

        let (mls_group, _) = {
            let mls_store = self.mls_store.read().await;
            let client = mls_store.find_client(&participant_id.to_string(), &cs)?;

            let ratchet_tree = ratchet_tree_option.try_into().map_err(|e| {
                anyhow::anyhow!(
                    "Failed to convert ratchet tree option to mls_types::RatchetTree: {e}"
                )
            })?;

            // Call join_group with ratchet tree and welcome message
            client.join_group(welcome_message, ratchet_tree).await?
        };

        let mls_group = mls_group.store().await?;
        let group_to_save = Arc::new(RwLock::new(mls_group));

        let mut mls_store = self.mls_store.write().await;
        mls_store
            .group_map
            .insert(meeting_link_name.to_string(), group_to_save.clone());

        Ok(group_to_save)
    }

    async fn create_external_commit(
        &self,
        participant_id: &UserId,
        meeting_link_name: &str,
        cs: CipherSuite,
        group_info: GroupInfo,
        ratchet_tree_option: RatchetTreeOption,
    ) -> Result<(Arc<RwLock<MlsGroup<MemKv>>>, CommitBundle), anyhow::Error> {
        let mut mls_store = self.mls_store.write().await;
        let client = mls_store.find_client(&participant_id.to_string(), &cs)?;

        let app_message = MlsMessage {
            version: ProtocolVersion::Mls10,
            content: MlsMessageContent::GroupInfo(group_info),
        };

        let mls_message = convert_mls_spec_to_types(&app_message)?;

        let ratchet_tree = ratchet_tree_option.try_into().map_err(|e| {
            anyhow::anyhow!("Failed to convert ratchet tree option to mls_types::RatchetTree: {e}")
        })?;

        let result = client
            .join_group_via_external_commit(mls_message, ratchet_tree, Disclosure::Full, vec![])
            .await;
        let (mls_group, commit) = match result {
            Ok((mls_group, commit)) => (mls_group, commit),
            Err(e) => {
                tracing::error!("Failed to join group via external commit: {:?}", e);
                return Err(anyhow::anyhow!(
                    "Failed to join group via external commit: {e:?}"
                ));
            }
        };
        let mls_group = mls_group.store().await?;

        let group_to_save = Arc::new(RwLock::new(mls_group));
        mls_store
            .group_map
            .insert(meeting_link_name.to_string(), group_to_save.clone());

        Ok((group_to_save, commit))
    }

    async fn create_external_commit_with_psks(
        &self,
        participant_id: &UserId,
        meeting_link_name: &str,
        cs: CipherSuite,
        group_info: GroupInfo,
        ratchet_tree_option: RatchetTreeOption,
        external_psks: Vec<ExternalPskId>,
    ) -> Result<(Arc<RwLock<MlsGroup<MemKv>>>, CommitBundle), anyhow::Error> {
        let mut mls_store = self.mls_store.write().await;
        let client = mls_store.find_client(&participant_id.to_string(), &cs)?;

        let app_message = MlsMessage {
            version: ProtocolVersion::Mls10,
            content: MlsMessageContent::GroupInfo(group_info),
        };

        let mls_message = convert_mls_spec_to_types(&app_message)?;

        let ratchet_tree = ratchet_tree_option.try_into().map_err(|e| {
            anyhow::anyhow!("Failed to convert ratchet tree option to mls_types::RatchetTree: {e}")
        })?;

        let result = client
            .join_group_via_external_commit(
                mls_message,
                ratchet_tree,
                Disclosure::Full,
                external_psks,
            )
            .await;
        let (mls_group, commit) = match result {
            Ok((mls_group, commit)) => (mls_group, commit),
            Err(e) => {
                tracing::error!("Failed to join group via external commit: {:?}", e);
                return Err(anyhow::anyhow!(
                    "Failed to join group via external commit: {e:?}"
                ));
            }
        };
        let mls_group = mls_group.store().await?;

        let group_to_save = Arc::new(RwLock::new(mls_group));
        mls_store
            .group_map
            .insert(meeting_link_name.to_string(), group_to_save.clone());

        Ok((group_to_save, commit))
    }

    async fn create_leave_proposal(
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

    async fn create_self_remove_participant_update_proposal(
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

    /// Kicks a participant from an MLS group with automatic retry on server rejection.
    ///
    /// This function:
    /// 1. Atomically collects and processes all pending proposals from the queue
    /// 2. Creates a fresh remove proposal for the target participant
    /// 3. Bundles the remove with pending proposals in a commit
    /// 4. Uploads to server with retry logic on HTTP 422 errors
    ///
    /// # Arguments
    /// * `target_participant_id` - UUID string of the participant to remove
    /// * `meeting_link_name` - Meeting room identifier
    ///
    /// # Returns
    /// * `Ok(())` - Target successfully removed or already removed
    /// * `Err(MeetCoreError::MaxRetriesReached)` - After 4 failed attempts with HTTP 422
    /// * `Err(MeetCoreError::ParticipantNotFound)` - Group or target not found
    /// * `Err(...)` - Other errors (network, MLS, etc.) fail immediately without retry
    ///
    /// # Retry Behavior
    /// - Retries only on HTTP 422 (validation error) from server
    /// - 4 total attempts (1 initial + 3 retries)
    /// - Exponential backoff: 500ms, 1000ms, 2000ms (±10% jitter)
    /// - Fresh remove proposal created for each attempt
    /// - Pending commit cleared after failed upload to maintain MLS state consistency
    ///
    /// # Concurrency
    /// - Atomically coordinates with proposal batch timer to prevent double-processing
    /// - Safe for concurrent calls (early exit if target already removed)
    async fn kick_participant(
        &self,
        target_participant_id: &str,
        meeting_link_name: &str,
    ) -> Result<(), MeetCoreError> {
        let target_uuid = Uuid::from_str(target_participant_id)?;

        let use_psk = {
            let use_psk_guard = self.use_psk.lock().await;
            *use_psk_guard
        };

        tracing::debug!(
            "Starting kick for participant {} in meeting {}",
            target_participant_id,
            meeting_link_name,
        );

        //Retry loop with fresh remove proposal each attempt
        for attempt_num in 0..KICK_MAX_ATTEMPTS {
            tracing::debug!(
                "Kick attempt {}/{} for participant {} in meeting {}",
                attempt_num + 1,
                KICK_MAX_ATTEMPTS,
                target_participant_id,
                meeting_link_name
            );

            let queued_proposals = {
                let mut queue_lock = self.proposal_queue.lock().await;

                let proposals = queue_lock.remove(meeting_link_name).unwrap_or_default();

                // Clear timer entry while still holding queue lock
                // This prevents timer from racing between timer check and queue access
                let mut timer_map = self.proposal_timer.lock().await;
                timer_map.remove(meeting_link_name);

                proposals
            };

            // Get write lock for this retry attempt
            let mls_store = self.mls_store.read().await;
            let mut mls_group = mls_store
                .group_map
                .get(meeting_link_name)
                .ok_or(MeetCoreError::ParticipantNotFound)?
                .write()
                .await;

            let role = mls_group.own_role_for_current_epoch()?;
            if role.role_index != UserRole::RoomAdmin.builder().role_index {
                tracing::warn!("User is not RoomAdmin, cannot kick participant");
                restore_proposals_to_queue(
                    &self.proposal_queue,
                    meeting_link_name.to_string(),
                    queued_proposals,
                    "not RoomAdmin",
                );
                return Err(MeetCoreError::NotRoomAdmin);
            }

            // Process each queued proposal through MLS group
            for queued in &queued_proposals {
                if let Err(e) = mls_group
                    .decrypt_message(queued.proposal_message.clone())
                    .await
                {
                    tracing::warn!("Failed to process queued proposal: {:?}", e);
                    // Continue with other proposals - invalid ones filtered by MLS library
                }
            }

            // Find target member in current roster
            let target_member = mls_group.roster().find(|m| match &m.credential {
                mls_types::Credential::SdCwtDraft04 {
                    claimset: Some(claimset),
                    ..
                } => claimset.uuid == target_uuid.into_bytes(),
                _ => false,
            });

            // If target not found, they were removed concurrently - success!
            let target_member = match target_member {
                Some(m) => m,
                None => {
                    tracing::debug!(
                        "Target {} removed concurrently during attempt {}",
                        target_participant_id,
                        attempt_num + 1
                    );
                    return Ok(());
                }
            };

            tracing::debug!(
                "Creating remove proposal for leaf_index {} in epoch {}",
                target_member.leaf_index(),
                mls_group.epoch()
            );

            let authorizer = mls_group.authorizer()?;
            let epoch = mls_group.epoch();
            let mut active_participants = HashSet::new();
            let mut to_remove = Vec::new();
            let mut proposal_args = Vec::new();

            proposal_args.push(ProposalArg::Remove(target_member.leaf_index()));

            for mut m in mls_group.roster() {
                let user_id = m.user_id()?;
                let identity = ProtonMeetIdentityProvider::user_identifier(&user_id);
                active_participants.insert(identity.clone());
                if m.leaf_index() == target_member.leaf_index() {
                    to_remove.push(identity);
                }
            }

            for identity in to_remove {
                proposal_args.extend(
                    authorizer
                        .role_proposal_for_removed_user(*epoch, &identity, &active_participants)?
                        .into_iter()
                        .map(|component| ProposalArg::UpdateComponent {
                            id: component.component_id,
                            data: component.data,
                        }),
                );
            }

            if use_psk {
                proposal_args.push(ProposalArg::PskExternal {
                    id: ExternalPskId(meeting_link_name.as_bytes().to_vec()),
                });
            }

            let result = mls_group.new_commit(proposal_args).await;
            let (commit_bundle, _welcome_option) = match result {
                Ok((commit_bundle, _welcome_option)) => (commit_bundle, _welcome_option),
                Err(e) => {
                    tracing::error!("Failed to create commit bundle: {:?}", e);
                    return Err(e.into());
                }
            };

            // Extract required fields
            let group_info = commit_bundle
                .group_info
                .ok_or(anyhow::anyhow!("Missing group info in commit bundle"))?;
            let ratchet_tree = commit_bundle
                .ratchet_tree
                .ok_or(anyhow::anyhow!("Missing ratchet tree in commit bundle"))?;

            // Convert to spec format for server
            let group_info_message = convert_mls_types_to_spec(&group_info)?;
            let ratchet_tree_option = ratchet_tree
                .try_into()
                .map_err(|e| anyhow::anyhow!("Failed to convert ratchet tree: {e}"))?;

            // Create MlsCommitInfo wrapper
            let welcome = commit_bundle.welcome.map(TryInto::try_into).transpose()?;
            let commit_info = MlsCommitInfo {
                room_id: meeting_link_name.as_bytes().to_vec(),
                welcome_message: welcome,
                commit: convert_mls_types_to_spec(&commit_bundle.commit)?,
            };

            tracing::debug!(
                "Created commit bundle for attempt {}, uploading to server",
                attempt_num + 1
            );

            let base64_sd_kbt = self
                .get_sd_kbt(&UserId::new(mls_group.own_user_id()?.to_string()))
                .await?;

            let result = self
                .http_client
                .update_group_info(
                    &base64_sd_kbt,
                    &group_info_message,
                    &ratchet_tree_option,
                    Some(&commit_info),
                    None, // No additional proposals
                )
                .await;

            // Handle server response
            match result {
                Ok(_) => {
                    // Success - merge pending commit
                    mls_group.merge_pending_commit().await?;

                    tracing::info!(
                        "Successfully kicked participant {} from meeting {} on attempt {}",
                        target_participant_id,
                        meeting_link_name,
                        attempt_num + 1
                    );

                    drop(mls_group);

                    // Trigger group update handler
                    if let Some(handler) = self.mls_group_update_handler.as_ref() {
                        let mut handler = handler.lock().await;
                        handler(meeting_link_name.to_string()).await;
                    }

                    return Ok(());
                }
                Err(e) => {
                    mls_group.clear_pending_commit();
                    mls_group.clear_pending_proposals();

                    drop(mls_group);

                    let is_retryable = if let HttpClientError::ErrorCode(status, _) = &e {
                        *status == 422
                    } else {
                        false
                    };

                    // Case 1: Non-retryable error - fail fast with original error
                    if !is_retryable {
                        tracing::warn!(
                            "Kick failed with non-retryable error on attempt {}: {:?}",
                            attempt_num + 1,
                            e
                        );
                        restore_proposals_to_queue(
                            &self.proposal_queue,
                            meeting_link_name.to_string(),
                            queued_proposals.clone(),
                            "non-retryable error",
                        );
                        return Err(e.into());
                    }

                    // Case 2: Retryable (422) but max attempts exhausted
                    if attempt_num >= KICK_MAX_ATTEMPTS - 1 {
                        tracing::error!(
                            "Kick failed after {} attempts with HTTP 422, max retries exhausted",
                            KICK_MAX_ATTEMPTS
                        );
                        restore_proposals_to_queue(
                            &self.proposal_queue,
                            meeting_link_name.to_string(),
                            queued_proposals.clone(),
                            "max retries exhausted",
                        );
                        return Err(MeetCoreError::MaxRetriesReached);
                    }

                    // Case 3: Retryable (422) with attempts remaining - sleep and retry
                    let delay_ms =
                        calculate_retry_delay(attempt_num, KICK_BASE_DELAY_MS, KICK_MAX_DELAY_MS);

                    tracing::warn!(
                        "Kick failed with HTTP 422 (attempt {}/{}), retrying in {}ms",
                        attempt_num + 1,
                        KICK_MAX_ATTEMPTS,
                        delay_ms
                    );

                    sleep(Duration::from_millis(delay_ms)).await;
                    // Continue to next iteration
                }
            }
        }

        // This should be unreachable since all paths in the loop return
        unreachable!("Should have returned from retry loop")
    }

    async fn get_group_key(&self, meeting_link_name: &str) -> Result<(String, u64), anyhow::Error> {
        let mls_store = self.mls_store.read().await;
        let group = mls_store
            .group_map
            .get(meeting_link_name)
            .ok_or(anyhow::anyhow!(
                "Failed to find mls group for room {meeting_link_name}"
            ))?
            .read()
            .await;

        let group_key = group.export_secret("meet-key", b"", 32).await?;
        let base64_group_key = general_purpose::STANDARD.encode(group_key.as_ref() as &[u8]);
        let epoch = group.epoch();
        Ok((base64_group_key, *epoch))
    }

    async fn get_group_len(&self, meeting_link_name: &str) -> Result<u32, anyhow::Error> {
        let mls_store = self.mls_store.read().await;
        let group = mls_store
            .group_map
            .get(meeting_link_name)
            .ok_or(anyhow::anyhow!(
                "Failed to find mls group for room {meeting_link_name}"
            ))?
            .read()
            .await;

        let len = group.roster().count() as u32;
        Ok(len)
    }

    async fn get_group_display_code(
        &self,
        meeting_link_name: &str,
    ) -> Result<String, anyhow::Error> {
        let mls_store = self.mls_store.read().await;
        let group = mls_store
            .group_map
            .get(meeting_link_name)
            .ok_or(anyhow::anyhow!(
                "Failed to find mls group for room {meeting_link_name}"
            ))?
            .read()
            .await;

        let epoch_authenticator = group.epoch_authenticator()?;

        // hex encode the epoch authenticator
        let group_display_code: String = epoch_authenticator
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();

        Ok(group_display_code)
    }

    async fn encrypt_application_message(
        &self,
        meeting_link_name: &str,
        message: &str,
    ) -> Result<mls_types::MlsMessage, anyhow::Error> {
        let mls_group_lock = {
            let store_lock = self.mls_store.read().await;
            store_lock
                .group_map
                .get(meeting_link_name)
                .ok_or_else(|| {
                    anyhow::anyhow!("Failed to find mls group for room {meeting_link_name}")
                })?
                .clone()
        };
        let mut mls_group = mls_group_lock.write().await;

        let encrypted_message = mls_group
            .encrypt_message(MediaType::default(), message.as_bytes())
            .await?;
        Ok(encrypted_message)
    }

    async fn decrypt_application_message(
        &self,
        meeting_link_name: &str,
        message: mls_types::MlsMessage,
    ) -> Result<(String, UserId), anyhow::Error> {
        match message.content_type()? {
            ContentType::Application => {}
            _ => {
                return Err(anyhow::anyhow!(
                    "Expected ApplicationMessage but received different message type: {:?}",
                    message.content_type()
                ));
            }
        }

        let mls_group_lock = {
            let store_lock = self.mls_store.read().await;
            store_lock
                .group_map
                .get(meeting_link_name)
                .ok_or_else(|| {
                    anyhow::anyhow!("Failed to find mls group for room {meeting_link_name}")
                })?
                .clone()
        };
        let mut mls_group = mls_group_lock.write().await;

        let (decrypted_message, _reinit) = mls_group.decrypt_message(message).await?;

        match decrypted_message {
            ReceivedMessage::ApplicationMessage {
                content, sender, ..
            } => {
                let content_string = String::from_utf8(content)
                    .map_err(|e| anyhow::anyhow!("Failed to convert content to UTF-8: {e}"))?;
                let mut sender = mls_group.find_member(sender)?;
                let sender_user_id = sender.credential.user_id()?;
                Ok((content_string, UserId::new(sender_user_id.id.to_string())))
            }
            _ => Err(anyhow::anyhow!(
                "Expected ApplicationMessage but received different message type: {decrypted_message:?}"
            )),
        }
    }

    async fn handle_websocket_message(
        &self,
        message: WebSocketMessage,
    ) -> Result<(), anyhow::Error> {
        const MLS_STATE_CHECK_TIMEOUT: u64 = 3; // seconds

        match message {
            WebSocketMessage::Text(text) => {
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

                            match rtc_message.content {
                                RTCMessageInContent::Welcome(mls_welcome_info) => {
                                    tracing::info!(
                                        ws_msg_id = msg_id_for_log.as_deref().unwrap_or("n/a"),
                                        "Received welcome message"
                                    );
                                    let mut state = self.state.lock().await;
                                    // save the welcome info to the state
                                    state.set_welcome_info(Some(mls_welcome_info));
                                    drop(state);
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
                                    let has_welcome = mls_commit_info.welcome_message.is_some();
                                    tracing::info!(
                                        ws_msg_id = msg_id_for_log
                                            .as_deref()
                                            .unwrap_or("n/a"),
                                        room_id = %room_id,
                                        commit_epoch = ?epoch,
                                        has_welcome = has_welcome,
                                        "Received commit update"
                                    );
                                    let mut should_process_cached_messages = false;
                                    match self
                                        .process_commit_message(commit_message, &room_id)
                                        .await
                                    {
                                        Ok(CommitProcessingOutcome::Applied) => {
                                            should_process_cached_messages = true;
                                        }
                                        Ok(CommitProcessingOutcome::NoStateChange) => {
                                            tracing::debug!(
                                                "Commit did not change state for room {}, skipping cached message processing",
                                                room_id
                                            );
                                        }
                                        Ok(CommitProcessingOutcome::DeferredFutureEpoch) => {
                                            tracing::debug!(
                                                "Commit deferred for future epoch in room {}, skipping cached message processing",
                                                room_id
                                            );
                                        }
                                        Err(e) => {
                                            if let Some(ServiceError::ProposalNotFound) =
                                                e.downcast_ref::<ServiceError>()
                                            {
                                                let commit_message =
                                                    mls_types::MlsMessage::try_from(
                                                        mls_commit_info.commit.clone(),
                                                    )?;
                                                let _ = self
                                                    .cache_commit_message(&room_id, commit_message)
                                                    .await;
                                                tracing::info!(
                                                    "Cached commit message for later processing"
                                                );
                                            } else if let Some(ServiceError::PskProposalMissing) =
                                                e.downcast_ref::<ServiceError>()
                                            {
                                                tracing::error!(
                                                    "Commit rejected: PSK proposal missing or has wrong ID for room {}",
                                                    room_id
                                                );
                                                return Err(e);
                                            } else {
                                                tracing::warn!(
                                                    "Failed to process commit message for room {}: {}",
                                                    room_id,
                                                    e
                                                );
                                            }
                                        }
                                    }

                                    if should_process_cached_messages {
                                        // Process cached messages only after we actually advanced/applied commit state.
                                        match self.process_cached_messages(&room_id).await {
                                            Ok(_) => tracing::debug!(
                                                "Cached messages processed successfully for room {}",
                                                room_id
                                            ),
                                            Err(e) => tracing::warn!(
                                                "Failed to process cached messages for room {}: {:?}",
                                                room_id,
                                                e
                                            ),
                                        }
                                    }
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
                                    let room_id = String::from_utf8(proposal_info.room_id.clone())
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
                                    let proposal_type = describe_proposal_kind(&proposal_message)
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
                                    let mut should_process_cached_messages = false;
                                    match self
                                        .process_proposal_message(proposal_message, &room_id)
                                        .await
                                    {
                                        Ok(ProposalProcessingOutcome::Applied) => {
                                            should_process_cached_messages = true;
                                        }
                                        Ok(ProposalProcessingOutcome::NoStateChange) => {
                                            tracing::debug!(
                                                "Proposal did not change state for room {}, skipping cached message processing",
                                                room_id
                                            );
                                        }
                                        Ok(ProposalProcessingOutcome::DeferredFutureEpoch) => {
                                            tracing::debug!(
                                                "Proposal deferred for future epoch in room {}, skipping cached message processing",
                                                room_id
                                            );
                                        }
                                        Err(e) => {
                                            tracing::warn!(
                                                "Failed to process proposal message: {}",
                                                e
                                            );
                                            let proposal_message = mls_types::MlsMessage::try_from(
                                                proposal_info.proposal.clone(),
                                            )?;
                                            let _ = self
                                                .cache_proposal_message(&room_id, proposal_message)
                                                .await;
                                            tracing::info!(
                                                "Cached proposal message for later processing"
                                            );
                                        }
                                    }

                                    if should_process_cached_messages {
                                        // Process cached messages only after proposal was accepted into current epoch state.
                                        match self.process_cached_messages(&room_id).await {
                                            Ok(_) => tracing::debug!(
                                                "Cached messages processed successfully for room {}",
                                                room_id
                                            ),
                                            Err(e) => tracing::warn!(
                                                "WS-MSG: Failed to process cached messages for room {}: {:?}",
                                                room_id,
                                                e
                                            ),
                                        }
                                    }
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
                                RTCMessageInContent::RemoveLeafNode(_mls_remove_leaf_node_info) => {
                                    tracing::debug!(
                                        "Received RemoveLeafNode message (not being used)"
                                    );
                                }
                                RTCMessageInContent::SendCommit(_mls_commit_info) => {
                                    tracing::debug!("Received SendCommit message (not being used)");
                                }
                                RTCMessageInContent::SendProposalAndCommit(
                                    _mls_proposal_and_commit_info,
                                ) => {
                                    tracing::debug!(
                                        "Received SendProposalAndCommit message (not being used)"
                                    );
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

                #[cfg(debug_assertions)]
                tracing::info!("Binary message processing completed successfully");
            }
            WebSocketMessage::Close(reason) => {
                tracing::info!("Received close message: {:?}", reason);
            }
        }

        Ok(())
    }

    async fn handle_proposal(
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

    async fn handle_livekit_admin_change(
        &self,
        room_id: &str,
        participant_uid: String,
        participant_type: u32,
    ) -> Result<(), anyhow::Error> {
        // trigger the livekit admin change handler to notify wasm/mobile
        if let Some(handler) = self.livekit_admin_change_handler.as_ref() {
            let mut handler = handler.lock().await;
            handler(room_id.to_string(), participant_uid, participant_type).await;
        } else {
            return Err(anyhow::anyhow!("LiveKit admin change handler is not set"));
        }

        Ok(())
    }

    async fn join_room(
        &self,
        user_info_token: &UserTokenInfo,
        meeting_link_name: &str,
        use_psk: bool,
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
            let result = self.http_client.get_group_info(&base64_sd_kbt).await;
            match result {
                // join by external commit
                Ok(ratchet_tree_and_group_info) => {
                    // check if the server version is supported
                    if ratchet_tree_and_group_info.version != GroupInfoVersion::V1 {
                        let mut state = self.state.lock().await;
                        state.set_mls_group_state(MlsGroupState::ServerVersionNotSupported);
                        return Err(MeetCoreError::MlsServerVersionNotSupported);
                    }

                    if let MlsMessageContent::GroupInfo(group_info) =
                        ratchet_tree_and_group_info.data.group_info.content
                    {
                        tracing::info!("Join by external commit");

                        let (mls_group, commit_bundle) = if use_psk {
                            self.create_external_commit_with_psks(
                                &user_info_token.user_id(),
                                meeting_link_name,
                                cs,
                                group_info,
                                ratchet_tree_and_group_info.data.ratchet_tree,
                                vec![ExternalPskId(meeting_link_name.as_bytes().to_vec())],
                            )
                            .await?
                        } else {
                            self.create_external_commit(
                                &user_info_token.user_id(),
                                meeting_link_name,
                                cs,
                                group_info,
                                ratchet_tree_and_group_info.data.ratchet_tree,
                            )
                            .await?
                        };

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
                            .http_client
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
                                if let HttpClientError::MlsStatusCode(status) = e {
                                    if status == 422 {
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

                    if let HttpClientError::MlsStatusCode(status) = &e {
                        if *status == 401 {
                            tracing::error!(
                                "Failed to get group info: 401 Unauthorized, may caused by time drift, stopping retry"
                            );
                            // client will need to show proper error message to user when we have this error
                            return Err(MeetCoreError::TimeDriftError);
                        }
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
                        .http_client
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
                            if let HttpClientError::MlsStatusCode(status) = e {
                                if status == 422 {
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
                            }
                            return Err(e.into());
                        }
                    }
                }
            }
        }
    }

    async fn join_room_with_proposal(
        &self,
        participant_id: &UserId,
        meeting_link_name: &str,
    ) -> Result<(), MeetCoreError> {
        let base64_sd_kbt = self.get_sd_kbt(participant_id).await?;

        let cs = {
            let mls_store = self.mls_store.read().await;
            mls_store.config.ciphersuite
        };

        const JOIN_PROPOSAL_TIMEOUT: u64 = 15;

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
                self.http_client.get_group_info(&base64_sd_kbt).await
            };

            match result {
                // join by external proposal
                Ok(ratchet_tree_and_group_info) => {
                    cached_group_info = Some(ratchet_tree_and_group_info.clone());

                    // check if the server version is supported
                    if ratchet_tree_and_group_info.version != GroupInfoVersion::V1 {
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
                            .http_client
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
                                if let HttpClientError::MlsStatusCode(status) = &e {
                                    if (400..500).contains(status) {
                                        cached_group_info = None;
                                    }
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
                                    // we had recevied the join proposal welcome and estiblish the mls group successfully
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

                    if let HttpClientError::MlsStatusCode(status) = &e {
                        if *status == 401 {
                            tracing::error!(
                                "Failed to get group info: 401 Unauthorized, may caused by time drift, stopping retry"
                            );
                            // client will need to show proper error message to user when we have this error
                            return Err(MeetCoreError::TimeDriftError);
                        }
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
                        .http_client
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
                            if let HttpClientError::MlsStatusCode(status) = e {
                                if status == 422 {
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
                            }
                            return Err(e.into());
                        }
                    }
                }
            }
        }
    }

    async fn leave_room(
        &self,
        participant_id: &UserId,
        meeting_link_name: &str,
    ) -> Result<(), anyhow::Error> {
        // find the mlsgroup of the room and decrypt the commit message
        let (remove_proposal, remove_self_from_participant_list_proposal) = {
            let store = self.mls_store.read().await;
            let group = store
                .group_map
                .get(meeting_link_name)
                .ok_or(anyhow::anyhow!(
                    "Failed to find mls group for room {meeting_link_name}"
                ))?;
            let mut mls_group = group.write().await;
            let cs = store.config.ciphersuite;

            // Create the ADU proposal for the leave room
            let remove_self_from_participant_list_proposal = self
                .create_self_remove_participant_update_proposal(&mut mls_group)
                .await?;

            let remove_proposal = self
                .create_leave_proposal(participant_id, &mut mls_group, cs)
                .await?;
            (remove_proposal, remove_self_from_participant_list_proposal)
        };

        if let Some(remove_self_from_participant_list_proposal) =
            remove_self_from_participant_list_proposal
        {
            let proposal_info = MlsProposalInfo {
                room_id: meeting_link_name.as_bytes().to_vec(),
                proposal: convert_mls_types_to_spec(&remove_self_from_participant_list_proposal)?,
            };
            let rtc_message_in = RTCMessageIn {
                content: RTCMessageInContent::Proposal(proposal_info),
            };
            let encoded_payload = rtc_message_in.to_tls_bytes()?;
            self.ws_client
                .send_message(ws_client::WebSocketMessage::Binary(encoded_payload))
                .await?;
        }

        let proposal_info = MlsProposalInfo {
            room_id: meeting_link_name.as_bytes().to_vec(),
            proposal: convert_mls_types_to_spec(&remove_proposal)?,
        };

        let rtc_message_in = RTCMessageIn {
            content: RTCMessageInContent::Proposal(proposal_info),
        };
        let encoded_payload = rtc_message_in.to_tls_bytes()?;
        self.ws_client
            .send_message(ws_client::WebSocketMessage::Binary(encoded_payload))
            .await?;

        // send the leave room message to the server for clean up connections
        let leave_room_message = LeaveRoomMessage {
            room_id: meeting_link_name.to_string(),
        };
        let _ = self
            .ws_client
            .send_text_request_and_wait(
                WebSocketTextRequestCommand::LeaveRoom(leave_room_message),
                Duration::from_secs(0),
            )
            .await;

        let mut state = self.state.lock().await;
        state.reset();

        Ok(())
    }

    async fn get_user_settings(&self) -> Result<UserSettings, anyhow::Error> {
        let user_settings = self.http_client.get_user_settings().await?;
        Ok(user_settings)
    }

    async fn get_sd_kbt(&self, user_identifier: &UserId) -> Result<String, anyhow::Error> {
        let mls_store = self.mls_store.read().await;
        let cs = mls_store.config.ciphersuite;
        let mls_client = mls_store
            .clients
            .get(&user_identifier.to_string())
            .ok_or(anyhow::anyhow!("mls client not found"))?
            .get(&cs)
            .ok_or(anyhow::anyhow!("mls client not found"))?;
        let sd_kbt = mls_client.new_identity_presentation(
            Disclosure::Full,
            None,
            &PresentationContext::Default,
        )?;
        let base64_sd_kbt = general_purpose::STANDARD.encode(sd_kbt);

        Ok(base64_sd_kbt)
    }

    async fn get_meeting_id(&self, user_identifier: &UserId) -> Result<String, anyhow::Error> {
        let mls_store = self.mls_store.read().await;
        let cs = mls_store.config.ciphersuite;
        let mls_client = mls_store
            .clients
            .get(&user_identifier.to_string())
            .ok_or(anyhow::anyhow!("mls client not found"))?
            .get(&cs)
            .ok_or(anyhow::anyhow!("mls client not found"))?;

        let sd_cwt = mls_client.sd_cwt()?;
        let payload = sd_cwt.0 .0.payload.as_value()?;
        let claims = payload
            .inner
            .extra
            .as_ref()
            .ok_or(anyhow::anyhow!("extra is not set"))?;
        Ok(claims.meeting_id.clone())
    }

    /// Check if user is host and update role to RoomAdmin if needed
    /// Only broadcasts once per epoch
    async fn check_and_update_host_role(&self, room_id: &str) -> Result<(), anyhow::Error> {
        let mls_group_lock = {
            let store_lock = self.mls_store.read().await;
            store_lock
                .group_map
                .get(room_id)
                .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
                .clone()
        };

        // Get state lock first to prevent holding the mls_group lock for too long
        let state_lock = self.state.lock().await;

        let mut mls_group = mls_group_lock.write().await;
        let epoch = *mls_group.epoch();

        // Check if we've already sent a proposal for this epoch
        if state_lock.has_sent_host_role_update_for_epoch(epoch) {
            tracing::debug!("Already sent host role update proposal for epoch {}", epoch);
            return Ok(());
        }
        drop(state_lock);

        let is_host = Self::is_host_from_credential(&mls_group)?;
        if !is_host {
            tracing::debug!("User is not host, skipping role update");
            return Ok(());
        }

        let current_role = mls_group.own_role_for_current_epoch()?;
        let identity = ProtonMeetIdentityProvider::user_identifier(&mls_group.own_user_id()?);

        if current_role.role_index == UserRole::RoomAdmin as u32 {
            tracing::debug!("User is already RoomAdmin, no update needed");
            return Ok(());
        }

        // Get participant list index
        let participant_list = mls_group.participant_list()?;
        let Some(participant_list_data) = participant_list else {
            tracing::warn!("No participant list found, cannot update role");
            return Ok(());
        };

        participant_list_data
            .participants
            .iter()
            .position(|p| p.user == identity)
            .ok_or_else(|| anyhow::anyhow!("User not found in participant list"))?;

        let authorizer = mls_group.authorizer()?;
        let user_index = match authorizer.participant_list_index(epoch, &identity) {
            Ok(Some(user_index)) => user_index,
            Err(e) => {
                tracing::error!("Failed to get participant list index: {:?}", e);
                return Err(e.into());
            }
            Ok(None) => {
                tracing::error!("User not found in participant list");
                return Err(anyhow::anyhow!("User not found in participant list"));
            }
        };

        let proposal_arg = mls_group.update_participant_role(user_index, UserRole::RoomAdmin)?;
        let mut proposals = mls_group.new_proposals([proposal_arg]).await?;
        let proposal_message = proposals.remove(0);
        drop(mls_group);

        // Broadcast proposal via websocket
        let proposal_info = MlsProposalInfo {
            room_id: room_id.as_bytes().to_vec(),
            proposal: convert_mls_types_to_spec(&proposal_message)?,
        };

        let rtc_message_in = RTCMessageIn {
            content: RTCMessageInContent::Proposal(proposal_info),
        };
        let encoded_payload = rtc_message_in.to_tls_bytes()?;
        self.ws_client
            .send_message(ws_client::WebSocketMessage::Binary(encoded_payload))
            .await?;

        // Mark epoch as handled
        {
            let mut state_lock = self.state.lock().await;
            state_lock.mark_host_role_update_sent_for_epoch(epoch);
        }

        tracing::info!(
            "Broadcast host role update proposal for epoch {} to become RoomAdmin",
            epoch
        );

        Ok(())
    }
}

impl Service {
    /// Check if the user is host from their credential in the MLS group
    fn is_host_from_credential(mls_group: &MlsGroup<MemKv>) -> Result<bool, anyhow::Error> {
        let self_leaf_index = mls_group.own_leaf_index()?;
        let mut member = mls_group.find_member(self_leaf_index)?;

        match &mut member.credential {
            mls_types::Credential::SdCwtDraft04 { sd_kbt, .. } => {
                let sd_cwt_payload = sd_kbt.0.sd_cwt_payload()?;
                let extra = sd_cwt_payload
                    .inner
                    .extra
                    .as_ref()
                    .ok_or_else(|| anyhow::anyhow!("no extra payload"))?;
                Ok(extra.is_host)
            }
            _ => Err(anyhow::anyhow!("Credential is not SdCwtDraft04")),
        }
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn set_mls_group_update_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        tracing::info!("Service set mls group update handler");
        self.mls_group_update_handler = Some(Arc::new(Mutex::new(Box::new({
            move |room_id| {
                Box::new(callback(room_id)) as Box<dyn Future<Output = ()> + Send + Unpin>
            }
        }))));
    }

    #[cfg(target_family = "wasm")]
    pub fn set_mls_group_update_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String) -> Fut + 'static,
        Fut: Future<Output = ()> + Unpin + 'static,
    {
        self.mls_group_update_handler = Some(Arc::new(Mutex::new(Box::new({
            move |room_id| Box::new(callback(room_id)) as Box<dyn Future<Output = ()> + Unpin>
        }))));
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn set_livekit_admin_change_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String, String, u32) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        tracing::info!("Service set livekit admin change handler");
        self.livekit_admin_change_handler = Some(Arc::new(Mutex::new(Box::new({
            move |room_id, participant_uid, participant_type| {
                Box::new(callback(room_id, participant_uid, participant_type))
                    as Box<dyn Future<Output = ()> + Send + Unpin>
            }
        }))));
    }

    async fn set_mls_sync_state_with_callback(
        &self,
        new_state: MlsSyncState,
        reason: Option<RejoinReason>,
    ) {
        // Set the state
        {
            let mut state = self.state.lock().await;
            state.set_mls_sync_state(new_state.clone());
        }

        // Trigger callback outside of lock to prevent lock inversion
        // Only pass reason if state is Failed
        let callback_reason = if matches!(new_state, MlsSyncState::Failed) {
            reason
        } else {
            None
        };
        if let Some(handler) = self.mls_sync_state_update_handler.as_ref() {
            let mut handler = handler.lock().await;
            handler(new_state, callback_reason).await;
        }
    }

    fn connection_lost_type_to_rejoin_reason(
        connection_lost_type: &ConnectionLostType,
    ) -> RejoinReason {
        match connection_lost_type {
            ConnectionLostType::EpochMismatch => RejoinReason::EpochMismatch,
            ConnectionLostType::WebsocketDisconnected => RejoinReason::WebsocketDisconnected,
            ConnectionLostType::MemberNotFoundInMLS => RejoinReason::MemberNotFoundInMLS,
            ConnectionLostType::FetchTimeout => RejoinReason::FetchTimeout,
            ConnectionLostType::Other => RejoinReason::Other,
        }
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn set_mls_sync_state_update_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(MlsSyncState, Option<RejoinReason>) -> Fut + Send + 'static,
        Fut: Future<Output = ()> + Unpin + Send + 'static,
    {
        tracing::info!("Service set mls sync state update handler");
        self.mls_sync_state_update_handler = Some(Arc::new(Mutex::new(Box::new({
            move |state, reason| {
                Box::new(callback(state, reason)) as Box<dyn Future<Output = ()> + Send + Unpin>
            }
        }))));
    }

    #[cfg(target_family = "wasm")]
    pub fn set_mls_sync_state_update_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(MlsSyncState, Option<RejoinReason>) -> Fut + 'static,
        Fut: Future<Output = ()> + Unpin + 'static,
    {
        self.mls_sync_state_update_handler = Some(Arc::new(Mutex::new(Box::new({
            move |state, reason| {
                Box::new(callback(state, reason)) as Box<dyn Future<Output = ()> + Unpin>
            }
        }))));
    }

    #[cfg(target_family = "wasm")]
    pub fn set_livekit_admin_change_handler<F, Fut>(&mut self, callback: F)
    where
        F: Fn(String, String, u32) -> Fut + 'static,
        Fut: Future<Output = ()> + Unpin + 'static,
    {
        self.livekit_admin_change_handler = Some(Arc::new(Mutex::new(Box::new({
            move |room_id, participant_uid, participant_type| {
                Box::new(callback(room_id, participant_uid, participant_type))
                    as Box<dyn Future<Output = ()> + Unpin>
            }
        }))));
    }

    /// Helper function to get the current epoch for a room
    async fn get_current_epoch(&self, room_id: &str) -> Result<u64, anyhow::Error> {
        let store = self.mls_store.read().await;
        let mls_group = store
            .group_map
            .get(room_id)
            .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
            .read()
            .await;
        Ok(*mls_group.epoch())
    }

    /// Helper function to get the current group id for a room
    async fn get_current_group_id(&self, room_id: &str) -> Result<Vec<u8>, anyhow::Error> {
        let store = self.mls_store.read().await;
        let mls_group = store
            .group_map
            .get(room_id)
            .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
            .read()
            .await;

        // Get group_context from mls_group
        let group_info_mls_types = mls_group
            .group_info_for_ext_commit()
            .await
            .map_err(|e| anyhow::anyhow!("Failed to get group_info_for_ext_commit: {e:?}"))?;

        let group_info_bytes = group_info_mls_types
            .mls_encode_to_vec()
            .map_err(|e| anyhow::anyhow!("Failed to encode group_info: {e:?}"))?;

        let group_info_message = mls_spec::messages::MlsMessage::from_tls_bytes(&group_info_bytes)
            .map_err(|e| anyhow::anyhow!("Failed to parse group_info message: {e:?}"))?;

        let group_info = match group_info_message.content {
            mls_spec::messages::MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => return Err(anyhow::anyhow!("Invalid group info content")),
        };

        let group_context = &group_info.group_context;

        // Get group_id from group_context
        let group_id = group_context.group_id().to_vec();

        Ok(group_id)
    }

    async fn process_cached_messages(&self, room_id: &str) -> Result<(), anyhow::Error> {
        #[cfg(debug_assertions)]
        tracing::info!("Processing cached messages for room {}", room_id);
        let mut total_processed_epochs = Vec::<u64>::new();
        let max_iterations = 10; // Prevent infinite loops
        let mut iteration = 0;

        loop {
            iteration += 1;
            if iteration > max_iterations {
                tracing::warn!(
                "Max iterations ({}) reached for cached message processing in room {}, stopping",
                max_iterations,
                room_id
            );
                break;
            }

            // Get current epoch once and use it for both filtering and validation
            let current_epoch = self.get_current_epoch(room_id).await?;

            // Get all processable epochs (epochs <= current_epoch) and sort them
            let mut processable_epochs = self
                .message_cache
                .lock()
                .await
                .get_processable_epochs(room_id, current_epoch);
            processable_epochs.sort();

            if processable_epochs.is_empty() {
                tracing::debug!("No more cached epochs to process for room {}", room_id);
                break;
            }

            #[cfg(debug_assertions)]
            tracing::info!(
                "Iteration {}: Processing {} cached epochs for room {} (current epoch: {}): {:?}",
                iteration,
                processable_epochs.len(),
                room_id,
                current_epoch,
                processable_epochs
            );

            // Use swap_remove for O(1) removal (order doesn't matter after selection)
            let epoch_to_process = processable_epochs.swap_remove(0);

            let mut epoch_advanced = false;

            // Epoch revalidation: Check if this epoch is still processable
            // The group epoch might have advanced since we started this iteration.
            // We need a fresh check here because the epoch could have advanced between
            // getting the processable epochs list and selecting this specific epoch.
            let current_group_epoch = self.get_current_epoch(room_id).await?;

            // Skip epochs that are no longer processable due to group advancement
            if epoch_to_process > current_group_epoch {
                tracing::debug!(
                    "Skipping epoch {} for room {} (now greater than current group epoch {})",
                    epoch_to_process,
                    room_id,
                    current_group_epoch
                );
                continue;
            }

            let cached_messages = match self
                .message_cache
                .lock()
                .await
                .get_messages_for_epoch(room_id, epoch_to_process)
            {
                Some(messages) if !messages.is_empty() => messages,
                Some(_) => {
                    tracing::debug!(
                        "No messages found for epoch {} in room {} (empty epoch entry)",
                        epoch_to_process,
                        room_id
                    );
                    continue;
                }
                None => {
                    tracing::debug!(
                        "Epoch {} no longer exists in cache for room {} (may have been cleaned up)",
                        epoch_to_process,
                        room_id
                    );
                    continue;
                }
            };

            tracing::info!(
                "Processing {} cached messages for room {} at epoch {} (group epoch: {})",
                cached_messages.len(),
                room_id,
                epoch_to_process,
                current_group_epoch
            );

            let mut epoch_success = true;
            let mut early_break_due_to_epoch_advance = false;

            for (message_type, cached_message) in cached_messages {
                match message_type {
                    CachedMessageType::Proposal => {
                        match self
                            .process_proposal_message(cached_message.message, room_id)
                            .await
                        {
                            Ok(_) => {}
                            Err(e) => {
                                tracing::warn!(
                                    "Failed to process cached proposal for room {} at epoch {}: {}",
                                    room_id,
                                    epoch_to_process,
                                    e
                                );
                                epoch_success = false;
                                break;
                            }
                        }
                    }
                    CachedMessageType::Commit => {
                        match self
                            .process_commit_message(cached_message.message, room_id)
                            .await
                        {
                            Ok(CommitProcessingOutcome::Applied) => {
                                // Commit processed successfully, epoch may have advanced.
                                epoch_advanced = true;

                                // Revalidate epoch after commit processing
                                let new_group_epoch = self.get_current_epoch(room_id).await?;

                                // If epoch advanced significantly, break to start fresh iteration
                                if new_group_epoch > current_group_epoch {
                                    tracing::info!(
                                            "Group epoch advanced from {} to {} after commit, breaking to revalidate cached messages",
                                            current_group_epoch,
                                            new_group_epoch
                                        );
                                    // Mark that we're breaking early due to epoch advancement, not failure
                                    early_break_due_to_epoch_advance = true;
                                    break;
                                }
                            }
                            Ok(CommitProcessingOutcome::NoStateChange) => {}
                            Ok(CommitProcessingOutcome::DeferredFutureEpoch) => {}
                            Err(e) => {
                                tracing::warn!(
                                    "Failed to process cached commit for room {} at epoch {}: {}",
                                    room_id,
                                    epoch_to_process,
                                    e
                                );
                                epoch_success = false;
                                break;
                            }
                        }
                    }
                }
            }

            // If we broke due to epoch advancement, still consider the epoch successful
            if early_break_due_to_epoch_advance {
                epoch_success = true;
            }

            if epoch_success {
                tracing::info!(
                    "Successfully processed cached messages for room {} at epoch {}",
                    room_id,
                    epoch_to_process
                );

                // Clean up successfully processed epochs
                let mut cache = self.message_cache.lock().await;
                cache.remove_processed_messages(room_id, epoch_to_process);
                #[cfg(debug_assertions)]
                tracing::info!(
                    "Cleaned up processed cached messages for room {} epochs: {:?}",
                    room_id,
                    epoch_to_process
                );
                total_processed_epochs.push(epoch_to_process);

                // continue to the next iteration, so we can process the next epoch until it failed
                if early_break_due_to_epoch_advance {
                    tracing::debug!(
                        "Breaking from epoch processing loop due to epoch advancement for room {}",
                        room_id
                    );
                    continue;
                }
            } else {
                tracing::warn!(
                        "Failed to process some cached messages for room {} at epoch {}, stopping cache processing",
                        room_id,
                        epoch_to_process
                    );
                break;
            }

            // If no epoch advancement occurred, we're done
            if !epoch_advanced {
                tracing::debug!(
                    "No epoch advancement in iteration {}, stopping cache processing for room {}",
                    iteration,
                    room_id
                );
                break;
            }
        }

        if !total_processed_epochs.is_empty() {
            #[cfg(debug_assertions)]
            tracing::info!(
                "Completed cached message processing for room {}: processed {} epochs total in {} iterations: {:?}",
                room_id,
                total_processed_epochs.len(),
                iteration,
                total_processed_epochs
            );
        }

        // Clean up old cached messages to prevent memory leaks
        // Keep messages for up to 10 epochs behind current epoch
        let final_epoch = self.get_current_epoch(room_id).await?;

        // Remove cached messages that are older than current epoch
        self.message_cache
            .lock()
            .await
            .cleanup_old_messages(room_id, final_epoch, 0);

        Ok(())
    }

    async fn process_commit_message(
        &self,
        commit_message: mls_types::MlsMessage,
        room_id: &str,
    ) -> Result<CommitProcessingOutcome, anyhow::Error> {
        let epoch_of_commit = commit_message
            .epoch()
            .ok_or(anyhow::anyhow!("Expected commit to have an epoch"))?;

        // Get epoch via MLS store adapter (through the service's port)
        // We need to access it directly from mls_store for now since we need the epoch before processing
        let mls_group_epoch = self.get_current_epoch(room_id).await?;

        tracing::info!(
            "Before processing commit message. epoch: {:?}",
            mls_group_epoch
        );

        match epoch_of_commit.cmp(&mls_group_epoch) {
            Ordering::Less => {
                tracing::info!(
                    "Received commit message with old epoch. commit epoch: {:?}, group epoch: {:?}",
                    epoch_of_commit,
                    mls_group_epoch
                );
                // Old commit is expected during backlog replay; ignore without extra cache churn.
                return Ok(CommitProcessingOutcome::NoStateChange);
            }
            Ordering::Equal => {}
            Ordering::Greater => {
                tracing::info!(
                    "Received commit message with future epoch. epoch: {:?}",
                    epoch_of_commit
                );
                self.cache_commit_message(room_id, commit_message).await?;
                return Ok(CommitProcessingOutcome::DeferredFutureEpoch);
            }
        }

        // lock whole process_commit_message
        let mut proposal_lock = self.proposal_queue.lock().await;
        let mut queued_proposals: Vec<QueuedProposal> =
            proposal_lock.remove(room_id).unwrap_or_else(Vec::new);

        // Process proposals outside the lock
        // handle the proposals in the queue before we process the commit message
        for queued_proposal in &queued_proposals {
            let result = self
                .handle_proposal(room_id, queued_proposal.proposal_message.clone())
                .await;
            if let Err(e) = result {
                tracing::warn!("Failed to handle proposal in the queue: {:?}", e);
            }
        }

        // handle proposals from message_cache for this epoch
        if let Some(cached_messages) = self
            .message_cache
            .lock()
            .await
            .get_messages_for_epoch(room_id, mls_group_epoch)
        {
            for (message_type, cached_message) in cached_messages {
                if let CachedMessageType::Proposal = message_type {
                    let result = self
                        .handle_proposal(room_id, cached_message.message.clone())
                        .await;
                    if let Err(e) = result {
                        tracing::warn!(
                            "Failed to handle proposal from message_cache for epoch {}: {:?}",
                            mls_group_epoch,
                            e
                        );
                    }
                }
            }
        }

        let store = self.mls_store.read().await;
        let mut mls_group = store
            .group_map
            .get(room_id)
            .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
            .write()
            .await;

        let use_psk = {
            let guard = self.use_psk.lock().await;
            *guard
        };
        if use_psk {
            if let Err(e) = Self::validate_psk_proposal(commit_message.clone(), room_id) {
                // PSK validation failed: stop the group and discard queued proposals.
                drop(proposal_lock);
                drop(mls_group);
                crate::service::utils::restore_to_queue(
                    self.proposal_queue.clone(),
                    room_id.to_string(),
                    std::mem::take(&mut queued_proposals),
                    "Failed to process commit message",
                );
                return Err(e);
            }
        }

        let result = mls_group.decrypt_message(commit_message.clone()).await;
        let (received_message, _reinit) = match result {
            Ok((received_message, reinit)) => (received_message, reinit),
            Err(e) => {
                tracing::error!("Failed to decrypt commit message: {:?}", e);
                drop(proposal_lock);
                crate::service::utils::restore_to_queue(
                    self.proposal_queue.clone(),
                    room_id.to_string(),
                    std::mem::take(&mut queued_proposals),
                    "Failed to process commit message",
                );
                return Err(anyhow::Error::from(e));
            }
        };
        match received_message {
            ReceivedMessage::Commit { ref output, .. } => {
                if use_psk {
                    let expected_id = room_id.as_bytes();
                    let has_psk = output.applied_proposals.iter().any(|p| {
                        matches!(
                            &p.effect,
                            mls_trait::types::ProposalEffect::PskAdded {
                                reference: mls_types::PskReference::External(mls_types::ExternalPskId(id))
                            } if id.as_slice() == expected_id
                        )
                    });
                    if !has_psk {
                        tracing::error!("Commit missing required PSK proposal for room {room_id}");
                        drop(proposal_lock);
                        drop(mls_group);
                        crate::service::utils::restore_to_queue(
                            self.proposal_queue.clone(),
                            room_id.to_string(),
                            std::mem::take(&mut queued_proposals),
                            "Commit missing PSK proposal",
                        );
                        return Err(anyhow::Error::from(ServiceError::PskProposalMissing));
                    }
                }
            }
            ReceivedMessage::Error(mls_types::MlsTypesError::MlsClientError(
                mls_rs::client::MlsError::ProposalNotFound,
            )) => {
                tracing::error!("Proposal not found in commit message");
                self.cache_commit_message(room_id, commit_message).await?;
                drop(proposal_lock);
                crate::service::utils::restore_to_queue(
                    self.proposal_queue.clone(),
                    room_id.to_string(),
                    std::mem::take(&mut queued_proposals),
                    "Failed to process commit message",
                );
                return Err(anyhow::Error::from(ServiceError::ProposalNotFound));
            }
            ReceivedMessage::Duplicate => {
                tracing::info!("Received duplicated commit message");
                drop(proposal_lock);
                crate::service::utils::restore_to_queue(
                    self.proposal_queue.clone(),
                    room_id.to_string(),
                    std::mem::take(&mut queued_proposals),
                    "Received duplicated commit message",
                );
                return Ok(CommitProcessingOutcome::NoStateChange);
            }
            _ => {
                tracing::error!("Received message is not a commit: {:?}", received_message);
                drop(proposal_lock);
                crate::service::utils::restore_to_queue(
                    self.proposal_queue.clone(),
                    room_id.to_string(),
                    std::mem::take(&mut queued_proposals),
                    "Failed to process commit message",
                );
                return Err(anyhow::Error::from(ServiceError::InvalidMlsMessageType));
            }
        }

        let new_epoch = *mls_group.epoch();
        tracing::info!("Commit message processed. epoch: {:?}", new_epoch);

        drop(proposal_lock);
        drop(mls_group);

        // trigger the group update callback outside of locks to prevent lock inversion
        if let Some(handler) = self.mls_group_update_handler.as_ref() {
            let mut handler = handler.lock().await;
            handler(room_id.to_string()).await;
        }

        let _unused_proposals = match received_message {
            ReceivedMessage::Commit { output, .. } => output.unused_proposals,
            _ => Vec::new(),
        };

        // Check if epoch advanced (it should have, since we processed a commit)
        // Only check if epoch changed from the original epoch
        if new_epoch > mls_group_epoch {
            // Epoch advanced, check and update host role if needed
            if let Err(e) = self.check_and_update_host_role(room_id).await {
                tracing::warn!(
                    "Failed to check and update host role after epoch change: {:?}",
                    e
                );
                // Don't fail the commit processing if role update fails
            }
        }

        // TODO: handle the unused proposals and recreate if needed

        Ok(CommitProcessingOutcome::Applied)
    }

    // receive proposal message
    // the host client will need to create the commit and broadcast to server
    // the other clients will need to decrypt the proposal to prepare for the comming commit
    async fn process_proposal_message(
        &self,
        proposal_message: mls_types::MlsMessage,
        room_id: &str,
    ) -> Result<ProposalProcessingOutcome, anyhow::Error> {
        // self.handle_proposal(&room_id, proposal_message.clone())
        //     .await?;

        let proposal = match proposal_message.clone().as_proposal() {
            Some(p) => {
                let mls_types_proposal: mls_types::Proposal = p.clone().try_into()?;
                mls_types_proposal
            }
            None => return Ok(ProposalProcessingOutcome::NoStateChange),
        };

        let proposal_epoch = proposal_message
            .epoch()
            .ok_or(anyhow::anyhow!("Expected proposal to have an epoch"))?;
        let current_epoch = self.get_current_epoch(room_id).await?;

        match proposal_epoch.cmp(&current_epoch) {
            Ordering::Less => {
                tracing::info!(
                    "Received proposal message with old epoch. proposal epoch: {:?}, group epoch: {:?}",
                    proposal_epoch,
                    current_epoch
                );
                return Ok(ProposalProcessingOutcome::NoStateChange);
            }
            Ordering::Equal => {}
            Ordering::Greater => {
                tracing::info!(
                    "Received proposal message with future epoch. proposal epoch: {:?}, group epoch: {:?}",
                    proposal_epoch,
                    current_epoch
                );
                self.cache_proposal_message(room_id, proposal_message)
                    .await?;
                return Ok(ProposalProcessingOutcome::DeferredFutureEpoch);
            }
        }

        match &proposal {
            mls_types::Proposal::Remove(_)
            | mls_types::Proposal::Add(_)
            | mls_types::Proposal::AppDataUpdate(_) => {
                // add the proposal to the queue
                let proposal_type = match &proposal {
                    mls_types::Proposal::Add(_) => ProposalType::Add,
                    mls_types::Proposal::Remove(_) => ProposalType::Remove,
                    mls_types::Proposal::AppDataUpdate(_) => ProposalType::AppDataUpdate,
                    _ => unreachable!(),
                };
                let queued_proposal = QueuedProposal {
                    proposal_message: proposal_message.clone(),
                    proposal_type,
                };
                {
                    let mut queue = self.proposal_queue.lock().await;
                    queue
                        .entry(room_id.to_string())
                        .or_insert_with(Vec::new)
                        .push(queued_proposal);
                }
            }
            _ => {
                let type_name = match proposal {
                    mls_types::Proposal::Add(_) => "ADD",
                    mls_types::Proposal::Remove(_) => "REMOVE",
                    mls_types::Proposal::Update(_) => "UPDATE",
                    mls_types::Proposal::Psk(_) => "PSK",
                    mls_types::Proposal::ReInit(_) => "RE_INIT",
                    mls_types::Proposal::ExternalInit(_) => "EXTERNAL_INIT",
                    mls_types::Proposal::GroupContextExtensions(_) => "GROUP_CONTEXT_EXTENSIONS",
                    mls_types::Proposal::AppDataUpdate(_) => "APP_DATA_UPDATE",
                    mls_types::Proposal::AppEphemeral(_) => "APP_EPHEMERAL",
                };
                tracing::warn!(
                    "Received proposal is not an expected proposal, it is {} proposal",
                    type_name
                );
            }
        }

        let mls_group = {
            let mls_group_lock = {
                let store_lock = self.mls_store.read().await;
                store_lock
                    .group_map
                    .get(room_id)
                    .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
                    .clone()
            };
            let mls_group = mls_group_lock.read().await;
            mls_group.clone()
        };

        let self_leaf_index = mls_group.own_leaf_index()?;
        let epoch_at = *mls_group.epoch();
        let deterministic_random_rank = self
            .get_deterministic_random_rank(
                *self_leaf_index,
                epoch_at,
                mls_group.roster().collect::<Vec<_>>(),
            )
            .await?;
        let rank_group = deterministic_random_rank / RANK_GROUP_SIZE;

        tracing::debug!(
            "deterministic_random_rank: {:?}, rank_group: {:?}",
            deterministic_random_rank,
            rank_group
        );

        // Calculate delay: random component (0-2000ms) + group-based component (0-5000ms per group)
        // Total delay range: 0ms to (20 * 100 + rank_group * 5000)ms
        let random_jitter = rand::thread_rng().gen_range(0..=20);
        let delay_ms = random_jitter * DELAY_PER_RANK_MS + rank_group * RANK_GROUP_DELAY_MS;

        self.clone()
            .start_proposal_timer(room_id.to_string(), delay_ms, epoch_at, rank_group);
        // TODO: Refactor this designated committer selection logic based on proposal type
        // and try to avoid shuffle() for efficiency if needed
        Ok(ProposalProcessingOutcome::Applied)
    }

    /// Validate the PSK proposal in the incoming commit message
    /// If the MLS message is a commit message, validate the PSK proposal in the commit message.
    /// It must contain a PSK proposal with the expected ID (`room_id.as_bytes()`).
    fn validate_psk_proposal(
        mls_message: mls_types::MlsMessage,
        room_id: &str,
    ) -> Result<(), anyhow::Error> {
        if let MlsMessagePayload::Plain(public_message) = mls_message.mls_message.payload {
            if let Content::Commit(commit) = public_message.content.content {
                let proposals = commit.proposals;
                let mut has_psk = false;
                for proposal in proposals {
                    if let ProposalOrRef::Proposal(proposal) = proposal {
                        if let Proposal::Psk(psk) = proposal.as_ref() {
                            if let Some(psk_id) = psk.external_psk_id() {
                                has_psk = true;
                                if psk_id.to_vec() != room_id.as_bytes() {
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

    async fn cache_commit_message(
        &self,
        room_id: &str,
        commit_message: mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error> {
        self.mls_service
            .cache_commit_message(room_id, commit_message)
            .await
    }

    async fn cache_proposal_message(
        &self,
        room_id: &str,
        proposal_message: mls_types::MlsMessage,
    ) -> Result<(), anyhow::Error> {
        self.mls_service
            .cache_proposal_message(room_id, proposal_message)
            .await
    }

    async fn handle_offline_members(&self, room_id: &str) -> Result<(), anyhow::Error> {
        {
            let mut running = self.handling_offline_members.lock().await;
            if *running {
                tracing::debug!("handle_offline_members is already running, skipping");
                return Ok(());
            }
            *running = true;
        }

        let result = self.handle_offline_members_impl(room_id).await;

        {
            let mut running = self.handling_offline_members.lock().await;
            *running = false;
        }

        result
    }

    async fn handle_offline_members_impl(&self, room_id: &str) -> Result<(), anyhow::Error> {
        let mut mls_group: MlsGroup<MemKv> = {
            let mls_group_lock = {
                let store_lock = self.mls_store.read().await;
                store_lock
                    .group_map
                    .get(room_id)
                    .ok_or_else(|| anyhow::anyhow!("Failed to find mls group for room {room_id}"))?
                    .clone()
            };
            let mls_group = mls_group_lock.read().await;
            mls_group.clone()
        };
        let epoch = *mls_group.epoch();

        // Skip if we've already handled offline members for this epoch
        {
            let state_lock = self.state.lock().await;
            if state_lock.has_handled_offline_members_for_epoch(epoch) {
                tracing::debug!("Already handled offline members at epoch {}", epoch);
                return Ok(());
            }
        }

        let authorizer = mls_group.authorizer()?;
        let self_leaf_index = mls_group.own_leaf_index()?;
        let mut member = mls_group.find_member(self_leaf_index)?;
        let identity = ProtonMeetIdentityProvider::user_identifier(&member.user_id()?);
        let current_role = authorizer.role_for_user(epoch, &identity)?;
        if current_role.role_index == UserRole::RoomAdmin as u32 {
            tracing::debug!(
                "Current role is ChannelManager, will check offline users and remove them if needed"
            );
        } else {
            tracing::debug!("Current role is not ChannelManager");
            return Ok(());
        }

        let roster = mls_group.roster().collect::<Vec<_>>();
        let offline_indices = self.get_offline_indices(roster).await?;
        if offline_indices.is_empty() {
            return Ok(());
        }

        tracing::debug!(
            "Detect offline members at epoch {}: {:?}",
            epoch,
            offline_indices
        );

        // Build active_participants (current roster) and identities of members we are removing
        let mut active_participants = HashSet::new();
        let mut to_remove = Vec::new();
        let mut proposal_args: Vec<ProposalArg> = Vec::new();

        for mut m in mls_group.roster() {
            let user_id = m.user_id()?;
            let identity = ProtonMeetIdentityProvider::user_identifier(&user_id);
            active_participants.insert(identity.clone());
            let li = m.leaf_index();
            if offline_indices.contains(&(*li)) {
                to_remove.push(identity);
            }
        }

        for offline_index in &offline_indices {
            proposal_args.push(ProposalArg::Remove(LeafIndex::try_from(*offline_index)?));
        }
        for identity in to_remove {
            proposal_args.extend(
                authorizer
                    .role_proposal_for_removed_user(epoch, &identity, &active_participants)?
                    .into_iter()
                    .map(|component| ProposalArg::UpdateComponent {
                        id: component.component_id,
                        data: component.data,
                    }),
            );
        }

        let use_psk = {
            let use_psk_guard = self.use_psk.lock().await;
            *use_psk_guard
        };

        if use_psk {
            proposal_args.push(ProposalArg::PskExternal {
                id: ExternalPskId(room_id.as_bytes().to_vec()),
            });
        }

        let (commit_bundle, _welcome_option) = match mls_group.new_commit(proposal_args).await {
            Ok((bundle, welcome)) => (bundle, welcome),
            Err(e) => {
                tracing::error!(
                    "Failed to create commit bundle for offline members: {:?}",
                    e
                );
                return Err(e.into());
            }
        };

        let group_info = commit_bundle
            .group_info
            .ok_or(anyhow::anyhow!("Missing group info in commit bundle"))?;
        let ratchet_tree = commit_bundle
            .ratchet_tree
            .ok_or(anyhow::anyhow!("Missing ratchet tree in commit bundle"))?;

        let group_info_message = convert_mls_types_to_spec(&group_info)?;
        let ratchet_tree_option = ratchet_tree
            .try_into()
            .map_err(|e| anyhow::anyhow!("Failed to convert ratchet tree: {e}"))?;

        let welcome = commit_bundle.welcome.map(TryInto::try_into).transpose()?;
        let commit_info = MlsCommitInfo {
            room_id: room_id.as_bytes().to_vec(),
            welcome_message: welcome,
            commit: convert_mls_types_to_spec(&commit_bundle.commit)?,
        };

        let base64_sd_kbt = self
            .get_sd_kbt(&UserId::new(mls_group.own_user_id()?.to_string()))
            .await?;

        match self
            .http_client
            .update_group_info(
                &base64_sd_kbt,
                &group_info_message,
                &ratchet_tree_option,
                Some(&commit_info),
                None,
            )
            .await
        {
            Ok(_) => {
                mls_group.merge_pending_commit().await?;
                self.mls_store
                    .write()
                    .await
                    .group_map
                    .entry(room_id.to_string())
                    .and_modify(|group| {
                        *group = Arc::new(RwLock::new(mls_group));
                    });
                let mut state_lock = self.state.lock().await;
                state_lock.mark_offline_members_handled_for_epoch(epoch);
            }
            Err(e) => {
                mls_group.clear_pending_commit();
                mls_group.clear_pending_proposals();
                return Err(e.into());
            }
        }

        Ok(())
    }
}

#[cfg(not(target_family = "wasm"))]
#[cfg(test)]
impl Service {
    pub async fn get_cached_message(&self) -> Result<Arc<Mutex<MlsMessageCache>>, anyhow::Error> {
        Ok(self.message_cache.clone())
    }
}

impl std::fmt::Debug for Service {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Service")
            .field("http_client", &"<HttpClient>")
            .field("user_repository", &"<UserRepository>")
            .field("active_groups", &"<HashMap>")
            .finish()
    }
}

#[cfg(not(target_family = "wasm"))]
#[cfg(test)]
#[path = "service_test.rs"]
mod service_test;
