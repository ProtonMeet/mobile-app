use std::str::FromStr;

use meet_identifiers::UserId;
use mls_spec::{Serializable, drafts::ratchet_tree_options::RatchetTreeOption};
use mls_trait::{
    ProposalArg,
    meet_policy::{RoomKind, RoomPolicies},
    mimi_protocol_mls::UserIdentifier,
};
use mls_types::ExternalPskId;
use proton_meet_mls::{MlsGroup, MlsGroupTrait, kv::MemKv};

use crate::{
    errors::core::MeetCoreError,
    infra::dto::realtime::{
        MlsCommitInfo, RTCMessageIn, RTCMessageInContent, RatchetTreeAndGroupInfo,
    },
    service::{
        user_service::Service,
        utils::{convert_mls_types_to_spec, ensure_room_admin},
    },
};

pub struct WaitingRoomPolicyCommit {
    pub group_info_tls: Vec<u8>,
    pub ratchet_tree: RatchetTreeOption,
    pub commit_data: Vec<u8>,
}

fn user_id_from_identifier(identifier: &UserIdentifier) -> Result<UserId, MeetCoreError> {
    let user_id = std::str::from_utf8(identifier).map_err(|e| MeetCoreError::MlsProtocolError {
        message: format!("Invalid participant user identifier: {e}"),
    })?;
    UserId::from_str(user_id).map_err(|e| MeetCoreError::MlsProtocolError {
        message: format!("Invalid meeting creator user id: {e}"),
    })
}

/// Meeting creator is always the last entry in the MLS participant list (see `RoomPolicies::participant_list`).
fn meeting_creator_user_id(mls_group: &MlsGroup<MemKv>) -> Result<UserId, MeetCoreError> {
    let list = mls_group
        .participant_list()?
        .ok_or_else(|| MeetCoreError::MlsProtocolError {
            message: "No participant list in group".to_string(),
        })?;
    let creator_identifier = list
        .participants
        .last()
        .map(|p| p.user.clone())
        .ok_or_else(|| MeetCoreError::MlsProtocolError {
            message: "Participant list is empty".to_string(),
        })?;
    user_id_from_identifier(&creator_identifier)
}

fn other_users_from_participant_list(
    mls_group: &MlsGroup<MemKv>,
    creator: &UserId,
) -> Result<Vec<UserId>, MeetCoreError> {
    let creator_identifier = UserIdentifier::from(creator.to_string());
    let Some(list) = mls_group.participant_list()? else {
        return Ok(vec![]);
    };

    list.participants
        .iter()
        .filter(|p| p.user != creator_identifier)
        .map(|p| user_id_from_identifier(&p.user))
        .collect()
}

fn encode_waiting_room_policy_commit(
    commit_bundle: &proton_meet_mls::CommitBundle,
    meeting_link_name: &str,
) -> Result<WaitingRoomPolicyCommit, MeetCoreError> {
    let group_info =
        commit_bundle
            .group_info
            .as_ref()
            .ok_or_else(|| MeetCoreError::MlsProtocolError {
                message: "Missing group info in waiting-room policy commit".to_string(),
            })?;
    let ratchet_tree =
        commit_bundle
            .ratchet_tree
            .as_ref()
            .ok_or_else(|| MeetCoreError::MlsProtocolError {
                message: "Missing ratchet tree in waiting-room policy commit".to_string(),
            })?;

    let group_info_message = convert_mls_types_to_spec(group_info)?;
    let ratchet_tree_option: RatchetTreeOption =
        ratchet_tree
            .clone()
            .try_into()
            .map_err(|e| MeetCoreError::MlsProtocolError {
                message: format!("Failed to convert ratchet tree: {e}"),
            })?;

    let group_info_tls = RatchetTreeAndGroupInfo {
        ratchet_tree: ratchet_tree_option.clone(),
        group_info: group_info_message,
    }
    .to_tls_bytes()
    .map_err(|e| MeetCoreError::MlsProtocolError {
        message: format!("Failed to encode group info payload: {e}"),
    })?;

    let commit_info = MlsCommitInfo {
        room_id: meeting_link_name.as_bytes().to_vec(),
        welcome_message: None,
        commit: convert_mls_types_to_spec(&commit_bundle.commit)?,
    };
    let commit_data = RTCMessageIn {
        content: RTCMessageInContent::SendCommit(commit_info),
    }
    .to_tls_bytes()
    .map_err(|e| MeetCoreError::MlsProtocolError {
        message: format!("Failed to encode commit payload: {e}"),
    })?;

    Ok(WaitingRoomPolicyCommit {
        group_info_tls,
        ratchet_tree: ratchet_tree_option,
        commit_data,
    })
}

pub async fn build_waiting_room_policy_commit(
    mls_group: &mut MlsGroup<MemKv>,
    meeting_link_name: &str,
    enable: bool,
) -> Result<WaitingRoomPolicyCommit, MeetCoreError> {
    ensure_room_admin(mls_group)?;

    let creator = meeting_creator_user_id(mls_group)?;
    let other_users = other_users_from_participant_list(mls_group, &creator)?;
    let room_kind = if enable {
        RoomKind::BasicRoomWithWaiting { other_users }
    } else {
        RoomKind::BasicHostedRoom {
            is_open: true,
            other_users,
        }
    };

    let committer_is_host = Service::is_host_from_credential(mls_group)?;
    let policies = RoomPolicies::new(&creator, &room_kind, committer_is_host).map_err(|e| {
        MeetCoreError::MlsProtocolError {
            message: e.to_string(),
        }
    })?;

    let proposals = [
        ProposalArg::update_component(&policies.roles)?,
        ProposalArg::update_component(&policies.pre_auth)?,
        ProposalArg::PskExternal {
            id: ExternalPskId(meeting_link_name.as_bytes().to_vec()),
        },
    ];

    let (commit_bundle, _) = mls_group.new_commit(proposals).await?;

    match encode_waiting_room_policy_commit(&commit_bundle, meeting_link_name) {
        Ok(commit) => Ok(commit),
        Err(error) => {
            abort_waiting_room_policy_commit(mls_group);
            Err(error)
        }
    }
}

pub async fn merge_waiting_room_policy_commit(
    mls_group: &mut MlsGroup<MemKv>,
) -> Result<(), MeetCoreError> {
    mls_group.merge_pending_commit().await?;
    Ok(())
}

pub fn abort_waiting_room_policy_commit(mls_group: &mut MlsGroup<MemKv>) {
    mls_group.clear_pending_commit();
    mls_group.clear_pending_proposals();
}
