#[cfg(test)]
mod tests {
    use cose_key_thumbprint::CoseKeyThumbprint;
    use ed25519_dalek::pkcs8::{DecodePrivateKey, DecodePublicKey};
    use identity::{Disclosure, Ed25519Issuer, ProtonMeetIdentity};
    use meet_identifiers::{Domain, GroupId, LeafIndex};
    use mls_spec::{
        defs::ProtocolVersion,
        messages::{MlsMessage, MlsMessageContent},
    };
    use mls_trait::ProposalArg;
    use proton_claims::{
        reexports::{cose_key_set::CoseKeySet, Issuer, IssuerParams, SpiceOidcClaims},
        MimiProvider,
    };
    use proton_claims::{ProtonMeetClaims, Role};
    use proton_meet_mls::{
        kv::MemKv, MlsClient, MlsClientConfig, MlsClientTrait, MlsGroup, MlsGroupConfig,
        MlsGroupTrait,
    };
    use sha2::Sha256;
    use uuid::Uuid;

    use crate::service::utils::{
        convert_mls_spec_to_types, convert_mls_types_to_spec, describe_proposal_kind,
        restore_to_queue,
    };
    use std::collections::HashMap;
    use std::sync::Arc;
    use tokio::sync::Mutex;

    // Helper function to create and initialize an MLS client with mock credentials
    async fn create_initialized_client(email: &str) -> MlsClient<MemKv> {
        let kv = MemKv::new();
        let (client, _) = MlsClient::new(kv, MlsClientConfig::default())
            .await
            .unwrap();
        let domain = Domain::new_random();

        let cnf = client.get_holder_confirmation_key_pem().unwrap();
        let issuer_sk = "-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIDR7w12ON3uzdZd8g6HIGOiGe/ozjj0rpBKs1VTVCyCM
-----END PRIVATE KEY-----";
        let issuer_signing_key = ed25519_dalek::SigningKey::from_pkcs8_pem(issuer_sk).unwrap();
        let issuer = Ed25519Issuer::new(issuer_signing_key.clone());
        let holder_verifying_key = ed25519_dalek::VerifyingKey::from_public_key_pem(&cnf).unwrap();
        let holder_confirmation_key = (&holder_verifying_key).try_into().unwrap();

        let payload = ProtonMeetClaims {
            meeting_id: "test_meeting".to_string(),
            uuid: Uuid::new_v4().into_bytes(),
            oidc_claims: SpiceOidcClaims::default(),
            role: Role::User,
            mimi_provider: MimiProvider::ProtonAg,
            is_from_server: false,
            is_host: false,
        };

        // Generate device ID from holder verifying key
        let mimi_device_id = CoseKeyThumbprint::<32>::compute::<Sha256>(&holder_verifying_key)
            .unwrap()
            .to_string();

        // Generate subject with correct format: mimi://{host}/d/{user_identifier}/{device_id}
        let user_identifier = email.to_string();
        let sub = format!("mimi://{domain}/d/{user_identifier}/{mimi_device_id}");

        let params = IssuerParams {
            protected_claims: None,
            unprotected_claims: None,
            payload: Some(payload),
            subject: Some(&sub),
            audience: None,
            expiry: None,
            with_not_before: false,
            with_issued_at: false,
            cti: None,
            cnonce: None,
            key_location: "https://auth.proton.me/issuer.cwk",
            holder_confirmation_key,
            issuer: "mimi://i/proton.me",
            leeway: Default::default(),
        };

        let sd_cwt = issuer.issue_cwt(&mut rand::thread_rng(), params).unwrap();
        let cks = CoseKeySet::new(&issuer_signing_key).unwrap();
        client.initialize(MemKv::new(), sd_cwt, &cks, &cks).unwrap()
    }

