use std::collections::HashSet;

use crate::{
    domain::user::models::UserId,
    service::{user_service::Service, utils::convert_mls_spec_to_types},
};
use identity::Disclosure;
use mls_spec::{
    defs::ProtocolVersion,
    drafts::ratchet_tree_options::RatchetTreeOption,
    group::group_info::GroupInfo,
    messages::{MlsMessage, MlsMessageContent},
};
use mls_trait::{AuthorizerExt, MlsGroupTrait, ProposalArg, ProtonMeetIdentityProvider};
use proton_meet_mls::{kv::MemKv, CipherSuite, MlsClientTrait, MlsGroup};

impl Service {
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
}
