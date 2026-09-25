use std::{collections::HashSet, sync::Arc, time::Duration};

use meet_identifiers::AsOwned;
use meet_type::fanout::MlsCommitInfo;
use mls_spec::{
    drafts::ratchet_tree_options::RatchetTreeOption, messages::MlsMessageContent, Serializable,
};
use mls_trait::{
    meet_policy::UserRole, AuthorizerExt, MlsClientTrait, MlsGroupTrait, ProposalArg,
    ProtonMeetIdentityProvider,
};
use mls_types::ExternalPskId;
use proton_meet_macro::{async_trait, async_trait_with_mock};
use proton_meet_mls::MlsStore;
use tokio::sync::RwLock;
use tracing::error;

use crate::{
    domain::user::{
        models::meeting_link_name::MeetingLinkName,
        ports::{meeting_api::MeetingApi, MlsApi, UserService},
    },
    infra::mimi_subject_parser::MimiSubject,
    service::{
        compute_stagger_time,
        user_service::{
            credential_is_agent,
            utils::{group_has_agent, mimi_sub_from_credential, StaggerOutcome},
            GroupKeyUpdateReason, Service,
        },
        utils::convert_mls_types_to_spec,
        StaggerStats, RANK_GROUP_DELAY_MS,
    },
    utils::{sleep, sync::SyncRwLock},
};

/// How long each rank group waits before it will summon or dismiss the captions
/// agent itself. Longer than the MLS stagger: the wait has to cover the round
/// trip of another participant's request plus the agent joining the group,
/// otherwise every rank asks for an agent that is already on its way.
const AGENT_REQUEST_RANK_GROUP_DELAY_MS: u64 = 8000;

#[cfg(not(target_family = "wasm"))]
pub(crate) type ArcCaptionService = Arc<dyn CaptionService + Send + Sync + 'static>;
#[cfg(target_family = "wasm")]
pub(crate) type ArcCaptionService = Arc<dyn CaptionService + 'static>;

#[async_trait_with_mock]
pub(crate) trait CaptionService {
    /// Host-side flow: admit an STT agent into the meeting's MLS group.
    /// Runs on a host (a regular meeting member who knows the meeting password).
    ///
    /// 1. `GET /v1/agent/keypackage?agent_device_id=...`: fetch agent's KP.
    /// 2. `derive_agent_external_psk`: compute the HKDF-derived agent PSK
    ///    every member already holds under `agent-psk-id.{link}`.
    /// 3. `AgentHostService::seal_psk_for_agent`: HPKE.Seal to agent's HPKE PK.
    /// 4. Take the group write lock, re-check epoch, build the commit
    ///    (`new_commit([PskExternal, Add])`), upload via `update_group_info`
    ///    while still holding the lock, merge on success or clear the
    ///    pending commit on failure.
    /// 5. `POST /v1/agent/bundle`: push encrypted PSK + Welcome + ratchet
    ///    tree to meet-server so the agent's WS subscriber receives an
    ///    `RTCMessageInContent::AgentBundle` binary frame.
    async fn admit_agent(
        &self,
        meeting_link_name: &crate::domain::user::models::meeting_link_name::MeetingLinkName,
        user_id: &crate::domain::user::models::UserId,
        agent_device_id: String,
        meeting_password: String,
    ) -> Result<(), anyhow::Error>;

    /// Respond to a server-pushed `AgentLeft` event by removing the agent's
    /// MLS leaf, rotating the SFrame epoch for forward secrecy.
    async fn remove_agent(
        &self,
        meeting_link_name: &crate::domain::user::models::meeting_link_name::MeetingLinkName,
        user_id: &crate::domain::user::models::UserId,
        agent_device_id: String,
    ) -> Result<(), anyhow::Error>;

    /// `GET /v1/agent/keypackagesv`: list the `mimi_device_id`s of every agent
    /// whose KeyPackage is currently uploaded for the host's meeting.
    async fn list_pending_agents(
        &self,
        user_id: &crate::domain::user::models::UserId,
    ) -> Result<Vec<String>, anyhow::Error>;