    async fn create_test_mls_group() -> MlsGroup<MemKv> {
        let mut client = create_initialized_client("user1@proton.me").await;
        let user_id = client.sd_cwt_mut().unwrap().user_id().unwrap();
        let group_id = GroupId::new(&user_id.domain);

        let group = client
            .new_group(
                &group_id,
                Disclosure::Full,
                MlsGroupConfig::default(user_id.clone(), false),
            )
            .await
            .unwrap()
            .store()
            .await
            .unwrap();

        group
    }

    #[tokio::test]
    async fn test_describe_proposal_kind_add() {
        // Skip Add proposal test for now - requires external commit setup
        // This test can be added later when we have a proper way to create Add proposals
    }

    #[tokio::test]
    async fn test_describe_proposal_kind_remove() {
        let mut group = create_test_mls_group().await;

        // Create Remove proposal (removing self)
        let own_leaf_index = group.own_leaf_index().unwrap();
        let leaf_index = LeafIndex::try_from(*own_leaf_index).unwrap();
        let mut proposals = group
            .new_proposals([ProposalArg::Remove(leaf_index)])
            .await
            .unwrap();
        let remove_proposal = proposals.remove(0);

        let result = describe_proposal_kind(&remove_proposal);
        assert_eq!(result, Some("REMOVE"));
    }

    #[tokio::test]
    async fn test_describe_proposal_kind_non_proposal() {
        let mut group = create_test_mls_group().await;

        // Create a commit (not a proposal)
        let (commit_bundle, ..) = group.new_commit([]).await.unwrap();
        let commit = commit_bundle.commit;

        // Commit should not be recognized as a proposal
        let result = describe_proposal_kind(&commit);
        assert_eq!(result, None);
    }

    #[tokio::test]
    async fn test_convert_mls_types_to_spec_and_back() {
        let mut group = create_test_mls_group().await;

        // Create a proposal
        let own_leaf_index = group.own_leaf_index().unwrap();
        let leaf_index = LeafIndex::try_from(*own_leaf_index).unwrap();
        let mut proposals = group
            .new_proposals([ProposalArg::Remove(leaf_index)])
            .await
            .unwrap();
        let proposal = proposals.remove(0);

        // Convert mls_types -> mls_spec
        let spec_message = convert_mls_types_to_spec(&proposal).unwrap();

        // Verify it's a valid mls_spec message (check it can be parsed)
        assert!(spec_message.version == ProtocolVersion::Mls10);

        // Convert back mls_spec -> mls_types
        let types_message = convert_mls_spec_to_types(&spec_message).unwrap();

        // Verify we can still recognize it as a proposal
        let proposal_kind = describe_proposal_kind(&types_message);
        assert_eq!(proposal_kind, Some("REMOVE"));
    }

    #[tokio::test]
    async fn test_convert_group_info_roundtrip() {
        let mut group = create_test_mls_group().await;

        // Create a commit to get GroupInfo
        let (commit_bundle, ..) = group.new_commit([]).await.unwrap();
        let group_info_message = commit_bundle.group_info.unwrap();

        // Convert mls_types -> mls_spec
        let spec_message = convert_mls_types_to_spec(&group_info_message).unwrap();

        // Verify it's a GroupInfo message
        assert!(matches!(
            spec_message.content,
            MlsMessageContent::GroupInfo(_)
        ));

        // Convert back mls_spec -> mls_types
        let types_message = convert_mls_spec_to_types(&spec_message).unwrap();

        // Verify it's still a valid GroupInfo
        assert!(types_message.as_group_info().is_some());
    }

    #[tokio::test]
    async fn test_convert_commit_roundtrip() {
        let mut group = create_test_mls_group().await;

        // Create a commit
        let (commit_bundle, ..) = group.new_commit([]).await.unwrap();
        let commit = commit_bundle.commit;

        // Convert mls_types -> mls_spec
        let spec_message = convert_mls_types_to_spec(&commit).unwrap();

        // Verify it's a valid mls_spec message
        assert!(spec_message.version == ProtocolVersion::Mls10);

        // Convert back mls_spec -> mls_types
        let types_message = convert_mls_spec_to_types(&spec_message).unwrap();

        // Verify it's still a valid Commit (has epoch)
        assert!(types_message.epoch().is_some());
    }

