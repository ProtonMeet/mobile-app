use std::str::from_utf8;

use crate::{key::Key, CryptoError, Result, SRPProof, SRPVerifier, SessionKeyAlgorithm};
use base64::prelude::BASE64_STANDARD;
use base64::Engine;
use hkdf::Hkdf;
use proton_crypto::{
    crypto::{
        DataEncoding, Decryptor, DecryptorSync, Encryptor, EncryptorSync, PGPMessage, PGPProvider,
        PGPProviderSync, SessionKey, VerifiedData,
    },
    new_pgp_provider, new_srp_provider,
    srp::{HashedPassword, SRPProvider},
};
use proton_crypto_account::salts::KeySecret;
use proton_crypto_subtle::aead::{AesGcmCiphertext, AesGcmKey};
use proton_srp::{SRPAuth, SrpHashVersion};
use sha2::Sha256;
use zeroize::Zeroizing;

/// Generates an SRP proof based on the provided password, modulus, server ephemeral, and salt.
pub async fn generate_srp_proof(
    password: &str,
    modulus: &str,
    base64_server_ephemeral: &str,
    base64_salt: &str,
) -> Result<SRPProof> {
    let client = SRPAuth::with_pgp(
        None,
        password,
        SrpHashVersion::V4,
        base64_salt,
        modulus,
        base64_server_ephemeral,
    )?;
    let proof = client.generate_proofs()?;
    Ok(SRPProof {
        client_ephemeral: BASE64_STANDARD.encode(proof.client_ephemeral),
        client_proof: BASE64_STANDARD.encode(proof.client_proof),
        expected_server_proof: BASE64_STANDARD.encode(proof.expected_server_proof),
    })
}

/// Computes the mailbox password hash based on the provided password and salt.
pub async fn compute_key_password(password: &str, base64_salt: &str) -> Result<String> {
    let salt = BASE64_STANDARD.decode(base64_salt)?;
    let srp_provider = new_srp_provider();
    let hashed_password = srp_provider.mailbox_password(password, &salt)?;
    let password_hash = hashed_password.password_hash();
    Ok(String::from_utf8(password_hash.to_vec())?)
}

pub async fn decrypt_session_key_with_passphrase(
    base64_key_packets: &str,
    session_key_passphrase: &str,
) -> Result<String> {
    let pgp_provider = new_pgp_provider();

    let decryptor = pgp_provider
        .new_decryptor()
        .with_passphrase(session_key_passphrase);

    let decrypted_session_key = decryptor
        .decrypt_session_key(BASE64_STANDARD.decode(base64_key_packets)?)
        .map_err(|e| CryptoError::FailedToDecryptSessionKey(e.to_string()))?;

    Ok(BASE64_STANDARD.encode(decrypted_session_key.export()))
}

/// Decrypt a UTF-8 string encrypted with [`encrypt_message`] using the same `aad`.
pub async fn decrypt_message(
    base64_message: &str,
    base64_session_key: &str,
    aad: &str,
) -> Result<String> {
    let hk = Hkdf::<Sha256>::new(None, &BASE64_STANDARD.decode(base64_session_key)?);
    let mut okm = Zeroizing::new([0_u8; proton_crypto_subtle::aead::AES_GCM_256_KEY_SIZE]);
    let info = b"aeskey.link.meet.proton";
    hk.expand(info, okm.as_mut_slice())
        .map_err(|e| CryptoError::FailedToExpandSessionKey(e.to_string()))?;

    let aes_key = AesGcmKey::from_bytes(&okm)
        .map_err(|e| CryptoError::FailedToCreateAesKey(e.to_string()))?;

    let message = BASE64_STANDARD.decode(base64_message)?;
    let cipertext = AesGcmCiphertext::decode(&message)
        .map_err(|e| CryptoError::FailedToDecodeEncryptedMessage(e.to_string()))?;

    let decrypted_message = aes_key
        .decrypt(cipertext, Some(aad))
        .map_err(|e| CryptoError::FailedToDecryptMessage(e.to_string()))?;

    Ok(from_utf8(&decrypted_message)?.to_string())
}

/// Encrypt a UTF-8 string with the meet link session key. Pass [`super::MEET_METADATA_AAD`] or
/// [`super::MEET_DISPLAY_NAME_AAD`] as `aad` to match web clients.
pub async fn encrypt_message(message: &str, base64_session_key: &str, aad: &str) -> Result<String> {
    let hk = Hkdf::<Sha256>::new(None, &BASE64_STANDARD.decode(base64_session_key)?);
    let mut okm = Zeroizing::new([0_u8; proton_crypto_subtle::aead::AES_GCM_256_KEY_SIZE]);
    let info = b"aeskey.link.meet.proton";
    hk.expand(info, okm.as_mut_slice())
        .map_err(|e| CryptoError::FailedToExpandSessionKey(e.to_string()))?;

    let aes_key = AesGcmKey::from_bytes(&okm)
        .map_err(|e| CryptoError::FailedToCreateAesKey(e.to_string()))?;

    let cipertext = aes_key
        .encrypt(message.as_bytes(), Some(aad))
        .map_err(|e| CryptoError::FailedToEncryptMessage(e.to_string()))?;

    Ok(BASE64_STANDARD.encode(cipertext.encode()))
}

