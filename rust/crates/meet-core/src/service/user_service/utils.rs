use std::{collections::HashMap, sync::Arc, time::Duration};

use identity::ProtonMeetIdentity;
use meet_type::fanout::GroupInfoVersion;
use mls_types::{Credential, ExternalPskId};
use proton_claims::ClientType;
use proton_meet_mls::{MlsGroup, MlsGroupTrait, kv::MemKv};
use tokio::sync::Mutex;

use crate::{
    service::user_service::{QueuedProposal, Service},
    utils::{sleep, spawn_detached},
};

pub const DELAY_PER_RANK_MS: u64 = 100;
pub const RANK_GROUP_SIZE: u64 = 3;
pub const RANK_GROUP_DELAY_MS: u64 = 5000;
pub const LIVEKIT_OFFLINE_THRESHOLD_MS: u64 = 60_000;

// Kick participant retry configuration
pub const KICK_MAX_ATTEMPTS: u32 = 4; // 1 initial + 3 retries
pub const KICK_BASE_DELAY_MS: u64 = 500;
pub const KICK_MAX_DELAY_MS: u64 = 10000;

pub const WR_SETTING_MAX_ATTEMPTS: u32 = 3;

// Supported group info versions for the client
pub const SUPPORTED_GROUP_INFO_VERSIONS: [GroupInfoVersion; 2] =
    [GroupInfoVersion::V1, GroupInfoVersion::V2];

pub fn mimi_sub_from_credential(credential: &Credential) -> Result<String, anyhow::Error> {
    match credential {
        Credential::SdCwtDraft04 { sd_kbt, .. } => {
            let mut sd_kbt = sd_kbt.as_ref().clone();
            Ok(ProtonMeetIdentity::sub(&mut sd_kbt)?.to_string())
        }
        _ => Err(anyhow::anyhow!("Expected SdCwtDraft04 credential")),
    }
}

/// True iff `credential` is from a server-issued (agent) identity. Read off
/// `ProtonMeetClaims.client_type`, the same flag the auth service stamps
/// onto agent SD-CWTs at issuance.
pub fn credential_is_agent(credential: &Credential) -> bool {
    matches!(
        credential,
        Credential::SdCwtDraft04 {
            claimset: Some(claimset),
            ..
        } if claimset.client_type == ClientType::Agent
    )
}

/// True iff any leaf in `mls_group`'s roster is an agent.
pub fn group_has_agent(mls_group: &MlsGroup<MemKv>) -> bool {
    mls_group
        .roster()
        .any(|m| credential_is_agent(&m.credential))
}

/// True if any leaf in the GroupInfo's ratchet tree is an agent. Used at
/// External-Commit-join time when there's no local `MlsGroup` yet.
pub fn ratchet_tree_option_has_agent(
    tree_option: &mls_trait::mls_spec::drafts::ratchet_tree_options::RatchetTreeOption,
) -> bool {
    let Ok(tree) = mls_types::PublicRatchetTree::try_from(tree_option.clone()) else {
        return false;
    };
    public_ratchet_tree_has_agent(&tree)
}

/// Same predicate as [`ratchet_tree_option_has_agent`] but takes the
/// already-converted [`PublicRatchetTree`]. Used by call sites that have it
/// in hand (e.g. `mls_service::join_group_via_external_commit`) to avoid a
/// redundant `TryFrom`.
pub fn public_ratchet_tree_has_agent(tree: &mls_types::PublicRatchetTree) -> bool {
    // Collect first so the iterator (which borrows the tree) doesn't outlive
    // its source across the boolean fold.
    let members: Vec<_> = tree.members().collect();
    members
        .into_iter()
        .any(|m| match mls_types::Member::try_from(m) {
            Ok(member) => credential_is_agent(&member.credential),
            Err(_) => false,
        })
}

