use std::sync::Arc;

use base64::{engine::general_purpose, Engine};
use proton_meet_crypto::MEET_KEY_PACKAGE_AAD;

use crate::domain::mls::ports::KeyPackagePort;
use crate::domain::room::models::join_request::JoinRequest;
use crate::domain::user::{
    models::{meeting_link_name::MeetingLinkName, meeting_session_key::MeetingSessionKey, UserId},
    ports::crypto_client::CryptoClient,
};

#[derive(Debug, thiserror::Error)]
pub enum WaitingRoomError {
    #[error("Failed to generate key package: {0}")]
    KeyPackageError(#[from] crate::domain::mls::ports::KeyPackageError),
    #[error("Encryption error: {0}")]
    EncryptionError(#[from] proton_meet_crypto::CryptoError),
    #[error("Failed to decode encrypted key package")]
    InvalidEncryptedKeyPackage,
}

/// Domain service for waiting-room guest join requests.
pub struct WaitingRoomService {
    crypto_client: Arc<dyn CryptoClient>,
    key_packages: Arc<dyn KeyPackagePort>,
}

impl WaitingRoomService {
    pub fn new(
        crypto_client: Arc<dyn CryptoClient>,
        key_packages: Arc<dyn KeyPackagePort>,
    ) -> Self {
        Self {
            crypto_client,
            key_packages,
        }
    }

    pub async fn create_join_request(
        &self,
        meeting_link_name: &MeetingLinkName,
        user_id: &UserId,
        meeting_session_key: &MeetingSessionKey,
    ) -> Result<JoinRequest, WaitingRoomError> {
        tracing::debug!(
            meeting_link = %meeting_link_name.as_str(),
            user_id = %user_id,
            "create_join_request"
        );
        let serialized_key_package = self.key_packages.new_key_package(user_id).await?;
        let encoded_key_package = general_purpose::STANDARD.encode(&serialized_key_package);
        tracing::debug!(
            meeting_link = %meeting_link_name.as_str(),
            key_package_len = serialized_key_package.len(),
            "create_join_request key package generated"
        );
        let aad = format!("{}.{}", meeting_link_name.as_str(), MEET_KEY_PACKAGE_AAD);
        let encrypted_key_package = self
            .crypto_client
            .encrypt_message(
                &encoded_key_package,
                meeting_session_key.expose_secret(),
                &aad,
            )
            .await?;

        tracing::debug!(
            meeting_link = %meeting_link_name.as_str(),
            encrypted_b64_len = encrypted_key_package.len(),
            "create_join_request key package encrypted"
        );

        let encrypted_key_package = general_purpose::STANDARD
            .decode(encrypted_key_package)
            .map_err(|_| WaitingRoomError::InvalidEncryptedKeyPackage)?;

        Ok(JoinRequest::new(
            encrypted_key_package,
            meeting_link_name.clone(),
        ))
    }

    /// Decrypts a waiting-room join request key package using the meeting session key.
    /// Returns the serialized MLS key package bytes (same format as [`KeyPackagePort::new_key_package`]).
    pub async fn decrypt_key_package(
        &self,
        encrypted_key_package: &[u8],
        meeting_link_name: &MeetingLinkName,
        meeting_session_key: &MeetingSessionKey,
    ) -> Result<Vec<u8>, WaitingRoomError> {
        let encrypted_b64 = general_purpose::STANDARD.encode(encrypted_key_package);
        let aad = format!("{}.{}", meeting_link_name.as_str(), MEET_KEY_PACKAGE_AAD);
        let decoded_key_package_b64 = self
            .crypto_client
            .decrypt_message(&encrypted_b64, meeting_session_key.expose_secret(), &aad)
            .await?;

        general_purpose::STANDARD
            .decode(decoded_key_package_b64)
            .map_err(|_| WaitingRoomError::InvalidEncryptedKeyPackage)
    }
}