    /// Ask meet-server for the live-captions agent.
    ///
    /// Every participant that wants captions can call this. The rank-staggered
    /// wait means the request is normally made once, by the lowest-ranked
    /// participant, and the others take over in turn if the agent never turns
    /// up — so a wedged or slow participant can't keep captions from starting.
    /// Whether captions are wanted at all stays with the caller.
    async fn request_closed_captions(
        &self,
        meeting_link_name: &MeetingLinkName,
    ) -> Result<(), anyhow::Error>;

    async fn stop_closed_captions(
        &self,
        meeting_link_name: &MeetingLinkName,
    ) -> Result<(), anyhow::Error>;

    async fn set_closed_captions_availability_as_host(
        &self,
        meeting_link_name: &MeetingLinkName,
        available: bool,
    ) -> Result<(), anyhow::Error>;

    async fn reset(&self);
}

pub(crate) struct CaptionServiceImpl {
    mls_api: Arc<dyn MlsApi>,
    mls_store: Arc<RwLock<MlsStore>>,
    user_service: Arc<RwLock<Service>>,
    meeting_api: Arc<dyn MeetingApi>,
    rooms_awaiting_captions_agent: SyncRwLock<HashSet<String>>,
}

impl CaptionServiceImpl {
    pub fn new(
        mls_api: Arc<dyn MlsApi>,
        mls_store: Arc<RwLock<MlsStore>>,
        user_service: Arc<RwLock<Service>>,
        meeting_api: Arc<dyn MeetingApi>,
    ) -> Self {
        Self {
            mls_api,
            mls_store,
            user_service,
            meeting_api,
            // The program can never panic when locking this, as it only operates insertion/deletion
            // while the lock is held. Hence, recovery is not needed.
            rooms_awaiting_captions_agent: SyncRwLock::new(HashSet::new(), |_| {
                error!("Recovery called for CaptionServiceImpl::rooms_awaiting_captions_agent, this should never happen")
            }),
        }
    }

    /// True while a captions agent holds a leaf in the group. This is what the
    /// stagger below treats as "somebody already asked", so it doubles as the
    /// answer to whether there is anything left to do.
    async fn captions_agent_in_group(&self, room_id: &str) -> bool {
        let Ok(lock) = self.mls_store.read().await.find_group(room_id) else {
            return false;
        };
        let guard = lock.read().await;
        group_has_agent(&*guard)
    }

    async fn settle_closed_captions(
        &self,
        meeting_link_name: &crate::domain::user::models::meeting_link_name::MeetingLinkName,
        want_agent: bool,
    ) -> Result<(), anyhow::Error> {
        let room_id = meeting_link_name.as_str().to_string();
        let op_name = if want_agent {
            "request_closed_captions"
        } else {
            "stop_closed_captions"
        };

        let agent_in_group = self.captions_agent_in_group(&room_id).await;

        if want_agent && agent_in_group {
            self.set_awaiting_captions_agent(&room_id, false);
            tracing::info!(op = op_name, "agent already in the group, skipping");
            return Ok(());
        }

        if !want_agent && !agent_in_group {
            // An agent we asked for that hasn't turned up yet is invisible to
            // everyone else, so cancelling it is ours to do, and without the
            // wait: staggering would only let the agent join a meeting nobody
            // wants it in.
            if self.is_awaiting_captions_agent(&room_id) {
                self.meeting_api
                    .remove_closed_captions_agent(&room_id)
                    .await?;
                self.set_awaiting_captions_agent(&room_id, false);
                tracing::info!(op = op_name, "cancelled our own request");
            } else {
                tracing::info!(op = op_name, "no agent to remove, skipping");
            }

            return Ok(());
        }

        let group_arc = {
            let store_lock = self.mls_store.read().await;
            store_lock
                .group_map
                .get(&room_id)
                .ok_or_else(|| anyhow::anyhow!("group not loaded for meeting"))?
                .clone()
        };
        let rank = {
            let service = self.user_service.read().await;
            let mls_group = group_arc.read().await;
            service.committer_rank(&mls_group).await?.1
        };

        if let StaggerOutcome::HandledElsewhere = self
            .stagger_then_check_agent(&room_id, rank, want_agent, op_name)
            .await
        {
            return Ok(());
        }

        if want_agent {
            self.meeting_api.add_closed_captions_agent(&room_id).await?;
        } else {
            self.meeting_api
                .remove_closed_captions_agent(&room_id)
                .await?;
        }
        self.set_awaiting_captions_agent(&room_id, want_agent);
        tracing::info!(op = op_name, rank, "asked meet-server");

        Ok(())
    }