/// Select the PSK id for a commit. Uses the meeting-scoped agent PSK id
/// (`agent-psk-id.{link}`) if the group contains an agent leaf.
/// Otherwise falls back to the meeting-link-name PSK (the id the human-only path has always used).
pub fn psk_id_for_commit(meeting_link_name: &str, has_agent: bool) -> ExternalPskId {
    if has_agent {
        ExternalPskId(
            crate::service::agent_host_service::agent_psk_id_for_meeting(meeting_link_name),
        )
    } else {
        ExternalPskId(meeting_link_name.as_bytes().to_vec())
    }
}

/// Stagger return: caller proceeds, or bails because another participant
/// already did the work during the wait.
pub enum StaggerOutcome {
    Proceed,
    HandledElsewhere,
}

/// How long each rank group waits before it will summon or dismiss the captions
/// agent itself. Longer than the MLS stagger: the wait has to cover the round
/// trip of another participant's request plus the agent joining the group,
/// otherwise every rank asks for an agent that is already on its way.
const AGENT_REQUEST_RANK_GROUP_DELAY_MS: u64 = 8000;

/// Shared rank-staggered wait used by `admit_agent` and `remove_agent`.
/// Sleeps for `jitter * DELAY_PER_RANK_MS + (rank / RANK_GROUP_SIZE) * RANK_GROUP_DELAY_MS`
/// then re-reads the group's epoch — if it advanced during the wait, the
/// caller is no longer the designated committer for this event and should
/// no-op. Same shape as the stagger inside `process_proposal_message`.
pub async fn stagger_then_check_epoch(
    service: &Service,
    room_id: &str,
    rank: u64,
    epoch_at_start: u64,
    op_name: &str,
) -> StaggerOutcome {
    use rand::Rng as _;
    let rank_group = rank / RANK_GROUP_SIZE;
    let random_jitter = rand::thread_rng().gen_range(0..=20);
    let delay_ms = random_jitter * DELAY_PER_RANK_MS + rank_group * RANK_GROUP_DELAY_MS;
    tracing::info!(
        op = op_name,
        rank,
        rank_group,
        delay_ms,
        epoch_at_start,
        "designated-committer stagger"
    );
    sleep(Duration::from_millis(delay_ms)).await;

    match service.get_current_epoch(room_id).await {
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
    service: &Service,
    room_id: &str,
    rank: u64,
    want_agent: bool,
    op_name: &str,
) -> StaggerOutcome {
    use rand::Rng as _;
    let rank_group = rank / RANK_GROUP_SIZE;
    let random_jitter = rand::thread_rng().gen_range(0..=20);
    let delay_ms =
        random_jitter * DELAY_PER_RANK_MS + rank_group * AGENT_REQUEST_RANK_GROUP_DELAY_MS;
    tracing::info!(
        op = op_name,
        rank,
        rank_group,
        delay_ms,
        want_agent,
        "designated-committer stagger"
    );
    sleep(Duration::from_millis(delay_ms)).await;

    if service.captions_agent_in_group(room_id).await == want_agent {
        tracing::info!(
            op = op_name,
            "another participant handled it during the stagger, skipping"
        );
        return StaggerOutcome::HandledElsewhere;
    }

    StaggerOutcome::Proceed
}

/// Calculate retry delay with exponential backoff and jitter
/// - attempt_num: 0-indexed attempt number (0 = first retry after initial failure)
/// - base_ms: base delay in milliseconds
/// - max_ms: maximum delay cap
pub fn calculate_retry_delay(attempt_num: u32, base_ms: u64, max_ms: u64) -> u64 {
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
pub fn restore_proposals_to_queue(
    proposal_queue: &Arc<Mutex<HashMap<String, Vec<QueuedProposal>>>>,
    meeting_link_name: String,
    proposals: Vec<QueuedProposal>,
    reason: &str,
) {
    if proposals.is_empty() {
        return;
    }

    let reason = reason.to_string();
    spawn_detached({
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
