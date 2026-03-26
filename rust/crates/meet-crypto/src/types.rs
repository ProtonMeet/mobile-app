#[cfg(not(target_family = "wasm"))]
use base64::{prelude::BASE64_STANDARD, Engine};

#[cfg(not(target_family = "wasm"))]
use proton_srp::SrpHashVersion;
use serde::{Deserialize, Serialize};

/// Represents an OpenPGP private key
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrivateKey {
    /// The private key in ASCII-armored format
    pub private_key: String,

    /// The key ID
    pub key_id: String,

    /// The user ID (name and email)
    pub user_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SRPProof {
    /// The client ephemeral in base64
    pub client_ephemeral: String,

    /// The client proof in base64
    pub client_proof: String,

    /// The expected server proof in base64
    pub expected_server_proof: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SRPVerifier {
    #[cfg(not(target_family = "wasm"))]
    /// The Proton SRP protocol version.
    pub version: SrpHashVersion,

    #[cfg(target_family = "wasm")]
    /// The Proton SRP protocol version.
    pub version: u8,

    /// The randomly generated salt.
    pub salt: String,

    /// The SRP verifier
    pub verifier: String,
}

#[cfg(not(target_family = "wasm"))]
impl From<proton_srp::SRPVerifier> for SRPVerifier {
    fn from(verifier: proton_srp::SRPVerifier) -> Self {
        Self {
            version: verifier.version,
            salt: BASE64_STANDARD.encode(verifier.salt),
            verifier: BASE64_STANDARD.encode(verifier.verifier),
        }
    }
}
