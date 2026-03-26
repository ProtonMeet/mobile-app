use crate::Result;
use crate::SRPProof;
use crate::SRPVerifier;
use crate::SessionKeyAlgorithm;
use js_sys::Promise;
use serde_json::Value;
use wasm_bindgen::prelude::*;
use wasm_bindgen_futures::JsFuture;

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = window)]
    pub type Window;

    #[wasm_bindgen(method, getter, js_name = cryptoBridge)]
    fn crypto_bridge(this: &Window) -> CryptoBridge;
}

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen]
    pub type CryptoBridge;

    #[wasm_bindgen(method)]
    fn generateSRPProof(
        this: &CryptoBridge,
        password: &str,
        modulus: &str,
        base64_server_ephemeral: &str,
        base64_salt: &str,
    ) -> Promise;

    #[wasm_bindgen(method)]
    fn computeKeyPassword(this: &CryptoBridge, password: &str, base64_salt: &str) -> Promise;

    #[wasm_bindgen(method)]
    fn decrypt_session_key_with_passphrase(
        this: &CryptoBridge,
        base64_key_packets: &str,
        session_key_passphrase: &str,
    ) -> Promise;

    #[wasm_bindgen(method)]
    fn decryptMessage(
        this: &CryptoBridge,
        base64_key_packets: &str,
        session_key_passphrase: &str,
    ) -> Promise;
}

pub async fn generate_srp_proof(
    password: &str,
    modulus: &str,
    base64_server_ephemeral: &str,
    base64_salt: &str,
) -> Result<SRPProof> {
    let window = web_sys::window().ok_or_else(|| WebCryptoError::BridgeUnavailable)?;
    let crypto_bridge = window
        .dyn_ref::<Window>()
        .ok_or_else(|| WebCryptoError::FailedToGetWindow)?
        .crypto_bridge();

    let promise =
        crypto_bridge.generateSRPProof(password, modulus, base64_server_ephemeral, base64_salt);
    let result = JsFuture::from(promise)
        .await
        .map_err(|_e| WebCryptoError::FailedToGenerateSRPProof)?;

    let result_str = result.as_string().ok_or(WebCryptoError::ResultNotString)?;

    let result_data: Value = serde_json::from_str(&result_str)
        .map_err(|e| WebCryptoError::ParseResult(e.to_string()))?;

    let expected_server_proof = result_data["expectedServerProof"]
        .as_str()
        .ok_or(WebCryptoError::MissingField("expectedServerProof"))?;
    let client_ephemeral = result_data["clientEphemeral"]
        .as_str()
        .ok_or(WebCryptoError::MissingField("clientEphemeral"))?;
    let client_proof = result_data["clientProof"]
        .as_str()
        .ok_or(WebCryptoError::MissingField("clientProof"))?;

    Ok(SRPProof {
        client_ephemeral: client_ephemeral.to_string(),
        client_proof: client_proof.to_string(),
        expected_server_proof: expected_server_proof.to_string(),
    })
}

pub async fn compute_key_password(password: &str, base64_salt: &str) -> Result<String> {
    let window = web_sys::window().ok_or_else(|| WebCryptoError::BridgeUnavailable)?;
    let crypto_bridge = window
        .dyn_ref::<Window>()
        .ok_or_else(|| WebCryptoError::FailedToGetWindow)?
        .crypto_bridge();

    let promise = crypto_bridge.computeKeyPassword(password, base64_salt);
    let result = JsFuture::from(promise)
        .await
        .map_err(|_e| WebCryptoError::FailedToComputeKeyPassword)?;
    let result_str = result.as_string().ok_or(WebCryptoError::ResultNotString)?;

    Ok(result_str)
}

pub async fn decrypt_session_key_with_passphrase(
    base64_key_packets: &str,
    session_key_passphrase: &str,
) -> Result<String> {
    let window = web_sys::window().ok_or_else(|| WebCryptoError::BridgeUnavailable)?;
    let crypto_bridge = window
        .dyn_ref::<Window>()
        .ok_or_else(|| WebCryptoError::FailedToGetWindow)?
        .crypto_bridge();

    let promise = crypto_bridge
        .decrypt_session_key_with_passphrase(base64_key_packets, session_key_passphrase);
    let result = JsFuture::from(promise)
        .await
        .map_err(|_e| WebCryptoError::FailedToDecryptSessionKey)?;

    Ok(result.as_string().ok_or(WebCryptoError::ResultNotString)?)
}