    /// Remembered until the agent turns up, the request is cancelled, or the
    /// meeting is torn down.
    fn set_awaiting_captions_agent(&self, room_id: &str, awaiting: bool) {
        let mut set = self.rooms_awaiting_captions_agent.write();

        if awaiting {
            set.insert(room_id.to_string());
        } else {
            set.remove(room_id);
        }
    }

    fn is_awaiting_captions_agent(&self, room_id: &str) -> bool {
        self.rooms_awaiting_captions_agent.read().contains(room_id)
    }

    /// Shared rank-staggered wait used by `admit_agent` and `remove_agent`.
    /// Sleeps for `jitter * DELAY_PER_RANK_MS + (rank / RANK_GROUP_SIZE) * RANK_GROUP_DELAY_MS`
    /// then re-reads the group's epoch — if it advanced during the wait, the
    /// caller is no longer the designated committer for this event and should
    /// no-op. Same shape as the stagger inside `process_proposal_message`.
    pub async fn stagger_then_check_epoch(
        &self,
        room_id: &str,
        rank: u64,
        epoch_at_start: u64,
        op_name: &str,
    ) -> StaggerOutcome {
        let StaggerStats {
            delay_ms,
            rank_group,
        } = compute_stagger_time(rank, RANK_GROUP_DELAY_MS);

        tracing::info!(
            op = op_name,
            rank,
            rank_group,
            delay_ms,
            epoch_at_start,
            "designated-committer stagger"
        );

        sleep(Duration::from_millis(delay_ms)).await;

        match self
            .user_service
            .read()
            .await
            .get_current_epoch(room_id)
            .await
        {
            Ok(current) if current != epoch_at_start => {
                tracing::info!(
                    op = op_name,
                    epoch_at_start,
                    current,
                    "epoch advanced during stagger, another participant handled it, skipping"
                );
                StaggerOutcome::HandledElsewhere
            }
            Ok(_) => StaggerOutcome::Proceed,
            Err(e) => {
                tracing::warn!(
                    op = op_name,
                    "failed to get current epoch after stagger: {e:?}"
                );
                StaggerOutcome::Proceed
            }
        }
    }

    /// Same rank-staggered wait for the captions-agent requests, which are HTTP
    /// calls rather than commits: asking meet-server for an agent doesn't advance
    /// the group's epoch, so what tells us another participant already handled it is
    /// the agent turning up in (or disappearing from) the group.
    pub async fn stagger_then_check_agent(
        &self,
        room_id: &str,
        rank: u64,
        want_agent: bool,
        op_name: &str,
    ) -> StaggerOutcome {
        let StaggerStats {
            delay_ms,
            rank_group,
        } = compute_stagger_time(rank, AGENT_REQUEST_RANK_GROUP_DELAY_MS);

        tracing::info!(
            op = op_name,
            rank,
            rank_group,
            delay_ms,
            want_agent,
            "designated-committer stagger"
        );

        sleep(Duration::from_millis(delay_ms)).await;

        if self.captions_agent_in_group(room_id).await == want_agent {
            tracing::info!(
                op = op_name,
                "another participant handled it during the stagger, skipping"
            );
            return StaggerOutcome::HandledElsewhere;
        }

        StaggerOutcome::Proceed
    }
}