    #[tokio::test]
    async fn test_convert_mls_spec_group_info_to_types() {
        let mut group = create_test_mls_group().await;

        // Create a commit to get a real GroupInfo
        let (commit_bundle, ..) = group.new_commit([]).await.unwrap();
        let group_info_types = commit_bundle.group_info.unwrap();

        // Convert to mls_spec first
        let spec_message = convert_mls_types_to_spec(&group_info_types).unwrap();

        // Extract GroupInfo from mls_spec message
        let group_info = match spec_message.content {
            MlsMessageContent::GroupInfo(gi) => gi,
            _ => panic!("Expected GroupInfo"),
        };

        // Create a new mls_spec message with this GroupInfo
        let app_message = MlsMessage {
            version: ProtocolVersion::Mls10,
            content: MlsMessageContent::GroupInfo(group_info),
        };

        // Convert mls_spec -> mls_types
        let types_message = convert_mls_spec_to_types(&app_message).unwrap();

        // Verify it's a GroupInfo
        assert!(types_message.as_group_info().is_some());

        // Convert back mls_types -> mls_spec
        let spec_message2 = convert_mls_types_to_spec(&types_message).unwrap();
        assert!(matches!(
            spec_message2.content,
            MlsMessageContent::GroupInfo(_)
        ));
    }

    #[tokio::test]
    async fn test_restore_to_queue_empty_queue() {
        let queue: Arc<Mutex<HashMap<String, Vec<u32>>>> = Arc::new(Mutex::new(HashMap::new()));
        let room_id = "room1".to_string();
        let items = vec![1, 2, 3];

        restore_to_queue(queue.clone(), room_id.clone(), items, "test error");

        // Wait a bit for the async task to complete
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        let queue_lock = queue.lock().await;
        let restored_items = queue_lock.get(&room_id).unwrap();
        assert_eq!(restored_items, &vec![1, 2, 3]);
    }

    #[tokio::test]
    async fn test_restore_to_queue_append_existing() {
        let mut initial_map = HashMap::new();
        initial_map.insert("room1".to_string(), vec![10, 20]);
        let queue: Arc<Mutex<HashMap<String, Vec<u32>>>> = Arc::new(Mutex::new(initial_map));
        let room_id = "room1".to_string();
        let items = vec![30, 40];

        restore_to_queue(queue.clone(), room_id.clone(), items, "test error");

        // Wait a bit for the async task to complete
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        let queue_lock = queue.lock().await;
        let restored_items = queue_lock.get(&room_id).unwrap();
        // Should append, not replace
        assert_eq!(restored_items, &vec![10, 20, 30, 40]);
    }

    #[tokio::test]
    async fn test_restore_to_queue_empty_items() {
        let queue: Arc<Mutex<HashMap<String, Vec<u32>>>> = Arc::new(Mutex::new(HashMap::new()));
        let room_id = "room1".to_string();
        let items = Vec::<u32>::new();

        restore_to_queue(queue.clone(), room_id.clone(), items, "test error");

        // Wait a bit for the async task to complete
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        let queue_lock = queue.lock().await;
        // Should not create an entry for empty items
        assert!(queue_lock.get(&room_id).is_none());
    }

    #[tokio::test]
    async fn test_restore_to_queue_different_rooms() {
        let queue: Arc<Mutex<HashMap<String, Vec<u32>>>> = Arc::new(Mutex::new(HashMap::new()));
        let room1 = "room1".to_string();
        let room2 = "room2".to_string();

        restore_to_queue(queue.clone(), room1.clone(), vec![1, 2], "test error");
        restore_to_queue(queue.clone(), room2.clone(), vec![3, 4], "test error");

        // Wait a bit for the async tasks to complete
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        let queue_lock = queue.lock().await;
        assert_eq!(queue_lock.get(&room1).unwrap(), &vec![1, 2]);
        assert_eq!(queue_lock.get(&room2).unwrap(), &vec![3, 4]);
    }
}
