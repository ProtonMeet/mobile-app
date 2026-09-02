//! Host-side helpers for admitting an STT agent into an MLS meeting.

use std::sync::Arc;

use mls_rs::CryptoProvider as _;
use mls_rs_codec::MlsEncode;
use mls_rs_core::crypto::{CipherSuiteProvider, HpkePublicKey};
use mls_rs_crypto_rustcrypto::RustCryptoProvider;
use mls_types::CipherSuite;
use proton_meet_mls::MlsStore;
use tokio::sync::RwLock;

use crate::domain::user::ports::MlsApi;

/// Prefix for the meeting-scoped agent PSK id. The full id is built by [`agent_psk_id_for_meeting`].
pub const AGENT_PSK_ID_PREFIX: &[u8] = b"agent-psk-id.";

/// Build the meeting-scoped PSK id used for every agent-involved commit: `agent-psk-id.{meeting_link_name}`.
pub fn agent_psk_id_for_meeting(meeting_link_name: &str) -> Vec<u8> {
    let link = meeting_link_name.as_bytes();
    let mut id = Vec::with_capacity(AGENT_PSK_ID_PREFIX.len() + link.len());
    id.extend_from_slice(AGENT_PSK_ID_PREFIX);
    id.extend_from_slice(link);
    id
}

/// HPKE seal label, matching what the agent passes to `client.hpke_decrypt`.
pub const PSK_HPKE_LABEL: &str = "agent-psk";

#[derive(Debug, thiserror::Error)]
pub enum AgentHostError {
    #[error("HPKE seal failed: {0}")]
    HpkeSeal(String),
    #[error("KeyPackage decode failed: {0}")]
    KeyPackageDecode(String),
    #[error("MLS group not loaded for meeting {0}")]
    GroupNotLoaded(String),
    #[error("MLS error: {0}")]
    Mls(#[from] mls_trait::MlsError),
    #[error("MLS spec error: {0}")]
    MlsSpec(String),
    #[error("Store error: {0}")]
    Store(#[from] proton_meet_mls::MlsStoreError),
    #[error("HTTP error: {0}")]
    Http(String),
    #[error("serialize error: {0}")]
    Serde(#[from] serde_json::Error),
}

#[derive(Debug, Clone)]
pub struct AgentBundleForPush {
    pub agent_device_id: String,
    pub psk_id: Vec<u8>,
    pub encrypted_psk: Vec<u8>,
    pub welcome: Vec<u8>,
    /// TLS-encoded `RatchetTreeOption`.
    pub ratchet_tree: Vec<u8>,
}

/// Host-side agent admission service. Holds a reference to the MLS store
/// (same one [`crate::service::mls_service::MlsService`] uses) so it can
/// look up the host's group and mutate it via `new_commit`, plus the
/// shared [`MlsApi`] port for the bundle POST.
pub struct AgentHostService {
    mls_api: Arc<dyn MlsApi>,
    #[expect(unused)]
    mls_store: Arc<RwLock<MlsStore>>,
}

impl AgentHostService {
    pub fn new(mls_api: Arc<dyn MlsApi>, mls_store: Arc<RwLock<MlsStore>>) -> Self {
        Self { mls_api, mls_store }
    }

    /// HPKE.Seal the PSK plaintext to the agent's HPKE init key. Uses the
    /// MLS ciphersuite's KEM (X25519 for the Proton default cipher suite).
    pub async fn seal_psk_for_agent(
        agent_hpke_init_key: &[u8],
        psk_plaintext: &[u8],
        ciphersuite: CipherSuite,
    ) -> Result<Vec<u8>, AgentHostError> {
        let cs_id: mls_rs::CipherSuite = ciphersuite.into();
        let provider = RustCryptoProvider::with_enabled_cipher_suites(vec![cs_id]);
        let cs_provider = provider
            .cipher_suite_provider(cs_id)
            .ok_or_else(|| AgentHostError::HpkeSeal("ciphersuite not supported".into()))?;
        let remote_key = HpkePublicKey::from(agent_hpke_init_key.to_vec());

        // The agent's `client.hpke_decrypt` builds its HPKE `info` as
        // `EncryptContext { label: raw label, context: b"" }.mls_encode_to_vec()`.
        let mut info = Vec::new();
        mls_rs_codec::byte_vec::mls_encode(&PSK_HPKE_LABEL.as_bytes().to_vec(), &mut info)
            .map_err(|e| AgentHostError::HpkeSeal(format!("encode info label: {e}")))?;
        mls_rs_codec::byte_vec::mls_encode(&Vec::<u8>::new(), &mut info)
            .map_err(|e| AgentHostError::HpkeSeal(format!("encode info context: {e}")))?;

        let ciphertext = cs_provider
            .hpke_seal(&remote_key, &info, None, psk_plaintext)
            .await
            .map_err(|e| AgentHostError::HpkeSeal(format!("{e:?}")))?;
        // `hpke_seal` returns an `HpkeCiphertext { kem_output, ciphertext }`.
        ciphertext
            .mls_encode_to_vec()
            .map_err(|e| AgentHostError::HpkeSeal(format!("encode HpkeCiphertext: {e}")))
    }

    /// `POST /v1/agent/bundle` via the shared [`MlsApi`] port.
    /// The port impl base64-encodes the byte fields for the JSON body.
    pub async fn push_bundle(
        &self,
        bearer_sd_cwt: &str,
        bundle: AgentBundleForPush,
    ) -> Result<(), AgentHostError> {
        self.mls_api
            .post_agent_bundle(
                bearer_sd_cwt,
                &bundle.agent_device_id,
                &bundle.psk_id,
                &bundle.encrypted_psk,
                &bundle.welcome,
                &bundle.ratchet_tree,
            )
            .await
            .map_err(|e| AgentHostError::Http(format!("post_agent_bundle: {e}")))?;
        Ok(())
    }
}