#[async_trait]
impl CaptionService for CaptionServiceImpl {
    /// Host-side flow: admit an STT agent into the meeting's MLS group.
    /// Runs on a host (a regular meeting member who knows the meeting password).
    ///
    /// 1. `GET /v1/agent/keypackage?agent_device_id=...`: fetch agent's KP.
    /// 2. `derive_agent_external_psk`: compute the HKDF-derived agent PSK
    ///    every member already holds under `agent-psk-id.{link}`.
    /// 3. `AgentHostService::seal_psk_for_agent`: HPKE.Seal to agent's HPKE PK.
    /// 4. Take the group write lock, re-check epoch, build the commit
    ///    (`new_commit([PskExternal, Add])`), upload via `update_group_info`
    ///    while still holding the lock, merge on success or clear the
    ///    pending commit on failure.
    /// 5. `POST /v1/agent/bundle`: push encrypted PSK + Welcome + ratchet
    ///    tree to meet-server so the agent's WS subscriber receives an
    ///    `RTCMessageInContent::AgentBundle` binary frame.
    async fn admit_agent(
        &self,
        meeting_link_name: &crate::domain::user::models::meeting_link_name::MeetingLinkName,
        user_id: &crate::domain::user::models::UserId,
        agent_device_id: String,
        meeting_password: String,
    ) -> Result<(), anyhow::Error> {
        use crate::service::agent_host_service::{
            agent_psk_id_for_meeting, AgentBundleForPush, AgentHostService,
        };
        use mls_rs_codec::MlsDecode as _;

        let psk_id_bytes = agent_psk_id_for_meeting(meeting_link_name.as_str());
        let room_id = meeting_link_name.as_str().to_string();

        let group_arc = self.mls_store.read().await.find_group(&room_id)?;

        {
            use std::str::FromStr;
            let mls_group = group_arc.read().await;
            let already_present = mls_group.roster().any(|m| {
                mimi_sub_from_credential(m.credential())
                    .ok()
                    .and_then(|uri| MimiSubject::from_str(&uri).ok())
                    .map(|mimi| mimi.device_id() == agent_device_id)
                    .unwrap_or(false)
            });
            if already_present {
                tracing::info!(
                    "admit_agent: device_id={agent_device_id} already in roster, skipping"
                );
                return Ok(());
            }
        }

        let (epoch_at_start, rank) = {
            let service = self.user_service.read().await;
            let mls_group = group_arc.read().await;
            service.committer_rank(&mls_group).await?
        };

        if let StaggerOutcome::HandledElsewhere = self
            .stagger_then_check_epoch(&room_id, rank, epoch_at_start, "admit_agent")
            .await
        {
            return Ok(());
        }

        // Unlocked prep — network + CPU-only work, before we grab the group
        // write lock.
        let host_sd_kbt = self.user_service.read().await.get_sd_kbt(user_id).await?;
        let agent_kp = self
            .mls_api
            .fetch_agent_keypackage(&host_sd_kbt, &agent_device_id)
            .await?;
        let agent_kp_bytes = agent_kp.key_package;
        let agent_hpke_pk = agent_kp.hpke_public_key;

        let cs = {
            let mls_store = self.mls_store.read().await;
            mls_store.config.ciphersuite
        };
        let meeting_psk = crate::infra::crypto_client::derive_external_psk(
            &meeting_password,
            meeting_link_name.as_str(),
        )?;
        let agent_psk = crate::infra::crypto_client::derive_agent_external_psk(&meeting_psk)?;
        let psk: &[u8] = &agent_psk.0;
        let encrypted_psk = AgentHostService::seal_psk_for_agent(&agent_hpke_pk, psk, cs)
            .await
            .map_err(|e| anyhow::anyhow!("seal_psk: {e}"))?;

        // Insert the PSK on the client before we take the group lock. Client
        // and group are different lock domains; ordering here avoids nesting.
        {
            let mls_store = self.mls_store.write().await;
            let client = mls_store.find_client(&user_id.to_string(), &cs)?;
            client
                .insert_external_psk(
                    ExternalPskId(psk_id_bytes.clone()),
                    mls_types::ExternalPsk(psk.to_vec()),
                )
                .await?;
        }

        let agent_kp_typed = {
            let mut slice = agent_kp_bytes.as_slice();
            mls_types::KeyPackage::mls_decode(&mut slice)
                .map_err(|e| anyhow::anyhow!("decode agent KP: {e:?}"))?
        };

        {
            let cred = agent_kp_typed
                .credential()
                .map_err(|e| anyhow::anyhow!("admit_agent: agent KP credential: {e:?}"))?;
            if !credential_is_agent(&cred) {
                anyhow::bail!(
                    "admit_agent: refusing to admit device_id={agent_device_id}: KP credential is not ClientType::Agent"
                );
            }
        }

        // Take the group write lock and hold it across new_commit → upload →
        // merge/clear. Matches `remove_agent`: safe against concurrent WS
        // commit processing racing our un-merged pending commit.
        let mut mls_group = group_arc.write().await;

        // TOCTOU re-check: the stagger validated the epoch, then we spent time
        // on network + crypto. If the epoch advanced in that window, another
        // committer beat us — bail before starting a redundant commit.
        let current_epoch = *mls_group.epoch();
        if current_epoch != epoch_at_start {
            tracing::info!(
                op = "admit_agent",
                epoch_at_start,
                current_epoch,
                "epoch advanced between stagger and lock, another admin handled it, skipping"
            );
            return Ok(());
        }

        let agent_role_update = {
            let mut cred = agent_kp_typed
                .credential()
                .map_err(|e| anyhow::anyhow!("admit_agent: agent KP credential: {e:?}"))?;
            let device_id = cred
                .device_id()
                .map_err(|e| anyhow::anyhow!("admit_agent: agent KP device_id: {e:?}"))?;
            let owning_identity_id = device_id.owning_identity_id().as_owned();
            let identifier = ProtonMeetIdentityProvider::user_identifier(&owning_identity_id);
            let epoch = *mls_group.epoch();
            mls_group
                .authorizer()?
                .role_proposal_for_added_user(epoch, identifier, UserRole::Agent)?
                .map(|component| ProposalArg::UpdateComponent {
                    id: component.component_id,
                    data: component.data,
                })
                .ok_or_else(|| {
                    anyhow::anyhow!(
                        "admit_agent: role_proposal_for_added_user returned None (Agent role change not authorized)"
                    )
                })?
        };

        let (commit_bundle, _) = mls_group
            .new_commit(vec![
                ProposalArg::PskExternal {
                    id: ExternalPskId(psk_id_bytes.clone()),
                },
                ProposalArg::Add(Box::new(agent_kp_typed)),
                agent_role_update,
            ])
            .await
            .map_err(|e| anyhow::anyhow!("admit_agent new_commit: {e:?}"))?;

        let welcome_mls_types = commit_bundle
            .welcome
            .ok_or_else(|| anyhow::anyhow!("admit_agent: commit produced no welcome"))?;
        let welcome_spec = convert_mls_types_to_spec(&welcome_mls_types)?;
        let welcome_value = match welcome_spec.content {
            MlsMessageContent::Welcome(w) => w,
            _ => {
                mls_group.clear_pending_commit();
                return Err(anyhow::anyhow!(
                    "admit_agent: commit welcome not a Welcome variant"
                ));
            }
        };
        let group_info = commit_bundle
            .group_info
            .ok_or_else(|| anyhow::anyhow!("admit_agent: commit bundle missing group_info"))?;
        let ratchet_tree = commit_bundle
            .ratchet_tree
            .ok_or_else(|| anyhow::anyhow!("admit_agent: commit bundle missing ratchet_tree"))?;

        let group_info_message = convert_mls_types_to_spec(&group_info)?;
        let ratchet_tree_option: RatchetTreeOption = ratchet_tree
            .try_into()
            .map_err(|e| anyhow::anyhow!("admit_agent: ratchet_tree convert: {e:?}"))?;

        let commit_info = MlsCommitInfo {
            room_id: meeting_link_name.as_str().as_bytes().to_vec(),
            welcome_message: Some(welcome_value.clone()),
            commit: convert_mls_types_to_spec(&commit_bundle.commit)?,
        };

        // Upload while still holding the group lock. On failure, clear the
        // pending commit so the host stays at epoch N. On success, merge and
        // release.
        let upload = self
            .mls_api
            .update_group_info(
                &host_sd_kbt,
                &group_info_message,
                &ratchet_tree_option,
                Some(&commit_info),
                None,
            )
            .await;

        match upload {
            Ok(_) => {
                mls_group.merge_pending_commit().await?;
            }
            Err(e) => {
                mls_group.clear_pending_commit();
                return Err(anyhow::anyhow!("update_group_info: {e}"));
            }
        }

        drop(mls_group);

        // Clone handlers to avoid possible deadlock on `self.user_service`
        let handlers = self.user_service.read().await.handlers.clone();
        handlers
            .call_mls_group_update_handler(room_id, GroupKeyUpdateReason::Join)
            .await;

        // push_bundle after the merge — server has already accepted the commit
        // and other members will process it via fanout, so the group has moved
        // to N+1 regardless of whether the agent gets its bundle. If
        // push_bundle fails, the agent's KP will time out and the host can
        // retry admission; the group state remains consistent.
        let welcome_bytes = welcome_value
            .to_tls_bytes()
            .map_err(|e| anyhow::anyhow!("welcome tls encode: {e:?}"))?;
        let ratchet_tree_option_bytes = ratchet_tree_option
            .to_tls_bytes()
            .map_err(|e| anyhow::anyhow!("ratchet_tree_option tls encode: {e:?}"))?;
        let host = AgentHostService::new(self.mls_api.clone(), self.mls_store.clone());
        host.push_bundle(
            &host_sd_kbt,
            AgentBundleForPush {
                agent_device_id,
                psk_id: psk_id_bytes,
                encrypted_psk,
                welcome: welcome_bytes,
                ratchet_tree: ratchet_tree_option_bytes,
            },
        )
        .await
        .map_err(|e| anyhow::anyhow!("push_bundle: {e}"))?;

        Ok(())
    }

