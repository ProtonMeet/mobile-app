use crate::domain::user::ports::CryptoClient;
use argon2::{Algorithm, Argon2, Params, Version};
use proton_meet_common::models::ProtonUserKey;
use proton_meet_crypto::{
    key::Key as CryptoKey, CryptoError, MeetCrypto, SRPProof, SRPVerifier, SessionKeyAlgorithm,
};
use proton_meet_macro::async_trait;
use sha2::{Digest, Sha256};

const MLS_EXTERNAL_PSK_OUTPUT_LEN: usize = 32;

pub(crate) fn derive_external_psk(
    meeting_password: &str,
    meeting_link_name: &str,
) -> Result<mls_types::ExternalPsk, anyhow::Error> {
    // Derive deterministic room-bound salt so all participants compute the same PSK bytes.
    let mut salt_hasher = Sha256::new();
    salt_hasher.update(meeting_link_name.as_bytes());
    let salt_hash = salt_hasher.finalize();

    let params = Params::new(19 * 1024, 2, 1, Some(MLS_EXTERNAL_PSK_OUTPUT_LEN))
        .map_err(|e| anyhow::anyhow!("failed to create Argon2 params: {e}"))?;
    let argon2 = Argon2::new(Algorithm::Argon2id, Version::V0x13, params);

    let mut output = [0_u8; MLS_EXTERNAL_PSK_OUTPUT_LEN];
    argon2
        .hash_password_into(meeting_password.as_bytes(), &salt_hash[..16], &mut output)
        .map_err(|e| anyhow::anyhow!("failed to derive external PSK with Argon2: {e}"))?;

    Ok(mls_types::ExternalPsk(output.to_vec()))
}

// Convert ProtonUserKey to crypto Key
fn to_crypto_keys(keys: &[ProtonUserKey]) -> Vec<CryptoKey> {
    keys.iter()
        .map(|k| CryptoKey {
            id: k.id.clone(),
            private_key: k.private_key.clone(),
            token: k.token.clone(),
            signature: k.signature.clone(),
            primary: k.primary == 1,
            active: k.active == 1,
        })
        .collect()
}

#[derive(Debug, Clone)]
pub struct MeetCryptoClient {}

impl MeetCryptoClient {
    pub fn new() -> Self {
        Self {}
    }
}
impl Default for MeetCryptoClient {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl CryptoClient for MeetCryptoClient {
    async fn generate_srp_proof(
        &self,
        password: &str,
        modulus: &str,
        base64_server_ephemeral: &str,
        base64_salt: &str,
    ) -> Result<SRPProof, CryptoError> {
        MeetCrypto::generate_srp_proof(password, modulus, base64_server_ephemeral, base64_salt)
            .await
    }

    async fn compute_key_password(
        &self,
        password: &str,
        base64_salt: &str,
    ) -> Result<String, CryptoError> {
        MeetCrypto::compute_key_password(password, base64_salt).await
    }

    async fn decrypt_session_key(
        &self,
        key_packets: &str,
        session_key_passphrase: &str,
    ) -> Result<String, CryptoError> {
        MeetCrypto::decrypt_session_key(key_packets, session_key_passphrase).await
    }

    #[cfg(not(target_family = "wasm"))]
    async fn decrypt_message(
        &self,
        base64_message: &str,
        base64_session_key: &str,
        aad: &str,
    ) -> Result<String, CryptoError> {
        MeetCrypto::decrypt_message(base64_message, base64_session_key, aad).await
    }

    #[cfg(target_family = "wasm")]
    async fn decrypt_message(
        &self,
        base64_key_packets: &str,
        session_key_passphrase: &str,
        aad: &str,
    ) -> Result<String, CryptoError> {
        MeetCrypto::decrypt_message(base64_key_packets, session_key_passphrase, aad).await
    }

    async fn generate_random_meeting_password(&self) -> Result<String, CryptoError> {
        MeetCrypto::generate_random_meeting_password().await
    }

    async fn generate_salt(&self) -> Result<String, CryptoError> {
        MeetCrypto::generate_salt().await
    }

    async fn generate_session_key(&self, algo: SessionKeyAlgorithm) -> Result<String, CryptoError> {
        MeetCrypto::generate_session_key(algo).await
    }

    async fn encrypt_session_key_with_passphrase(
        &self,
        base64_session_key: &str,
        passphrase: &str,
    ) -> Result<String, CryptoError> {
        MeetCrypto::encrypt_session_key(base64_session_key, passphrase).await
    }

    async fn encrypt_session_key(
        &self,
        base64_session_key: &str,
        passphrase: &str,
    ) -> Result<String, CryptoError> {
        MeetCrypto::encrypt_session_key(base64_session_key, passphrase).await
    }

    async fn openpgp_encrypt_message(
        &self,
        message: &str,
        base64_private_key: &str,
        private_key_passphrase: &str,
    ) -> Result<String, CryptoError> {
        MeetCrypto::openpgp_encrypt_message(message, base64_private_key, private_key_passphrase)
            .await
    }

    async fn openpgp_decrypt_message(
        &self,
        encrypted_message: &str,
        user_private_keys: &[ProtonUserKey],
        all_address_keys: &[ProtonUserKey],
        private_key_passphrase: &str,
    ) -> Result<String, CryptoError> {
        let crypto_user_keys = to_crypto_keys(user_private_keys);
        let crypto_address_keys = to_crypto_keys(all_address_keys);
        MeetCrypto::openpgp_decrypt_message(
            encrypted_message,
            &crypto_user_keys,
            &crypto_address_keys,
            private_key_passphrase,
        )
        .await
    }

    async fn get_srp_verifier(
        &self,
        modulus: &str,
        password: &str,
    ) -> Result<SRPVerifier, CryptoError> {
        MeetCrypto::get_srp_verifier(modulus, password).await
    }

    async fn encrypt_message(
        &self,
        message: &str,
        base64_session_key: &str,
        aad: &str,
    ) -> Result<String, CryptoError> {
        MeetCrypto::encrypt_message(message, base64_session_key, aad).await
    }
}
