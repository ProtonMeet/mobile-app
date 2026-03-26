use proton_meet_common::models::ProtonUserKey;
use proton_meet_crypto::{CryptoError, SRPProof};
use proton_meet_crypto::{SRPVerifier, SessionKeyAlgorithm};
use proton_meet_macro::async_trait_with_mock;

#[async_trait_with_mock]
pub trait CryptoClient: Send + Sync {
    async fn generate_srp_proof(
        &self,
        password: &str,
        modulus: &str,
        base64_server_ephemeral: &str,
        base64_salt: &str,
    ) -> Result<SRPProof, CryptoError>;

    async fn compute_key_password(
        &self,
        password: &str,
        base64_salt: &str,
    ) -> Result<String, CryptoError>;

    async fn decrypt_session_key(
        &self,
        key_packets: &str,
        session_key_passphrase: &str,
    ) -> Result<String, CryptoError>;

    async fn decrypt_message(
        &self,
        base64_message: &str,
        base64_session_key: &str,
        aad: &str,
    ) -> Result<String, CryptoError>;

    async fn generate_random_meeting_password(&self) -> Result<String, CryptoError>;

    async fn generate_salt(&self) -> Result<String, CryptoError>;

    async fn generate_session_key(
        &self,
        algorithm: SessionKeyAlgorithm,
    ) -> Result<String, CryptoError>;

    async fn encrypt_session_key_with_passphrase(
        &self,
        session_key: &str,
        password_hash: &str,
    ) -> Result<String, CryptoError>;

    async fn openpgp_encrypt_message(
        &self,
        message: &str,
        base64_private_key: &str,
        private_key_passphrase: &str,
    ) -> Result<String, CryptoError>;

    async fn openpgp_decrypt_message(
        &self,
        encrypted_message: &str,
        user_private_keys: &[ProtonUserKey],
        all_address_keys: &[ProtonUserKey],
        private_key_passphrase: &str,
    ) -> Result<String, CryptoError>;

    async fn get_srp_verifier(
        &self,
        modulus: &str,
        password: &str,
    ) -> Result<SRPVerifier, CryptoError>;

    async fn encrypt_message(
        &self,
        message: &str,
        base64_session_key: &str,
        aad: &str,
    ) -> Result<String, CryptoError>;

    async fn encrypt_session_key(
        &self,
        base64_session_key: &str,
        passphrase: &str,
    ) -> Result<String, CryptoError>;
}
