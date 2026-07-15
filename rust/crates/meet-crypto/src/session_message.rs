use std::str::from_utf8;

use aes_gcm::{
    aead::{Aead, KeyInit, Payload},
    Aes256Gcm,
};
use base64::prelude::BASE64_STANDARD;
use base64::Engine;
use hkdf::Hkdf;
use sha2::Sha256;
use zeroize::Zeroizing;

use crate::CryptoError;

const AES_GCM_256_KEY_SIZE: usize = 32;
const AES_GCM_256_IV_SIZE: usize = 12;
const HKDF_INFO: &[u8] = b"aeskey.link.meet.proton";

type Result<T> = std::result::Result<T, CryptoError>;

fn random_iv() -> Result<[u8; AES_GCM_256_IV_SIZE]> {
    let mut iv = [0_u8; AES_GCM_256_IV_SIZE];
    getrandom::fill(&mut iv)
        .map_err(|e| CryptoError::Other(format!("failed to generate nonce: {e}")))?;
    Ok(iv)
}

fn derive_aes_key(base64_session_key: &str) -> Result<Aes256Gcm> {
    let session_key = BASE64_STANDARD
        .decode(base64_session_key)
        .map_err(|e| CryptoError::Base64DecodeError(e.to_string()))?;
    let hk = Hkdf::<Sha256>::new(None, &session_key);
    let mut okm = Zeroizing::new([0_u8; AES_GCM_256_KEY_SIZE]);
    hk.expand(HKDF_INFO, okm.as_mut_slice())
        .map_err(|e| CryptoError::FailedToExpandSessionKey(e.to_string()))?;
    Aes256Gcm::new_from_slice(okm.as_ref())
        .map_err(|_| CryptoError::FailedToCreateAesKey("invalid AES key length".to_string()))
}

/// Encrypt a UTF-8 string with the meet link session key (HKDF + AES-GCM-256).
pub fn encrypt_message(message: &str, base64_session_key: &str, aad: &str) -> Result<String> {
    let cipher = derive_aes_key(base64_session_key)?;
    let iv = random_iv()?;
    let nonce = aes_gcm::Nonce::from_slice(&iv);
    let payload = Payload {
        msg: message.as_bytes(),
        aad: aad.as_bytes(),
    };
    let ciphertext = cipher
        .encrypt(&nonce, payload)
        .map_err(|e| CryptoError::FailedToEncryptMessage(e.to_string()))?;

    let mut encoded = Vec::with_capacity(AES_GCM_256_IV_SIZE + ciphertext.len());
    encoded.extend_from_slice(&iv);
    encoded.extend_from_slice(&ciphertext);
    Ok(BASE64_STANDARD.encode(encoded))
}

/// Decrypt a UTF-8 string encrypted with [`encrypt_message`] using the same `aad`.
pub fn decrypt_message(
    base64_message: &str,
    base64_session_key: &str,
    aad: &str,
) -> Result<String> {
    let cipher = derive_aes_key(base64_session_key)?;
    let message = BASE64_STANDARD
        .decode(base64_message)
        .map_err(|e| CryptoError::Base64DecodeError(e.to_string()))?;
    if message.len() < AES_GCM_256_IV_SIZE {
        return Err(CryptoError::FailedToDecodeEncryptedMessage(
            "ciphertext too short".to_string(),
        ));
    }
    let (iv, data) = message.split_at(AES_GCM_256_IV_SIZE);
    let nonce = aes_gcm::Nonce::from_slice(iv);
    let payload = Payload {
        msg: data,
        aad: aad.as_bytes(),
    };
    let decrypted = cipher
        .decrypt(nonce, payload)
        .map_err(|e| CryptoError::FailedToDecryptMessage(e.to_string()))?;
    Ok(from_utf8(&decrypted)?.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{MEET_DISPLAY_NAME_AAD, MEET_KEY_PACKAGE_AAD, MEET_METADATA_AAD};

    #[test]
    fn encrypt_decrypt_roundtrip() {
        let session_key = BASE64_STANDARD.encode([7_u8; 32]);
        for (message, aad) in [
            ("Hello, world!", MEET_METADATA_AAD),
            ("Alice", MEET_DISPLAY_NAME_AAD),
            ("base64-key-package", MEET_KEY_PACKAGE_AAD),
        ] {
            let encrypted = encrypt_message(message, &session_key, aad).unwrap();
            let decrypted = decrypt_message(&encrypted, &session_key, aad).unwrap();
            assert_eq!(decrypted, message);
        }
    }
}