    async fn remove_agent(
        &self,
        meeting_link_name: &crate::domain::user::models::meeting_link_name::MeetingLinkName,
        user_id: &crate::domain::user::models::UserId,
        agent_device_id: String,
    ) -> Result<(), anyhow::Error> {
        use std::str::FromStr;

        let room_id = meeting_link_name.as_str().to_string();
        let group_arc = self.mls_store.read().await.find_group(&room_id)?;

        let (epoch_at_start, leaf_index, is_admin) = {
            let mls_group = group_arc.read().await;
            let epoch_at = *mls_group.epoch();
            let role = mls_group.own_role_for_current_epoch()?;
            let is_admin = role.role_index == UserRole::RoomAdmin as u32;
            let leaf = mls_group.roster().find_map(|m| {
                let mimi_uri = mimi_sub_from_credential(m.credential()).ok()?;
                let mimi = MimiSubject::from_str(&mimi_uri).ok()?;
                (mimi.device_id() == agent_device_id).then(|| m.leaf_index())
            });
            (epoch_at, leaf, is_admin)
        };

        let Some(leaf_index) = leaf_index else {
            tracing::debug!(
                "remove_agent: device_id={agent_device_id} not in roster (already removed?), skipping"
            );
            return Ok(());
        };

        let rank = if is_admin {
            0
        } else {
            let (roster, self_leaf_index) = {
                let mls_group = group_arc.read().await;
                (
                    mls_group.roster().collect::<Vec<_>>(),
                    *mls_group.own_leaf_index()?,
                )
            };
            self.user_service
                .read()
                .await
                .get_deterministic_random_rank(self_leaf_index, epoch_at_start, roster)
                .await?
        };

        if let StaggerOutcome::HandledElsewhere = self
            .stagger_then_check_epoch(&room_id, rank, epoch_at_start, "remove_agent")
            .await
        {
            return Ok(());
        }

        let host_sd_kbt = self.user_service.read().await.get_sd_kbt(user_id).await?;
        let mut mls_group = group_arc.write().await;

        // TOCTOU re-check: the stagger validated the epoch, then we spent time
        // on network + crypto. If the epoch advanced in that window, another
        // committer beat us — bail before starting a redundant commit.
        let current_epoch = *mls_group.epoch();
        if current_epoch != epoch_at_start {
            tracing::info!(
                op = "remove_agent",
                epoch_at_start,
                current_epoch,
                "epoch advanced between stagger and lock, another committer handled it, skipping"
            );
            return Ok(());
        }

        let proposal_args = vec![
            ProposalArg::Remove(leaf_index),
            ProposalArg::PskExternal {
                id: ExternalPskId(
                    crate::service::agent_host_service::agent_psk_id_for_meeting(
                        meeting_link_name.as_str(),
                    ),
                ),
            },
        ];
        let (commit_bundle, _) = mls_group.new_commit(proposal_args).await?;

        let group_info = commit_bundle
            .group_info
            .ok_or_else(|| anyhow::anyhow!("remove_agent: commit bundle missing group_info"))?;
        let ratchet_tree = commit_bundle
            .ratchet_tree
            .ok_or_else(|| anyhow::anyhow!("remove_agent: commit bundle missing ratchet_tree"))?;

        let group_info_message = convert_mls_types_to_spec(&group_info)?;
        let ratchet_tree_option = ratchet_tree
            .try_into()
            .map_err(|e| anyhow::anyhow!("remove_agent: ratchet_tree convert: {e}"))?;
        let welcome = commit_bundle.welcome.map(TryInto::try_into).transpose()?;
        let commit_info = MlsCommitInfo {
            room_id: meeting_link_name.as_str().as_bytes().to_vec(),
            welcome_message: welcome,
            commit: convert_mls_types_to_spec(&commit_bundle.commit)?,
        };

        let upload = self
            .mls_api
            .update_group_info(
                &host_sd_kbt,
                &group_info_message,
                &ratchet_tree_option,
                Some(&commit_info),
                None,
            )
            .await;

        match upload {
            Ok(_) => {
                mls_group.merge_pending_commit().await?;
                drop(mls_group);

                // Clone handlers to avoid possible deadlock on `self.user_service`
                let handlers = self.user_service.read().await.handlers.clone();
                handlers
                    .call_mls_group_update_handler(room_id, GroupKeyUpdateReason::Leave)
                    .await;
                Ok(())
            }
            Err(e) => {
                mls_group.clear_pending_commit();
                Err(anyhow::anyhow!("remove_agent update_group_info: {e}"))
            }
        }
    }