pub async fn decrypt_message(
    base64_key_packets: &str,
    session_key_passphrase: &str,
    _aad: &str,
) -> Result<String> {
    let window = web_sys::window().ok_or_else(|| WebCryptoError::BridgeUnavailable)?;
    let crypto_bridge = window
        .dyn_ref::<Window>()
        .ok_or_else(|| WebCryptoError::FailedToGetWindow)?
        .crypto_bridge();

    let promise = crypto_bridge.decryptMessage(base64_key_packets, session_key_passphrase);
    let result = JsFuture::from(promise)
        .await
        .map_err(|_e| WebCryptoError::FailedToDecryptMessage)?;

    Ok(result.as_string().ok_or(WebCryptoError::ResultNotString)?)
}

#[allow(unused_variables)]
pub async fn encrypt_message(
    message: &str,
    base64_session_key: &str,
    _aad: &str,
) -> Result<String> {
    unimplemented!();
}

pub async fn generate_random_password() -> Result<String> {
    unimplemented!();
}

pub async fn generate_salt() -> Result<String> {
    unimplemented!();
}

#[allow(unused_variables)]
pub async fn generate_session_key(algo: SessionKeyAlgorithm) -> Result<String> {
    unimplemented!();
}

#[allow(unused_variables)]
pub async fn encrypt_session_key_with_passphrase(
    base64_session_key: &str,
    passphrase: &str,
) -> Result<String> {
    unimplemented!();
}

#[allow(unused_variables)]
pub async fn openpgp_encrypt_message(
    message: &str,
    base64_private_key: &str,
    private_key_passphrase: &str,
) -> Result<String> {
    unimplemented!();
}

#[allow(unused_variables)]
pub async fn openpgp_decrypt_message(
    encrypted_message: &str,
    user_private_keys: &[crate::key::Key],
    all_address_keys: &[crate::key::Key],
    private_key_passphrase: &str,
) -> Result<String> {
    // For WASM, we need to call the JavaScript crypto bridge
    // The bridge should handle trying multiple keys
    let window = web_sys::window().ok_or_else(|| WebCryptoError::BridgeUnavailable)?;
    let crypto_bridge = window
        .dyn_ref::<Window>()
        .ok_or_else(|| WebCryptoError::FailedToGetWindow)?
        .crypto_bridge();

    // Try decrypting with each key until one succeeds
    // Start with address keys (preferred), then user keys
    let mut last_error = None;

    // Try address keys first
    for key in all_address_keys {
        match try_decrypt_with_key(
            &crypto_bridge,
            encrypted_message,
            &key.private_key,
            private_key_passphrase,
        )
        .await
        {
            Ok(result) => return Ok(result),
            Err(e) => last_error = Some(e),
        }
    }

    // Try user keys
    for key in user_private_keys {
        match try_decrypt_with_key(
            &crypto_bridge,
            encrypted_message,
            &key.private_key,
            private_key_passphrase,
        )
        .await
        {
            Ok(result) => return Ok(result),
            Err(e) => last_error = Some(e),
        }
    }

    Err(last_error.unwrap_or_else(|| WebCryptoError::FailedToDecryptMessage.into()))
}

async fn try_decrypt_with_key(
    crypto_bridge: &CryptoBridge,
    encrypted_message: &str,
    private_key: &str,
    passphrase: &str,
) -> Result<String> {
    // This would need to be implemented in the JavaScript bridge
    // For now, return an error indicating it's not implemented
    Err(
        WebCryptoError::Other("WASM openpgp_decrypt_message not yet implemented".to_string())
            .into(),
    )
}

#[allow(unused_variables)]
pub async fn get_srp_verifier(modulus: &str, password: &str) -> Result<SRPVerifier> {
    unimplemented!();
}

#[cfg(target_family = "wasm")]
#[derive(Debug, thiserror::Error)]
pub enum WebCryptoError {
    #[error("Crypto bridge unavailable")]
    BridgeUnavailable,
    #[error("JavaScript interop error: {0}")]
    JsInterop(String),
    #[error("Result is not a string")]
    ResultNotString,
    #[error("Failed to parse result: {0}")]
    ParseResult(String),
    #[error("Missing or invalid field: {0}")]
    MissingField(&'static str),
    #[error("Other web crypto error: {0}")]
    Other(String),
    #[error("Failed to compute key password")]
    FailedToComputeKeyPassword,
    #[error("Failed to generate SRP proof")]
    FailedToGenerateSRPProof,
    #[error("Failed to get window")]
    FailedToGetWindow,
    #[error("Failed to decrypt session key")]
    FailedToDecryptSessionKey,
    #[error("Failed to decrypt message")]
    FailedToDecryptMessage,
}
