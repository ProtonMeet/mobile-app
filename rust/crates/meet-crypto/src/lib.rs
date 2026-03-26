use aes_gcm::Error as AesGcmError;
#[cfg(not(target_family = "wasm"))]
use proton_srp::MailboxHashError;
use thiserror::Error;

pub mod binary;
pub mod chat_message;
pub mod key;
pub mod message;
#[cfg(not(target_family = "wasm"))]
#[cfg(test)]
mod mocks;
#[cfg(not(target_family = "wasm"))]
pub mod private_key;
pub mod room_key;
mod types;

pub use types::*;

/// Associated data for AES-GCM payloads derived from the meet link session key (meeting title, etc.).
pub const MEET_METADATA_AAD: &str = "metadata.meet.proton";
/// Associated data for AES-GCM payloads derived from the meet link session key (participant display names).
pub const MEET_DISPLAY_NAME_AAD: &str = "displayname.meet.proton";

#[cfg(not(target_family = "wasm"))]
mod native;
#[cfg(not(target_family = "wasm"))]
pub use native::*;

#[cfg(target_family = "wasm")]
mod web;
#[cfg(target_family = "wasm")]
pub use web::*;

#[derive(Debug, Error)]
pub enum CryptoError {
    #[error("Key generation failed: {0}")]
    KeyGenerationFailed(String),

    #[error("Encryption failed: {0}")]
    EncryptionFailed(String),

    #[error("Decryption failed: {0}")]
    DecryptionFailed(String),

    #[error("Signature verification failed: {0}")]
    SignatureVerificationFailed(String),

    #[error("Invalid input: {0}")]
    InvalidInput(String),

    #[error("JavaScript interop error: {0}")]
    JsInteropError(String),

    #[error("Unexpected error: {0}")]
    Other(String),

    #[error("Base64 decode error: {0}")]
    Base64DecodeError(String),

    #[error("SRP error: {0}")]
    SrpError(String),

    #[error("UTF-8 conversion error: {0}")]
    Utf8ConversionError(String),

    #[error("Failed to decrypt session key: {0}")]
    FailedToDecryptSessionKey(String),

    #[error("Failed to expand session key: {0}")]
    FailedToExpandSessionKey(String),

    #[error("Failed to create AES key: {0}")]
    FailedToCreateAesKey(String),

    #[error("Failed to decode encrypted message: {0}")]
    FailedToDecodeEncryptedMessage(String),

    #[error("Failed to decrypt message: {0}")]
    FailedToDecryptMessage(String),

    #[error("Failed to encrypt message: {0}")]
    FailedToEncryptMessage(String),

    #[error("Failed to convert to UTF-8: {0}")]
    FromUtf8Error(#[from] std::string::FromUtf8Error),
    #[error("Invalid AesGcm key length error")]
    AesGcmInvalidKeyLength,

    #[error("Invalid AesGcm encrypted data length error")]
    AesGcmInvalidDataSize,

    #[error("Aes gcm crypto error: {0}")]
    AesGcm(String),
}

// map aes_gcm::Error to CryptoError
impl From<AesGcmError> for CryptoError {
    fn from(err: AesGcmError) -> Self {
        CryptoError::AesGcm(format!("{:?}", err.to_string()))
    }
}

impl From<base64::DecodeError> for CryptoError {
    fn from(error: base64::DecodeError) -> Self {
        CryptoError::Base64DecodeError(error.to_string())
    }
}

impl From<std::str::Utf8Error> for CryptoError {
    fn from(error: std::str::Utf8Error) -> Self {
        CryptoError::Utf8ConversionError(error.to_string())
    }
}

#[cfg(not(target_family = "wasm"))]
impl From<MailboxHashError> for CryptoError {
    fn from(error: MailboxHashError) -> Self {
        CryptoError::SrpError(error.to_string())
    }
}

#[cfg(not(target_family = "wasm"))]
impl From<proton_srp::SRPError> for CryptoError {
    fn from(error: proton_srp::SRPError) -> Self {
        CryptoError::SrpError(error.to_string())
    }
}

#[cfg(not(target_family = "wasm"))]
impl From<proton_crypto::Error> for CryptoError {
    fn from(error: proton_crypto::Error) -> Self {
        CryptoError::Other(error.to_string())
    }
}

#[cfg(target_family = "wasm")]
impl From<WebCryptoError> for CryptoError {
    fn from(error: WebCryptoError) -> Self {
        match error {
            WebCryptoError::BridgeUnavailable => {
                CryptoError::JsInteropError("Crypto bridge unavailable".to_string())
            }
            WebCryptoError::JsInterop(msg) => CryptoError::JsInteropError(msg),
            WebCryptoError::ResultNotString => {
                CryptoError::JsInteropError("Result is not a string".to_string())
            }
            WebCryptoError::ParseResult(msg) => {
                CryptoError::JsInteropError(format!("Failed to parse result: {}", msg))
            }
            WebCryptoError::MissingField(field) => {
                CryptoError::JsInteropError(format!("Missing or invalid field: {}", field))
            }
            WebCryptoError::Other(msg) => CryptoError::Other(msg),
            WebCryptoError::FailedToComputeKeyPassword => {
                CryptoError::JsInteropError("Failed to compute key password".to_string())
            }
            WebCryptoError::FailedToGenerateSRPProof => {
                CryptoError::JsInteropError("Failed to generate SRP proof".to_string())
            }
            WebCryptoError::FailedToGetWindow => {
                CryptoError::JsInteropError("Failed to get window".to_string())
            }
            WebCryptoError::FailedToDecryptSessionKey => {
                CryptoError::JsInteropError("Failed to decrypt session key".to_string())
            }
            WebCryptoError::FailedToDecryptMessage => {
                CryptoError::JsInteropError("Failed to decrypt message".to_string())
            }
        }
    }
}

type Result<T> = std::result::Result<T, CryptoError>;

pub enum SessionKeyAlgorithm {
    Aes256,
    Aes128,
}

#[cfg(not(target_family = "wasm"))]
impl From<SessionKeyAlgorithm> for proton_crypto::crypto::SessionKeyAlgorithm {
    fn from(algo: SessionKeyAlgorithm) -> Self {
        match algo {
            SessionKeyAlgorithm::Aes256 => proton_crypto::crypto::SessionKeyAlgorithm::Aes256,
            SessionKeyAlgorithm::Aes128 => proton_crypto::crypto::SessionKeyAlgorithm::Aes128,
        }
    }
}

pub struct MeetCrypto {}

impl MeetCrypto {
    pub async fn generate_srp_proof(
        password: &str,
        modulus: &str,
        base64_server_ephemeral: &str,
        base64_salt: &str,
    ) -> Result<SRPProof> {
        generate_srp_proof(password, modulus, base64_server_ephemeral, base64_salt).await
    }

