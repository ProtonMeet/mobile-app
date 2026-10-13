use mls_rs::CryptoProvider;
use mls_rs_codec::MlsEncode;
use mls_spec::{Parsable, Serializable};
use mls_trait::meet_policy::UserRole;
use mls_types::{Credential, Member, Proposal};
use proton_meet_mls::{MlsGroup, MlsGroupTrait, kv::MemKv};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::errors::core::MeetCoreError;
use crate::service::user_service::QueuedProposal;
use crate::utils::spawn_detached;

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

pub(crate) fn ensure_room_admin(mls_group: &MlsGroup<MemKv>) -> Result<(), MeetCoreError> {
    let role = mls_group.own_role_for_current_epoch()?;
    if role.role_index != UserRole::RoomAdmin.builder().role_index {
        return Err(MeetCoreError::NotRoomAdmin);
    }
    Ok(())
}

pub fn get_uuid_from_member(member: &mut Member) -> Result<Uuid, anyhow::Error> {
    match &mut member.credential {
        Credential::SdCwtDraft04 { sd_kbt, .. } => {
            let sd_cwt_payload = sd_kbt.0.sd_cwt_payload()?;
            let extra = sd_cwt_payload
                .inner
                .extra
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("no extra payload"))?;
            let uuid_bytes = &extra.uuid;
            Uuid::from_slice(uuid_bytes).map_err(|e| anyhow::anyhow!("Failed to parse UUID: {e}"))
        }
        _ => Err(anyhow::anyhow!("other credential: {:?}", member.credential)),
    }
}

/// Extracts UUID from a KeyPackage's credential.
/// Returns None if the credential is not SdCwt or if UUID extraction fails.
pub fn get_uuid_from_key_package(key_package: &mls_rs::KeyPackage) -> Option<Uuid> {
    let credential: Credential = key_package
        .leaf_node
        .signing_identity
        .credential
        .clone()
        .try_into()
        .ok()?;
    if let Credential::SdCwtDraft04 { sd_kbt, .. } = credential {
        let mut sd_kbt = *sd_kbt;
        let sd_cwt_payload = sd_kbt.0.sd_cwt_payload().ok()?;
        let extra = sd_cwt_payload.inner.extra.as_ref()?;
        let uuid_slice: &[u8; 16] = extra.uuid.as_slice().try_into().ok()?;
        Some(Uuid::from_bytes(*uuid_slice))
    } else {
        None
    }
}

pub async fn get_key_package_reference(
    key_package: &mls_rs::KeyPackage,
) -> Result<[u8; 32], anyhow::Error> {
    let crypto_provider =
        mls_rs_crypto_rustcrypto::RustCryptoProvider::with_enabled_cipher_suites(vec![
            key_package.cipher_suite,
        ]);
    if let Some(cs_provider) = crypto_provider.cipher_suite_provider(key_package.cipher_suite) {
        let reference = key_package.to_reference(&cs_provider).await?;
        let slice: &[u8] = reference.as_ref();
        let array: [u8; 32] = slice
            .try_into()
            .map_err(|e: std::array::TryFromSliceError| {
                anyhow::anyhow!("Key package reference is not 32 bytes: {e:?}")
            })?;
        Ok(array)
    } else {
        Err(anyhow::anyhow!("Cipher suite not supported"))
    }
}

/// Describes the kind of proposal message
pub fn describe_proposal_kind(proposal_message: &mls_types::MlsMessage) -> Option<&'static str> {
    proposal_message
        .as_proposal()
        .and_then(|proposal| {
            let typed: Result<Proposal, _> = proposal.clone().try_into();
            typed.ok()
        })
        .map(|proposal| match proposal {
            Proposal::Add(_) => "ADD",
            Proposal::Remove(_) => "REMOVE",
            Proposal::Update(_) => "UPDATE",
            Proposal::Psk(_) => "PSK",
            Proposal::ReInit(_) => "RE_INIT",
            Proposal::ExternalInit(_) => "EXTERNAL_INIT",
            Proposal::GroupContextExtensions(_) => "GROUP_CONTEXT_EXTENSIONS",
            Proposal::AppDataUpdate(_) => "APP_DATA_UPDATE",
            Proposal::AppEphemeral(_) => "APP_EPHEMERAL",
        })
}

/// Converts mls_types::MlsMessage to mls_spec::messages::MlsMessage
pub fn convert_mls_types_to_spec(
    message: &mls_types::MlsMessage,
) -> Result<mls_spec::messages::MlsMessage, anyhow::Error> {
    let encoded = message.mls_encode_to_vec()?;
    mls_spec::messages::MlsMessage::from_tls_bytes(&encoded)
        .map_err(|e| anyhow::anyhow!("Failed to convert mls_types to mls_spec: {e}"))
}

/// Converts mls_spec::messages::MlsMessage to mls_types::MlsMessage
pub fn convert_mls_spec_to_types(
    message: &mls_spec::messages::MlsMessage,
) -> Result<mls_types::MlsMessage, anyhow::Error> {
    let encoded = message
        .to_tls_bytes()
        .map_err(|e| anyhow::anyhow!("Failed to serialize mls_spec message: {e}"))?;
    mls_types::MlsMessage::from_bytes(&encoded)
        .map_err(|e| anyhow::anyhow!("Failed to convert mls_spec to mls_types: {e}"))
}

/// Restores items to the queue asynchronously when processing fails.
/// This function spawns a detached task to avoid blocking the error return path.
/// Items are appended to existing queue entries, not replaced.
pub fn restore_to_queue<T>(
    queue: Arc<Mutex<HashMap<String, Vec<T>>>>,
    room_id: String,
    items: Vec<T>,
    error_context: &str,
) where
    T: Send + 'static,
{
    if !items.is_empty() {
        let items_count = items.len();
        let error_context = error_context.to_string();
        crate::utils::spawn_detached(async move {
            let mut queue_lock = queue.lock().await;
            tracing::warn!(
                "{}: restoring {} items to queue for room {}",
                error_context,
                items_count,
                room_id
            );
            queue_lock
                .entry(room_id)
                .or_insert_with(Vec::new)
                .extend(items);
        });
    }
}

/// Restores items to the queue synchronously in the current task.
/// Items are appended to existing queue entries, not replaced.
pub async fn restore_to_queue_sync<T>(
    queue: Arc<Mutex<HashMap<String, Vec<T>>>>,
    room_id: String,
    items: Vec<T>,
    error_context: &str,
) where
    T: Send,
{
    if !items.is_empty() {
        let items_count = items.len();
        let mut queue_lock = queue.lock().await;
        tracing::warn!(
            "{}: restoring {} items to queue for room {}",
            error_context,
            items_count,
            room_id
        );
        queue_lock
            .entry(room_id)
            .or_insert_with(Vec::new)
            .extend(items);
    }
}

/// Restore queued proposals back to the proposal queue on failure
pub(crate) fn restore_proposals_to_queue(
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

#[cfg(not(target_family = "wasm"))]
#[cfg(test)]
#[path = "utils_test.rs"]
mod utils_test;
