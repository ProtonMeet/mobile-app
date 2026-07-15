#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use base64::{engine::general_purpose, Engine};
    use mockall::predicate::eq;
    use proton_meet_crypto::MEET_KEY_PACKAGE_AAD;
    use proton_meet_macro::unified_test;

    use crate::domain::mls::ports::{KeyPackageError, MockKeyPackagePort};
    use crate::domain::room::WaitingRoomService;
    use crate::domain::user::{
        models::{
            meeting_link_name::MeetingLinkName, meeting_session_key::MeetingSessionKey, UserId,
        },
        ports::crypto_client::MockCryptoClient,
    };

    #[unified_test]
    async fn create_join_request_encrypts_key_package_with_session_key() {
        let key_package_bytes = Arc::new(vec![1, 2, 3, 4]);
        let encoded_key_package = general_purpose::STANDARD.encode(key_package_bytes.as_slice());
        let encrypted_payload = "dGVzdC1lbmNyeXB0ZWQ=";
        let session_key = MeetingSessionKey::from("session-key");

        let key_packages_bytes = key_package_bytes.clone();
        let mut key_packages = MockKeyPackagePort::new();
        key_packages
            .expect_new_key_package()
            .with(eq(UserId::new("user-1".to_string())))
            .times(1)
            .returning(move |_| {
                let key_packages_bytes = key_packages_bytes.clone();
                Box::pin(async move { Ok((*key_packages_bytes).clone()) })
            });

        let mut crypto_client = MockCryptoClient::new();
        crypto_client
            .expect_encrypt_message()
            .with(
                eq(encoded_key_package),
                eq("session-key"),
                eq(format!("test-room.{MEET_KEY_PACKAGE_AAD}")),
            )
            .times(1)
            .returning(|_, _, _| Box::pin(async { Ok(encrypted_payload.to_string()) }));

        let service = WaitingRoomService::new(Arc::new(crypto_client), Arc::new(key_packages));

        let join_request = service
            .create_join_request(
                &MeetingLinkName::from("test-room"),
                &UserId::new("user-1".to_string()),
                &session_key,
            )
            .await
            .expect("join request should be created");

        assert_eq!(
            join_request.encrypted_key_package,
            b"test-encrypted".to_vec(),
        );
        assert_eq!(join_request.meeting_link_name.as_str(), "test-room");
    }

    #[unified_test]
    async fn create_join_request_propagates_key_package_errors() {
        let mut key_packages = MockKeyPackagePort::new();
        key_packages
            .expect_new_key_package()
            .times(1)
            .returning(|_| Box::pin(async { Err(KeyPackageError::FailedToGenerateKeyPackage) }));

        let service =
            WaitingRoomService::new(Arc::new(MockCryptoClient::new()), Arc::new(key_packages));

        let error = service
            .create_join_request(
                &MeetingLinkName::from("test-room"),
                &UserId::new("user-1".to_string()),
                &MeetingSessionKey::from("session-key"),
            )
            .await
            .expect_err("key package failure should propagate");

        assert!(matches!(
            error,
            crate::domain::room::WaitingRoomError::KeyPackageError(
                KeyPackageError::FailedToGenerateKeyPackage
            )
        ));
    }
}