    pub async fn compute_key_password(password: &str, base64_salt: &str) -> Result<String> {
        compute_key_password(password, base64_salt).await
    }

    // return the decrypted session key as base64 encoded string
    pub async fn decrypt_session_key(
        key_packets: &str,
        session_key_passphrase: &str,
    ) -> Result<String> {
        decrypt_session_key_with_passphrase(key_packets, session_key_passphrase).await
    }

    pub async fn generate_random_meeting_password() -> Result<String> {
        generate_random_password().await
    }

    pub async fn generate_salt() -> Result<String> {
        generate_salt().await
    }

    pub async fn generate_session_key(algo: SessionKeyAlgorithm) -> Result<String> {
        generate_session_key(algo).await
    }

    pub async fn encrypt_session_key(base64_session_key: &str, passphrase: &str) -> Result<String> {
        encrypt_session_key_with_passphrase(base64_session_key, passphrase).await
    }

    #[cfg(not(target_family = "wasm"))]
    pub async fn decrypt_message(
        base64_message: &str,
        base64_session_key: &str,
        aad: &str,
    ) -> Result<String> {
        crate::decrypt_message(base64_message, base64_session_key, aad).await
    }

    #[cfg(not(target_family = "wasm"))]
    pub async fn encrypt_message(
        message: &str,
        base64_session_key: &str,
        aad: &str,
    ) -> Result<String> {
        crate::encrypt_message(message, base64_session_key, aad).await
    }

    #[cfg(target_family = "wasm")]
    pub async fn decrypt_message(
        base64_key_packets: &str,
        session_key_passphrase: &str,
        _aad: &str,
    ) -> Result<String> {
        crate::web::decrypt_message(base64_key_packets, session_key_passphrase, _aad).await
    }

    #[cfg(target_family = "wasm")]
    pub async fn encrypt_message(
        message: &str,
        base64_session_key: &str,
        aad: &str,
    ) -> Result<String> {
        crate::web::encrypt_message(message, base64_session_key, aad).await
    }

    pub async fn openpgp_encrypt_message(
        message: &str,
        base64_private_key: &str,
        private_key_passphrase: &str,
    ) -> Result<String> {
        openpgp_encrypt_message(message, base64_private_key, private_key_passphrase).await
    }

    pub async fn openpgp_decrypt_message(
        encrypted_message: &str,
        user_private_keys: &[crate::key::Key],
        all_address_keys: &[crate::key::Key],
        private_key_passphrase: &str,
    ) -> Result<String> {
        openpgp_decrypt_message(
            encrypted_message,
            user_private_keys,
            all_address_keys,
            private_key_passphrase,
        )
        .await
    }

    pub async fn get_srp_verifier(modulus: &str, password: &str) -> Result<SRPVerifier> {
        get_srp_verifier(modulus, password).await
    }
}