const CHARSET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
pub async fn generate_random_password() -> Result<String> {
    let password = proton_crypto::generate_secure_random_bytes::<12>();
    let mut result = String::new();
    for i in password {
        result.push(CHARSET[i as usize % CHARSET.len()] as char);
    }
    Ok(result)
}

pub async fn generate_salt() -> Result<String> {
    let salt = proton_crypto::generate_secure_random_bytes::<16>();
    Ok(BASE64_STANDARD.encode(salt))
}

pub async fn generate_session_key(algo: SessionKeyAlgorithm) -> Result<String> {
    let pgp_provider = new_pgp_provider();
    let session_key = pgp_provider.session_key_generate(algo.into())?;
    Ok(BASE64_STANDARD.encode(session_key.export()))
}

pub async fn encrypt_session_key_with_passphrase(
    base64_session_key: &str,
    passphrase: &str,
) -> Result<String> {
    let pgp_provider = new_pgp_provider();
    let session_key = pgp_provider.session_key_import(
        &BASE64_STANDARD.decode(base64_session_key)?,
        proton_crypto::crypto::SessionKeyAlgorithm::Aes256,
    )?;
    let encrypted_session_key = pgp_provider
        .new_encryptor()
        .with_passphrase(passphrase)
        .encrypt_session_key(&session_key)?;
    Ok(BASE64_STANDARD.encode(encrypted_session_key))
}

pub async fn openpgp_encrypt_message(
    message: &str,
    base64_private_key: &str,
    private_key_passphrase: &str,
) -> Result<String> {
    let pgp_provider = new_pgp_provider();
    let private_key = pgp_provider.private_key_import(
        base64_private_key,
        private_key_passphrase,
        DataEncoding::Armor,
    )?;
    let public_key = pgp_provider.private_key_to_public_key(&private_key)?;
    let signing_context = pgp_provider.new_signing_context("pw.link.meet.proton".to_string(), true);
    let encryptor = pgp_provider
        .new_encryptor()
        .with_encryption_key(&public_key)
        .with_signing_key(&private_key)
        .with_signing_context(&signing_context);
    let encrypted_message = encryptor.encrypt(message.as_bytes())?;
    Ok(String::from_utf8(encrypted_message.armor()?)?)
}

pub async fn openpgp_decrypt_message(
    encrypted_message: &str,
    user_private_keys: &[Key],
    all_address_keys: &[Key],
    private_key_passphrase: &str,
) -> Result<String> {
    use crate::private_key::LockedPrivateKeys;

    // Validate input parameters
    if user_private_keys.is_empty() && all_address_keys.is_empty() {
        return Err(CryptoError::DecryptionFailed(
            "No keys provided for decryption. Both user_private_keys and all_address_keys are empty.".to_string()
        ));
    }

    if private_key_passphrase.is_empty() {
        return Err(CryptoError::DecryptionFailed(
            "Private key passphrase is empty.".to_string(),
        ));
    }

    let pgp_provider = new_pgp_provider();

    // Convert domain keys to locked keys
    let locked_keys = LockedPrivateKeys::from_domain_keys(user_private_keys, all_address_keys)?;

    // Unlock all keys
    let key_secret = KeySecret::new(private_key_passphrase.as_bytes().to_vec());
    let unlocked_keys = locked_keys.unlock_with(&pgp_provider, &key_secret);

    // Validate that we have at least some unlocked keys
    if unlocked_keys.user_keys.is_empty() && unlocked_keys.addr_keys.is_empty() {
        let mut error_msg = String::from("No keys could be unlocked. ");
        if !unlocked_keys.user_keys_failed.is_empty() {
            error_msg.push_str(&format!(
                "User keys failed: {:?}. ",
                unlocked_keys.user_keys_failed
            ));
        }
        if !unlocked_keys.addr_keys_failed.is_empty() {
            error_msg.push_str(&format!(
                "Address keys failed: {:?}. ",
                unlocked_keys.addr_keys_failed
            ));
        }
        error_msg.push_str("Please verify the passphrase and that keys are valid.");
        return Err(CryptoError::DecryptionFailed(error_msg));
    }

    // Try decrypting with unlocked keys
    // Use with_decryption_key_refs to add all keys at once
    let mut decryptor = pgp_provider.new_decryptor();

    // Add address keys first (preferred), then user keys
    if !unlocked_keys.addr_keys.is_empty() {
        decryptor = decryptor.with_decryption_key_refs(unlocked_keys.addr_keys.as_ref());
    }
    if !unlocked_keys.user_keys.is_empty() {
        decryptor = decryptor.with_decryption_key_refs(unlocked_keys.user_keys.as_ref());
    }

    let decrypted_data = decryptor
        .decrypt(encrypted_message.as_bytes(), DataEncoding::Armor)
        .map_err(|e| {
            CryptoError::DecryptionFailed(format!(
                "Failed to decrypt with any key: {e}. This may indicate the message was encrypted with different keys or the passphrase is incorrect.",
            ))
        })?;

    Ok(String::from_utf8(decrypted_data.into_vec())?)
}

pub async fn get_srp_verifier(modulus: &str, password: &str) -> Result<SRPVerifier> {
    let verifier = SRPAuth::generate_verifier_with_pgp(password, None, modulus)?;
    Ok(verifier.into())
}
