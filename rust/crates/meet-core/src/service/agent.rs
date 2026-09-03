use std::sync::Arc;

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

use crate::{
    domain::user::ports::{MlsApi, UserService},
    infra::mimi_subject_parser::MimiSubject,
    service::{
        user_service::{
            credential_is_agent,
            utils::{mimi_sub_from_credential, stagger_then_check_epoch, StaggerOutcome},
            GroupKeyUpdateReason, Service,
        },
        utils::convert_mls_types_to_spec,
    },
};

#[cfg(not(target_family = "wasm"))]
pub(crate) type ArcAgentService = Arc<dyn AgentService + Send + Sync + 'static>;
#[cfg(target_family = "wasm")]
pub(crate) type ArcAgentService = Arc<dyn AgentService + 'static>;

#[async_trait_with_mock]
pub(crate) trait AgentService {
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
}

pub(crate) struct AgentServiceImpl {
    mls_api: Arc<dyn MlsApi>,
    mls_store: Arc<RwLock<MlsStore>>,
    user_service: Arc<RwLock<Service>>,
}

impl AgentServiceImpl {
    pub fn new(
        mls_api: Arc<dyn MlsApi>,
        mls_store: Arc<RwLock<MlsStore>>,
        user_service: Arc<RwLock<Service>>,
    ) -> Self {
        Self {
            mls_api,
            mls_store,
            user_service,
        }
    }
}

#[async_trait]
impl AgentService for AgentServiceImpl {
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

        let group_arc = {
            let store_lock = self.mls_store.read().await;
            store_lock
                .group_map
                .get(&room_id)
                .ok_or_else(|| anyhow::anyhow!("group not loaded for meeting"))?
                .clone()
        };

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
            let mls_group = group_arc.read().await;
            self.user_service
                .read()
                .await
                .committer_rank(&mls_group)
                .await?
        };

        if let StaggerOutcome::HandledElsewhere = stagger_then_check_epoch(
            &*self.user_service.read().await,
            &room_id,
            rank,
            epoch_at_start,
            "admit_agent",
        )
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

        self.user_service
            .read()
            .await
            .handlers
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
        let group_arc = {
            let store_lock = self.mls_store.read().await;
            store_lock
                .group_map
                .get(&room_id)
                .ok_or_else(|| anyhow::anyhow!("group not loaded for meeting"))?
                .clone()
        };

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

        if let StaggerOutcome::HandledElsewhere = stagger_then_check_epoch(
            &*self.user_service.read().await,
            &room_id,
            rank,
            epoch_at_start,
            "remove_agent",
        )
        .await
        {
            return Ok(());
        }

        let host_sd_kbt = self.user_service.read().await.get_sd_kbt(user_id).await?;
        let mut mls_group = group_arc.write().await;

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

                self.user_service
                    .read()
                    .await
                    .handlers
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
}