    async fn list_pending_agents(
        &self,
        user_id: &crate::domain::user::models::UserId,
    ) -> Result<Vec<String>, anyhow::Error> {
        let host_sd_kbt = self.user_service.read().await.get_sd_kbt(user_id).await?;

        Ok(self.mls_api.list_agent_keypackages(&host_sd_kbt).await?)
    }

    /// Ask meet-server for the live-captions agent.
    ///
    /// Every participant that wants captions can call this. The rank-staggered
    /// wait means the request is normally made once, by the lowest-ranked
    /// participant, and the others take over in turn if the agent never turns
    /// up — so a wedged or slow participant can't keep captions from starting.
    /// Whether captions are wanted at all stays with the caller.
    async fn request_closed_captions(
        &self,
        meeting_link_name: &MeetingLinkName,
    ) -> Result<(), anyhow::Error> {
        self.settle_closed_captions(meeting_link_name, true).await
    }

    /// Ask meet-server to drop the live-captions agent, arbitrated the same way
    /// as [`Service::request_closed_captions`].
    async fn stop_closed_captions(
        &self,
        meeting_link_name: &MeetingLinkName,
    ) -> Result<(), anyhow::Error> {
        self.settle_closed_captions(meeting_link_name, false).await
    }

    async fn set_closed_captions_availability_as_host(
        &self,
        meeting_link_name: &MeetingLinkName,
        available: bool,
    ) -> Result<(), anyhow::Error> {
        let room_id = meeting_link_name.as_str().to_string();
        self.meeting_api
            .set_closed_captions_agent_availability(&room_id, available)
            .await?;
        Ok(())
    }

    async fn reset(&self) {
        self.rooms_awaiting_captions_agent.write().clear();
    }
}

#[cfg(test)]
#[cfg(not(target_family = "wasm"))]
mod test {
    use std::{future::ready, sync::Arc};

    use proton_meet_macro::unified_test;

    use crate::{
        domain::user::{
            models::meeting_link_name::MeetingLinkName, ports::meeting_api::MockMeetingApi,
        },
        errors::http_client::HttpClientError,
        service::test::{create_test_service_bundle, setup_single_user_group, ServiceBundleDI},
    };

    /// A solo caller is a room admin, so it ranks first and only waits out the
    /// stagger's jitter (up to 2s) before asking.
    #[unified_test]
    async fn request_closed_captions_asks_meet_server_when_no_agent_in_group() {
        let room_id = "captions_request_no_agent";

        let mut meeting_api = MockMeetingApi::new();
        meeting_api
            .expect_add_closed_captions_agent()
            .times(1)
            .withf(move |link| link == room_id)
            .returning(|_| Box::pin(ready(Ok(()))));

        let bundle = setup_single_user_group(
            room_id,
            ServiceBundleDI {
                meeting_api: Some(Arc::new(meeting_api)),
                ..Default::default()
            },
        )
        .await
        .0;

        bundle
            .caption_service
            .request_closed_captions(&MeetingLinkName::from(room_id))
            .await
            .unwrap();
    }

    #[unified_test]
    async fn stop_closed_captions_is_a_no_op_without_an_agent_in_group() {
        let room_id = "captions_stop_no_agent";

        let mut meeting_api = MockMeetingApi::new();
        meeting_api
            .expect_remove_closed_captions_agent()
            .times(0)
            .returning(|_| Box::pin(ready(Ok(()))));

        let bundle = setup_single_user_group(
            room_id,
            ServiceBundleDI {
                meeting_api: Some(Arc::new(meeting_api)),
                ..Default::default()
            },
        )
        .await
        .0;

        bundle
            .caption_service
            .stop_closed_captions(&MeetingLinkName::from(room_id))
            .await
            .unwrap();
    }

    /// The web client cancels a summon the moment demand disappears, before the
    /// agent has joined — the state nobody else can see.
    #[unified_test]
    async fn stop_closed_captions_cancels_our_own_request_before_the_agent_arrives() {
        let room_id = "captions_cancel_in_flight";
        let meeting_name = MeetingLinkName::from(room_id);

        let mut meeting_api = MockMeetingApi::new();
        meeting_api
            .expect_add_closed_captions_agent()
            .times(1)
            .returning(|_| Box::pin(ready(Ok(()))));
        meeting_api
            .expect_remove_closed_captions_agent()
            .times(1)
            .withf(move |link| link == room_id)
            .returning(|_| Box::pin(ready(Ok(()))));

        let (bundle, pop, ..) = setup_single_user_group(
            room_id,
            ServiceBundleDI {
                meeting_api: Some(Arc::new(meeting_api)),
                ..Default::default()
            },
        )
        .await;

        bundle
            .caption_service
            .request_closed_captions(&meeting_name)
            .await
            .unwrap();
        assert!(
            pop.caption_service.is_awaiting_captions_agent(room_id),
            "the request should be remembered until the agent arrives"
        );

        bundle
            .caption_service
            .stop_closed_captions(&meeting_name)
            .await
            .unwrap();
        assert!(
            !pop.caption_service.is_awaiting_captions_agent(room_id),
            "cancelling should clear the outstanding request"
        );
    }

    #[unified_test]
    async fn request_closed_captions_reports_a_failed_request() {
        let room_id = "captions_request_http_error";

        let mut meeting_api = MockMeetingApi::new();
        meeting_api
            .expect_add_closed_captions_agent()
            .times(1)
            .returning(|_| {
                Box::pin(ready(Err(HttpClientError::MlsHttpError {
                    message: "server down".to_string(),
                })))
            });
        let bundle = setup_single_user_group(
            room_id,
            ServiceBundleDI {
                meeting_api: Some(Arc::new(meeting_api)),
                ..Default::default()
            },
        )
        .await
        .0;

        let result = bundle
            .caption_service
            .request_closed_captions(&MeetingLinkName::from(room_id))
            .await;

        assert!(result.is_err(), "a failed request must reach the caller");
    }

    #[unified_test]
    async fn request_closed_captions_needs_a_loaded_group_to_rank_itself() {
        let room_id = "captions_request_no_group";
        let bundle = create_test_service_bundle("captions-no-group", room_id, Default::default()).0;

        let result = bundle
            .caption_service
            .request_closed_captions(&MeetingLinkName::from(room_id))
            .await;

        assert!(
            result.is_err(),
            "without a group there is no rank, so nothing should be sent"
        );
    }
}
