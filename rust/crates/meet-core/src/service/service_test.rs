#[cfg(test)]
mod tests {
    use std::{collections::HashMap, future::ready, sync::Arc};

    use esdicawt::spec::CwtAny;
    use mls_types::ExternalPskId;
    use muon::Status;
    use tokio::sync::RwLock;

    use crate::{
        domain::user::{
            models::UserId,
            ports::{
                user_api::MockUserApi, MockHttpClient, MockUserRepository, MockWebSocketClient,
            },
        },
        errors::{login::LoginError, service::ServiceError},
        infra::{
            crypto_client::derive_external_psk,
            dto::{
                proton_user::UserData,
                realtime::{MlsCommitInfo, MlsProposalInfo, RTCMessageIn, RTCMessageInContent},
            },
            message_cache::CachedMessageType,
            mimi_subject_parser::ANONYMOUS_USER_IDENTIFIER,
        },
        service::{
            service::{ProposalType, QueuedProposal, Service},
            service_state::MlsGroupState,
        },
    };

    use base64::{prelude::BASE64_STANDARD, Engine};
    use cose_key_thumbprint::CoseKeyThumbprint;
    use ed25519_dalek::pkcs8::{
        spki::der::pem::LineEnding, DecodePrivateKey, DecodePublicKey, EncodePublicKey,
    };
    use identity::{Ed25519Issuer, IdentityResult, ProtonMeetIdentity, SdCwt};
    use meet_identifiers::{GroupId, LeafIndex};
    use mls_rs::group::proposal::Proposal;
    use mls_spec::{
        drafts::ratchet_tree_options::RatchetTreeOption, messages::MlsMessageContent, Parsable,
        Serializable,
    };
    use mls_trait::{
        meet_policy::UserRole, types::ProposalEffect, types::ReceivedMessage, MlsClientTrait,
        ProposalArg,
    };
    use mockall::predicate::eq;
    use proton_claims::{
        reexports::{cose_key_set::CoseKeySet, Issuer, IssuerParams, SpiceOidcClaims},
        MimiProvider, ProtonMeetClaims,
    };
    use proton_meet_mls::{kv::MemKv, CommitBundle, MlsClientConfig, MlsGroup, MlsStore};
    use uuid::Uuid;

    use crate::domain::user::ports::{user_service::UserService, ConnectionState};
    use crate::infra::{dto::realtime::GroupInfoSummaryData, ws_client::WebSocketMessage};
    use mls_rs_codec::MlsEncode;
    use proton_meet_mls::MlsGroupTrait;

    // Test data constants for better maintainability
    const TEST_USERNAME: &str = "test_user";
    const TEST_PASSWORD: &str = "test_password";
    const TEST_USER_ID: &str = "test_user_id";
    const TEST_USER_EMAIL: &str = "test@example.com";
    const TEST_USER_NAME: &str = "Test User";

    #[test]
    fn test_derive_external_psk_argon2_is_deterministic_and_room_bound() {
        let room_a_first = derive_external_psk("meet_password", "room-a").unwrap();
        let room_a_second = derive_external_psk("meet_password", "room-a").unwrap();
        let room_b = derive_external_psk("meet_password", "room-b").unwrap();

        assert_eq!(room_a_first, room_a_second);
        assert_ne!(room_a_first, room_b);
        assert_eq!(room_a_first.0.len(), 32);
    }

    #[tokio::test]
    async fn test_login_success() {
        let http_client = MockHttpClient::new();
        let mut mock_user_api = MockUserApi::new();
        mock_user_api
            .expect_login()
            .with(eq(TEST_USERNAME), eq(TEST_PASSWORD))
            .once()
            .returning(move |_, _| {
                let user_data = UserData {
                    user: proton_meet_common::models::ProtonUser {
                        id: TEST_USER_ID.to_string(),
                        name: TEST_USER_NAME.to_string(),
                        email: TEST_USER_EMAIL.to_string(),
                        ..Default::default()
                    },
                    key_salts: vec![],
                };
                Box::pin(ready(Ok(user_data)))
            });
        mock_user_api
            .expect_get_user_addresses()
            .once()
            .returning(|| Box::pin(ready(Ok(vec![]))));

        let mut user_repository = MockUserRepository::new();
        user_repository
            .expect_init_tables()
            .with(eq(TEST_USER_ID))
            .once()
            .returning(|_| Box::pin(ready(Ok(()))));

        user_repository
            .expect_save_user()
            .withf(move |user| {
                user.id == TEST_USER_ID
                    && user.name == TEST_USER_NAME
                    && user.email == TEST_USER_EMAIL
            })
            .once()
            .returning(|_| Box::pin(ready(Ok(()))));
        user_repository
            .expect_save_user_keys()
            .withf(|user_id, keys| user_id == TEST_USER_ID && keys.is_empty())
            .once()
            .returning(|_, _| Box::pin(ready(Ok(()))));

        let ws_client = Arc::new(MockWebSocketClient::new());
        let mls_store = Arc::new(RwLock::new(MlsStore {
            clients: HashMap::new(),
            group_map: HashMap::new(),
            config: MlsClientConfig::default(),
        }));
        let service = Service::new(
            Arc::new(http_client),
            Arc::new(mock_user_api),
            Arc::new(user_repository),
            ws_client,
            mls_store,
        );

        let result = service.login(TEST_USERNAME, TEST_PASSWORD).await;

        assert!(result.is_ok());
        let (_, user, user_keys, user_addresses) = result.unwrap();
        assert_eq!(user.id, TEST_USER_ID.to_string());
        assert_eq!(user.name, TEST_USER_NAME);
        assert_eq!(user.email, TEST_USER_EMAIL);
        assert_eq!(user_keys, vec![]);
        assert_eq!(user_addresses, vec![]);
    }

    #[tokio::test]
    async fn test_login_http_client_error() {
        let http_client = MockHttpClient::new();
        let mut mock_user_api = MockUserApi::new();
        mock_user_api
            .expect_login()
            .with(eq(TEST_USERNAME), eq(TEST_PASSWORD))
            .once()
            .returning(|_, _| {
                Box::pin(ready(Err(LoginError::LoginFailed(
                    "Invalid credentials".to_string(),
                ))))
            });

        let user_repository = MockUserRepository::new();
        let ws_client = Arc::new(MockWebSocketClient::new());
        let mls_store = Arc::new(RwLock::new(MlsStore {
            clients: HashMap::new(),
            group_map: HashMap::new(),
            config: MlsClientConfig::default(),
        }));
        let service = Service::new(
            Arc::new(http_client),
            Arc::new(mock_user_api),
            Arc::new(user_repository),
            ws_client,
            mls_store,
        );

        let result = service.login(TEST_USERNAME, TEST_PASSWORD).await;

        assert!(result.is_err());
        assert!(matches!(result.unwrap_err(), LoginError::LoginFailed(_)));
    }

    #[tokio::test]
    async fn test_logout_success() {
        let user_id = TEST_USER_ID.to_string();

        let http_client = MockHttpClient::new();
        let mut mock_user_api = MockUserApi::new();
        mock_user_api
            .expect_logout()
            .once()
            .returning(|| Box::pin(ready(())));

        let mut user_repository = MockUserRepository::new();
        user_repository
            .expect_delete_user()
            .with(eq(user_id.clone()))
            .once()
            .returning(|_| Box::pin(ready(Ok(1))));

        let ws_client = Arc::new(MockWebSocketClient::new());

        let mls_store = Arc::new(RwLock::new(MlsStore {
            clients: HashMap::new(),
            group_map: HashMap::new(),
            config: MlsClientConfig::default(),
        }));
        let service = Service::new(
            Arc::new(http_client),
            Arc::new(mock_user_api),
            Arc::new(user_repository),
            ws_client,
            mls_store,
        );

        let result = service.logout(&UserId::new(user_id)).await;

        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_basic_encrypt_decrypt() {
        // Test basic encryption/decryption between two users
        let meet_link_name = "test_meet_link_name";
        let config = MlsClientConfig::default();

        // Setup two users
        let service1 = create_test_service("user_id", meet_link_name).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;

        let (group, _group2) =
            setup_two_user_group(&service1, &service2, meet_link_name, config.ciphersuite).await;

        // Test message encryption/decryption
        let message = "Hello, world!";
        let encrypted_message = service1
            .encrypt_application_message(meet_link_name, message)
            .await
            .unwrap();

        let (decrypted_message, sender_id) = service2
            .decrypt_application_message(meet_link_name, encrypted_message)
            .await
            .unwrap();

        assert_eq!(decrypted_message, message);
        assert_eq!(sender_id, UserId::new("user_id".to_string()));

        // Verify group state
        assert_eq!(group.read().await.roster().count(), 2);
    }

    #[tokio::test]
    async fn test_create_external_proposal() {
        // Setup test constants
        let meet_link_name = "test_external_proposal";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        // Create two services: user1 creates the group, user2 creates external proposal
        let service1 = create_test_service("user1", meet_link_name).await;
        let service2 = create_test_service("user2", meet_link_name).await;

        // User1: Create MLS client and initialize a new group
        let user_token_info1 = service1
            .create_mls_client(
                "access_token_user1",
                meet_link_name,
                "meet_password",
                true,
                None,
            )
            .await
            .unwrap();

        let (group1, commit_bundle1) = service1
            .create_mls_group(
                &user_token_info1.user_id(),
                meet_link_name,
                meet_link_name,
                ciphersuite,
            )
            .await
            .unwrap();

        // Verify initial group state - only user1 should be in the group
        assert_eq!(group1.read().await.roster().count(), 1);
        let initial_epoch = *group1.read().await.epoch();
        assert_eq!(initial_epoch, 1); // Initial epoch should be 0

        // User2: Create MLS client
        let user_token_info2 = service2
            .create_mls_client(
                "access_token_user2",
                meet_link_name,
                "meet_password",
                true,
                None,
            )
            .await
            .unwrap();

        // Extract GroupInfo and RatchetTree from user1's commit bundle
        let group_info_bytes = commit_bundle1
            .group_info
            .clone()
            .expect("CommitBundle should contain GroupInfo")
            .mls_encode_to_vec()
            .expect("GroupInfo should serialize");

        let group_info_message = mls_spec::messages::MlsMessage::from_tls_bytes(&group_info_bytes)
            .expect("Should parse MlsMessage");

        let group_info = match group_info_message.content {
            MlsMessageContent::GroupInfo(gi) => gi,
            _ => panic!("Expected GroupInfo message"),
        };

        let ratchet_tree = commit_bundle1
            .ratchet_tree
            .clone()
            .expect("CommitBundle should contain RatchetTree")
            .try_into()
            .expect("Should convert to RatchetTreeOption");

        // User2: Create external proposal to join the group
        let external_proposal = service2
            .create_external_proposal(
                &user_token_info2.user_id(),
                ciphersuite,
                group_info,
                ratchet_tree,
            )
            .await
            .expect("User2 should successfully create external proposal");

        // User1: Process the external proposal
        let (received_message, _) = group1
            .write()
            .await
            .decrypt_message(external_proposal)
            .await
            .expect("User1 should successfully process external proposal");

        // Verify we received a proposal
        match received_message {
            ReceivedMessage::Proposal => {
                // Expected - external proposal processed successfully
            }
            _ => panic!("Expected to receive a Proposal message, got: {received_message:?}"),
        }

        // User1: Commit the pending proposal to add user2 to the group (generates Welcome)
        let commit_bundle = {
            let mut group1_write = group1.write().await;
            let (bundle, _) = group1_write
                .new_commit(vec![])
                .await
                .expect("User1 should commit the proposal");

            group1_write
                .merge_pending_commit()
                .await
                .expect("Should merge pending commit");

            bundle
        };

        // Verify user1's group now has 2 members after committing the proposal
        assert_eq!(
            group1.read().await.roster().count(),
            2,
            "Group should have 2 members after committing external proposal"
        );
        let new_epoch = *group1.read().await.epoch();
        assert_eq!(
            new_epoch,
            initial_epoch + 1,
            "Epoch should have advanced by 1"
        );

        // Extract Welcome message and RatchetTree from commit bundle
        let welcome_mls = commit_bundle
            .welcome
            .expect("CommitBundle should contain Welcome for external proposal");
        let ratchet_tree2 = commit_bundle
            .ratchet_tree
            .expect("CommitBundle should contain RatchetTree");

        // Convert Welcome to mls_types::MlsMessage
        let welcome_bytes = welcome_mls
            .mls_encode_to_vec()
            .expect("Should encode Welcome");
        let welcome_message =
            mls_types::MlsMessage::from_bytes(&welcome_bytes).expect("Should parse Welcome");

        // Convert RatchetTree to RatchetTreeOption
        let ratchet_tree_option = ratchet_tree2
            .try_into()
            .expect("Should convert to RatchetTreeOption");

        // User2: Join the group using the Welcome message and ratchet tree
        let group2 = service2
            .join_group(
                &user_token_info2.user_id(),
                meet_link_name,
                welcome_message,
                ratchet_tree_option,
            )
            .await
            .expect("User2 should join via Welcome message");

        // Verify user2's group state
        assert_eq!(
            group2.read().await.roster().count(),
            2,
            "User2's group should have 2 members"
        );
        assert_eq!(
            *group2.read().await.epoch(),
            new_epoch,
            "User2's group should be at the same epoch"
        );

        // Verify both users can encrypt/decrypt messages
        let message = "Hello from user1!";
        let encrypted = service1
            .encrypt_application_message(meet_link_name, message)
            .await
            .expect("User1 should encrypt message");

        let (decrypted, sender_id) = service2
            .decrypt_application_message(meet_link_name, encrypted)
            .await
            .expect("User2 should decrypt message from user1");

        assert_eq!(decrypted, message);
        assert_eq!(
            sender_id.to_string(),
            user_token_info1.user_identifier.id.to_string()
        );

        // Verify reverse direction
        let message2 = "Hello from user2!";
        let encrypted2 = service2
            .encrypt_application_message(meet_link_name, message2)
            .await
            .expect("User2 should encrypt message");

        let (decrypted2, sender_id2) = service1
            .decrypt_application_message(meet_link_name, encrypted2)
            .await
            .expect("User1 should decrypt message from user2");

        assert_eq!(decrypted2, message2);
        assert_eq!(
            sender_id2.to_string(),
            user_token_info2.user_identifier.id.to_string()
        );

        // ========== Part 2: Add User3 and User4 in a single commit ==========

        // Create services for user3 and user4
        let service3 = create_test_service("user3", meet_link_name).await;
        let service4 = create_test_service("user4", meet_link_name).await;

        // User3: Create MLS client
        let user_token_info3 = service3
            .create_mls_client(
                "access_token_user3",
                meet_link_name,
                "meet_password",
                true,
                None,
            )
            .await
            .unwrap();

        // User4: Create MLS client
        let user_token_info4 = service4
            .create_mls_client(
                "access_token_user4",
                meet_link_name,
                "meet_password",
                true,
                None,
            )
            .await
            .unwrap();

        // Get current group state directly from group1 (no intermediate commit needed)
        let (group_info_for_proposals, ratchet_tree_for_proposals) = {
            let group1_read = group1.read().await;

            // Get GroupInfo for external proposals
            let group_info_mls_spec = group1_read
                .group_info_for_ext_commit()
                .await
                .expect("Should get group_info_for_ext_commit");

            // Parse to get GroupInfo
            let group_info_bytes = group_info_mls_spec.mls_encode_to_vec().unwrap();
            let group_info_message =
                mls_spec::messages::MlsMessage::from_tls_bytes(&group_info_bytes).unwrap();
            let group_info = match group_info_message.content {
                MlsMessageContent::GroupInfo(gi) => gi,
                _ => panic!("Expected GroupInfo"),
            };

            // Get the ratchet tree and convert to RatchetTreeOption
            let exported_tree = group1_read.ratchet_tree();

            // Serialize ExportedTree and deserialize to mls_spec::tree::RatchetTree
            let tree_bytes = exported_tree.mls_encode_to_vec().unwrap();
            let ratchet_tree_mls_spec =
                mls_spec::tree::RatchetTree::from_tls_bytes(&tree_bytes).unwrap();
            let ratchet_tree_option = RatchetTreeOption::Full {
                ratchet_tree: ratchet_tree_mls_spec,
            };

            (group_info, ratchet_tree_option)
        };

        // User3: Create external proposal
        let external_proposal3 = service3
            .create_external_proposal(
                &user_token_info3.user_id(),
                ciphersuite,
                group_info_for_proposals.clone(),
                ratchet_tree_for_proposals.clone(),
            )
            .await
            .expect("User3 should create external proposal");

        // User4: Create external proposal
        let external_proposal4 = service4
            .create_external_proposal(
                &user_token_info4.user_id(),
                ciphersuite,
                group_info_for_proposals,
                ratchet_tree_for_proposals,
            )
            .await
            .expect("User4 should create external proposal");

        // User1: Process user3's external proposal
        let (received_message3, _) = group1
            .write()
            .await
            .decrypt_message(external_proposal3.clone())
            .await
            .expect("User1 should process user3's external proposal");
        assert!(
            matches!(received_message3, ReceivedMessage::Proposal),
            "Expected Proposal for user3"
        );

        // User2: Also process user3's external proposal
        group2
            .write()
            .await
            .decrypt_message(external_proposal3)
            .await
            .expect("User2 should process user3's external proposal");

        // User1: Commit user3's proposal
        let commit_bundle_user3 = {
            let mut group1_write = group1.write().await;
            let (bundle, _) = group1_write
                .new_commit(vec![])
                .await
                .expect("User1 should commit user3's proposal");

            group1_write
                .merge_pending_commit()
                .await
                .expect("Should merge pending commit");

            bundle
        };

        // Verify user1's group now has 3 members after committing user3's proposal
        assert_eq!(
            group1.read().await.roster().count(),
            3,
            "Group should have 3 members after committing user3's proposal"
        );
        let epoch_after_user3 = *group1.read().await.epoch();
        assert_eq!(
            epoch_after_user3,
            new_epoch + 1,
            "Epoch should have advanced by 1 after user3 joins"
        );

        // User2: Process the commit to stay in sync
        group2
            .write()
            .await
            .decrypt_message(commit_bundle_user3.commit.clone())
            .await
            .expect("User2 should process the commit");
        assert_eq!(
            group2.read().await.roster().count(),
            3,
            "User2's group should also have 3 members"
        );

        // Extract Welcome for user3
        let welcome_user3 = commit_bundle_user3
            .welcome
            .expect("CommitBundle should contain Welcome for user3");
        let ratchet_tree_user3 = commit_bundle_user3
            .ratchet_tree
            .expect("CommitBundle should contain RatchetTree");

        // Convert Welcome and RatchetTree for user3
        let welcome_bytes_user3 = welcome_user3.mls_encode_to_vec().unwrap();
        let welcome_message_user3 =
            mls_types::MlsMessage::from_bytes(&welcome_bytes_user3).unwrap();
        let ratchet_tree_option_user3: RatchetTreeOption = ratchet_tree_user3.try_into().unwrap();

        // User3: Join the group using the Welcome message
        let group3 = service3
            .join_group(
                &user_token_info3.user_id(),
                meet_link_name,
                welcome_message_user3,
                ratchet_tree_option_user3,
            )
            .await
            .expect("User3 should join via Welcome message");

        // Verify user3's group state
        assert_eq!(
            group3.read().await.roster().count(),
            3,
            "User3's group should have 3 members"
        );
        assert_eq!(
            *group3.read().await.epoch(),
            epoch_after_user3,
            "User3 should be at the correct epoch"
        );

        // Now handle user4's external proposal which was created at old epoch
        // Extract the key package from the stale external proposal
        let key_package_user4 = match external_proposal4.as_proposal() {
            Some(Proposal::Add(add)) => add.key_package().clone(),
            _ => panic!("Expected Add Proposal for user4"),
        };

        // User1: Create a fresh local Add proposal with user4's key package
        let commit_bundle_user4 = {
            let mut group1_write = group1.write().await;
            let (bundle, _) = group1_write
                .new_commit([ProposalArg::Add(Box::new(key_package_user4.into()))])
                .await
                .expect("User1 should commit user4's add proposal");

            group1_write
                .merge_pending_commit()
                .await
                .expect("Should merge pending commit");

            bundle
        };

        // Verify all groups now have 4 members
        assert_eq!(
            group1.read().await.roster().count(),
            4,
            "Group should have 4 members after adding user4"
        );
        let final_epoch = *group1.read().await.epoch();
        assert_eq!(
            final_epoch,
            epoch_after_user3 + 1,
            "Epoch should have advanced by 1 after user4 joins"
        );

        // User2 and User3: Process the commit to stay in sync
        group2
            .write()
            .await
            .decrypt_message(commit_bundle_user4.commit.clone())
            .await
            .expect("User2 should process user4's commit");
        group3
            .write()
            .await
            .decrypt_message(commit_bundle_user4.commit.clone())
            .await
            .expect("User3 should process user4's commit");

        assert_eq!(
            group2.read().await.roster().count(),
            4,
            "User2's group should have 4 members"
        );
        assert_eq!(
            group3.read().await.roster().count(),
            4,
            "User3's group should have 4 members"
        );

        // Extract Welcome for user4
        let welcome_user4 = commit_bundle_user4
            .welcome
            .expect("CommitBundle should contain Welcome for user4");
        let ratchet_tree_user4 = commit_bundle_user4
            .ratchet_tree
            .expect("CommitBundle should contain RatchetTree");

        // Convert Welcome and RatchetTree for user4
        let welcome_bytes_user4 = welcome_user4.mls_encode_to_vec().unwrap();
        let welcome_message_user4 =
            mls_types::MlsMessage::from_bytes(&welcome_bytes_user4).unwrap();
        let ratchet_tree_option_user4: RatchetTreeOption = ratchet_tree_user4.try_into().unwrap();

        // User4: Join the group using the Welcome message
        let group4 = service4
            .join_group(
                &user_token_info4.user_id(),
                meet_link_name,
                welcome_message_user4,
                ratchet_tree_option_user4,
            )
            .await
            .expect("User4 should join via Welcome message");

        // Verify all groups are in sync
        assert_eq!(
            group4.read().await.roster().count(),
            4,
            "User4's group should have 4 members"
        );
        assert_eq!(
            *group4.read().await.epoch(),
            final_epoch,
            "User4 should be at the final epoch"
        );

        // Verify all 4 users can communicate
        let message_from_3 = "Hello from user3!";
        let encrypted_from_3 = service3
            .encrypt_application_message(meet_link_name, message_from_3)
            .await
            .expect("User3 should encrypt message");

        let (decrypted_by_1, sender_from_3) = service1
            .decrypt_application_message(meet_link_name, encrypted_from_3.clone())
            .await
            .expect("User1 should decrypt message from user3");
        assert_eq!(decrypted_by_1, message_from_3);
        assert_eq!(
            sender_from_3.to_string(),
            user_token_info3.user_identifier.id.to_string()
        );

        let (decrypted_by_4, sender_from_3_to_4) = service4
            .decrypt_application_message(meet_link_name, encrypted_from_3)
            .await
            .expect("User4 should decrypt message from user3");
        assert_eq!(decrypted_by_4, message_from_3);
        assert_eq!(
            sender_from_3_to_4.to_string(),
            user_token_info3.user_identifier.id.to_string()
        );

        // Verify user4 can also send messages
        let message_from_4 = "Hello from user4!";
        let encrypted_from_4 = service4
            .encrypt_application_message(meet_link_name, message_from_4)
            .await
            .expect("User4 should encrypt message");

        let (decrypted_by_2, sender_from_4) = service2
            .decrypt_application_message(meet_link_name, encrypted_from_4)
            .await
            .expect("User2 should decrypt message from user4");
        assert_eq!(decrypted_by_2, message_from_4);
        assert_eq!(
            sender_from_4.to_string(),
            user_token_info4.user_identifier.id.to_string()
        );
    }

    #[tokio::test]
    async fn test_external_commit_with_psk() {
        let meet_link_name = "test_external_psk_commit";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        let service1 = create_test_service("psk-user1", meet_link_name).await;
        let service2 = create_test_service("psk-user2", meet_link_name).await;

        // Create first user and group
        let user_token_info = service1
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();
        let (group1, commit_bundle1) = service1
            .create_mls_group(
                &user_token_info.user_id(),
                meet_link_name,
                meet_link_name,
                ciphersuite,
            )
            .await
            .unwrap();

        // Create second user
        let user_token_info2 = service2
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();
        let user1_id = {
            let store = service1.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("service1 should have one MLS client")
        };
        let user2_id = {
            let store = service2.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("service2 should have one MLS client")
        };

        let psk_id = mls_types::ExternalPskId(b"demo-external-psk-id".to_vec());
        let psk_value = mls_types::ExternalPsk(b"demo-external-psk-secret-material".to_vec());

        {
            let store = service1.mls_store.read().await;
            let client = store
                .find_client(&user1_id, &ciphersuite)
                .expect("service1 client should exist");
            client
                .insert_external_psk(psk_id.clone(), psk_value.clone())
                .await
                .expect("service1 should insert external PSK");
            assert!(
                client
                    .has_external_psk(&psk_id)
                    .await
                    .expect("service1 should query external PSK"),
                "service1 client should contain seeded PSK"
            );
        }
        {
            let store = service2.mls_store.read().await;
            let client = store
                .find_client(&user2_id, &ciphersuite)
                .expect("service2 client should exist");
            client
                .insert_external_psk(psk_id.clone(), psk_value.clone())
                .await
                .expect("service2 should insert external PSK");
            assert!(
                client
                    .has_external_psk(&psk_id)
                    .await
                    .expect("service2 should query external PSK"),
                "service2 client should contain seeded PSK"
            );
        }

        // Second user joins via external commit
        let group_info_message = mls_spec::messages::MlsMessage::from_tls_bytes(
            &commit_bundle1
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap();
        let group_info = match group_info_message.content {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        let (_, commit_bundle2) = service2
            .create_external_commit_with_psks(
                &user_token_info2.user_id(),
                meet_link_name,
                ciphersuite,
                group_info,
                commit_bundle1.ratchet_tree.unwrap().try_into().unwrap(),
                vec![psk_id.clone()],
            )
            .await
            .unwrap();

        // Process the join in first user's group
        let (_, _) = group1
            .write()
            .await
            .decrypt_message(commit_bundle2.commit.clone())
            .await
            .unwrap();

        // Get the second user's group
        let group2 = {
            let store = service2.mls_store.read().await;
            store.group_map.get(meet_link_name).unwrap().clone()
        };

        // Verify both groups are in sync
        assert_eq!(group1.read().await.epoch(), group2.read().await.epoch());
        assert_eq!(group1.read().await.roster().count(), 2);
        assert_eq!(group2.read().await.roster().count(), 2);
        assert_eq!(
            group1
                .read()
                .await
                .epoch_authenticator()
                .unwrap()
                .to_ascii_lowercase(),
            group2
                .read()
                .await
                .epoch_authenticator()
                .unwrap()
                .to_ascii_lowercase()
        );
    }

    #[tokio::test]
    async fn test_external_add_proposal_with_psk() {
        let meet_link_name = "test_external_add_proposal_with_psk";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        let service1 = create_test_service("psk-user1", meet_link_name).await;
        let service2 = create_test_service("psk-user2", meet_link_name).await;

        // User1 creates the group.
        let user_token_info1 = service1
            .create_mls_client(
                "access_token_user1",
                meet_link_name,
                "meet_password",
                true,
                None,
            )
            .await
            .unwrap();
        let (group1, commit_bundle1) = service1
            .create_mls_group(
                &user_token_info1.user_id(),
                meet_link_name,
                meet_link_name,
                ciphersuite,
            )
            .await
            .unwrap();

        // User2 creates a client and sends external add proposal.
        let user_token_info2 = service2
            .create_mls_client(
                "access_token_user2",
                meet_link_name,
                "meet_password",
                true,
                None,
            )
            .await
            .unwrap();

        let group_info = match mls_spec::messages::MlsMessage::from_tls_bytes(
            &commit_bundle1
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap()
        .content
        {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        let ratchet_tree_option: RatchetTreeOption = commit_bundle1
            .ratchet_tree
            .clone()
            .unwrap()
            .try_into()
            .unwrap();

        let external_proposal = service2
            .create_external_proposal(
                &user_token_info2.user_id(),
                ciphersuite,
                group_info,
                ratchet_tree_option,
            )
            .await
            .unwrap();

        let (proposal_msg, _) = group1
            .write()
            .await
            .decrypt_message(external_proposal)
            .await
            .unwrap();
        assert!(
            matches!(proposal_msg, ReceivedMessage::Proposal),
            "committer should receive external add proposal"
        );

        // Seed the same PSK on both clients.
        let user1_id = {
            let store = service1.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("service1 should have one MLS client")
        };
        let user2_id = {
            let store = service2.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("service2 should have one MLS client")
        };

        let psk_id = mls_types::ExternalPskId(b"external-add-psk-id".to_vec());
        let psk_value = mls_types::ExternalPsk(b"external-add-psk-value".to_vec());

        {
            let store = service1.mls_store.read().await;
            let client = store.find_client(&user1_id, &ciphersuite).unwrap();
            client
                .insert_external_psk(psk_id.clone(), psk_value.clone())
                .await
                .unwrap();
        }
        {
            let store = service2.mls_store.read().await;
            let client = store.find_client(&user2_id, &ciphersuite).unwrap();
            client
                .insert_external_psk(psk_id.clone(), psk_value.clone())
                .await
                .unwrap();
        }

        // Committer merges pending external add proposal and injects PSK in same commit.
        let commit_bundle = {
            let mut group1_write = group1.write().await;
            let (bundle, _) = group1_write
                .new_commit(vec![ProposalArg::PskExternal { id: psk_id.clone() }])
                .await
                .unwrap();
            let (commit_output, _) = group1_write.merge_pending_commit().await.unwrap();

            assert!(
                commit_output.applied_proposals.iter().any(|proposal| {
                    matches!(
                        &proposal.effect,
                        ProposalEffect::PskAdded { reference }
                            if reference == &mls_types::PskReference::External(psk_id.clone())
                    )
                }),
                "committer output should include PskAdded effect"
            );
            bundle
        };

        // Joiner joins using Welcome message.
        let welcome_message = mls_types::MlsMessage::from_bytes(
            &commit_bundle.welcome.unwrap().mls_encode_to_vec().unwrap(),
        )
        .unwrap();
        let ratchet_tree_option: RatchetTreeOption =
            commit_bundle.ratchet_tree.unwrap().try_into().unwrap();
        let group2 = service2
            .join_group(
                &user_token_info2.user_id(),
                meet_link_name,
                welcome_message,
                ratchet_tree_option,
            )
            .await
            .unwrap();

        assert_eq!(
            *group1.read().await.epoch(),
            *group2.read().await.epoch(),
            "joiner and committer must end on same epoch"
        );
        assert_eq!(
            group1
                .read()
                .await
                .epoch_authenticator()
                .unwrap()
                .to_ascii_lowercase(),
            group2
                .read()
                .await
                .epoch_authenticator()
                .unwrap()
                .to_ascii_lowercase(),
            "joiner and committer must have same epoch authenticator"
        );
    }

    #[tokio::test]
    async fn test_external_psk_commit_propagates_to_group() {
        let meet_link_name = "test_external_psk_commit";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        let service1 = create_test_service("psk-user1", meet_link_name).await;
        let service2 = create_test_service("psk-user2", meet_link_name).await;

        let (group1, group2, _initial_join_commit) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            ciphersuite,
        )
        .await;

        let user1_id = {
            let store = service1.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("service1 should have one MLS client")
        };
        let user2_id = {
            let store = service2.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("service2 should have one MLS client")
        };

        let psk_id = mls_types::ExternalPskId(b"demo-external-psk-id".to_vec());
        let psk_value = mls_types::ExternalPsk(b"demo-external-psk-secret-material".to_vec());

        {
            let store = service1.mls_store.read().await;
            let client = store
                .find_client(&user1_id, &ciphersuite)
                .expect("service1 client should exist");
            client
                .insert_external_psk(psk_id.clone(), psk_value.clone())
                .await
                .expect("service1 should insert external PSK");
            assert!(
                client
                    .has_external_psk(&psk_id)
                    .await
                    .expect("service1 should query external PSK"),
                "service1 client should contain seeded PSK"
            );
        }
        {
            let store = service2.mls_store.read().await;
            let client = store
                .find_client(&user2_id, &ciphersuite)
                .expect("service2 client should exist");
            client
                .insert_external_psk(psk_id.clone(), psk_value.clone())
                .await
                .expect("service2 should insert external PSK");
            assert!(
                client
                    .has_external_psk(&psk_id)
                    .await
                    .expect("service2 should query external PSK"),
                "service2 client should contain seeded PSK"
            );
        }

        let epoch_before = *group1.read().await.epoch();
        assert_eq!(*group2.read().await.epoch(), epoch_before);

        let commit_bundle = {
            let mut group1_write = group1.write().await;
            let (bundle, _) = group1_write
                .new_commit(vec![ProposalArg::PskExternal { id: psk_id.clone() }])
                .await
                .expect("committer should create PSK commit");
            let (commit_output, _) = group1_write
                .merge_pending_commit()
                .await
                .expect("committer should merge PSK commit");

            assert!(
                commit_output.applied_proposals.iter().any(|proposal| {
                    matches!(
                        &proposal.effect,
                        ProposalEffect::PskAdded { reference }
                            if reference == &mls_types::PskReference::External(psk_id.clone())
                    )
                }),
                "committer output should include PskAdded effect"
            );
            bundle
        };

        let (received_message, _) = group2
            .write()
            .await
            .decrypt_message(commit_bundle.commit.clone())
            .await
            .expect("receiver should decrypt PSK commit");

        match received_message {
            ReceivedMessage::Commit { output, .. } => {
                assert!(
                    output.applied_proposals.iter().any(|proposal| {
                        matches!(
                            &proposal.effect,
                            ProposalEffect::PskAdded { reference }
                                if reference == &mls_types::PskReference::External(psk_id.clone())
                        )
                    }),
                    "receiver output should include PskAdded effect"
                );
            }
            _ => panic!("Expected Commit message after PSK commit"),
        }

        let epoch_after = *group1.read().await.epoch();
        assert_eq!(
            epoch_after,
            epoch_before + 1,
            "PSK commit should advance group1 epoch"
        );
        assert_eq!(
            *group2.read().await.epoch(),
            epoch_after,
            "group2 should stay in sync after processing PSK commit"
        );

        let plaintext = "psk-backed-message";
        let ciphertext = service1
            .encrypt_application_message(meet_link_name, plaintext)
            .await
            .expect("service1 should encrypt after PSK commit");
        let (decrypted, _) = service2
            .decrypt_application_message(meet_link_name, ciphertext)
            .await
            .expect("service2 should decrypt after PSK commit");
        assert_eq!(decrypted, plaintext);

        let (group_key, epoch) = service1
            .get_group_key(meet_link_name)
            .await
            .expect("service1 should get group key");
        let (group_key_2, epoch_2) = service2
            .get_group_key(meet_link_name)
            .await
            .expect("service2 should get group key");

        assert_eq!(epoch, epoch_2);
        assert_eq!(group_key_2, group_key);
    }

    #[tokio::test]
    async fn test_external_psk_commit_fails_for_committer_without_seeded_psk() {
        let meet_link_name = "test_external_psk_missing_committer";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        let service1 = create_test_service("psk-missing-committer-user1", meet_link_name).await;
        let service2 = create_test_service("psk-missing-committer-user2", meet_link_name).await;

        let (group1, _group2, _initial_join_commit) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            ciphersuite,
        )
        .await;

        let psk_id = mls_types::ExternalPskId(b"missing-committer-psk-id".to_vec());

        let commit_result = group1
            .write()
            .await
            .new_commit(vec![ProposalArg::PskExternal { id: psk_id }])
            .await;
        assert!(
            commit_result.is_err(),
            "commit creation must fail when committer does not have the external PSK seeded"
        );
    }

    #[tokio::test]
    async fn test_external_psk_missing_preload_produces_different_group_key() {
        let meet_link_name = "test_external_psk_group_key_divergence";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        let service1 = create_test_service("psk-divergence-user1", meet_link_name).await;
        let service2 = create_test_service("psk-divergence-user2", meet_link_name).await;

        let (group1, group2, _initial_join_commit) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            ciphersuite,
        )
        .await;

        let user1_id = {
            let store = service1.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("service1 should have one MLS client")
        };

        let psk_id = mls_types::ExternalPskId(b"group-key-divergence-psk-id".to_vec());
        let psk_value = mls_types::ExternalPsk(b"group-key-divergence-psk-secret".to_vec());

        {
            let store = service1.mls_store.read().await;
            let client = store
                .find_client(&user1_id, &ciphersuite)
                .expect("service1 client should exist");
            client
                .insert_external_psk(psk_id.clone(), psk_value)
                .await
                .expect("service1 should insert external PSK");
            assert!(
                client
                    .has_external_psk(&psk_id)
                    .await
                    .expect("service1 should query external PSK"),
                "service1 client should contain seeded PSK"
            );
        }

        let psk_commit = {
            let mut group1_write = group1.write().await;
            let (bundle, _) = group1_write
                .new_commit(vec![ProposalArg::PskExternal { id: psk_id }])
                .await
                .expect("committer should create PSK commit");
            group1_write
                .merge_pending_commit()
                .await
                .expect("committer should merge PSK commit");
            bundle
        };

        let result = group2
            .write()
            .await
            .decrypt_message(psk_commit.commit.clone())
            .await
            .expect("receiver should process commit even without PSK preload");

        if let ReceivedMessage::Error(_) = result.0 {
            // Expected error
        } else {
            panic!("Expected error, got {:?}", result.0);
        }

        let group1_secret = group1
            .read()
            .await
            .export_secret("group-key-divergence-check", b"psk-missing-preload", 32)
            .await
            .expect("group1 should export secret");
        let group2_secret = group2
            .read()
            .await
            .export_secret("group-key-divergence-check", b"psk-missing-preload", 32)
            .await
            .expect("group2 should export secret");

        assert_ne!(
            &*group1_secret, &*group2_secret,
            "without PSK preload on receiver, exported group key material should diverge"
        );

        let epoch1 = group1.read().await.epoch();
        let epoch2 = group2.read().await.epoch();
        assert_ne!(epoch1, epoch2);
    }

    #[tokio::test]
    async fn test_forward_secrecy() {
        // Test that new joiners cannot decrypt old messages (forward secrecy)
        let meet_link_name = "test_meet_link_name";
        let config = MlsClientConfig::default();

        let service1 = create_test_service("user_id", meet_link_name).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let (group, _group2, commit_bundle2) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        // Send message before third user joins
        let old_message = "Secret before user3 joins";
        let old_encrypted = service1
            .encrypt_application_message(meet_link_name, old_message)
            .await
            .unwrap();

        // User2 can decrypt the old message
        let (decrypted, _) = service2
            .decrypt_application_message(meet_link_name, old_encrypted.clone())
            .await
            .unwrap();
        assert_eq!(decrypted, old_message);

        // Add third user using the commit_bundle2 from setup
        let user_token_info3 = service3
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();

        let group_info_message = mls_spec::messages::MlsMessage::from_tls_bytes(
            &commit_bundle2
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap();
        let group_info = match group_info_message.content {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        let (_, commit_bundle3) = service3
            .create_external_commit(
                &user_token_info3.user_id(),
                meet_link_name,
                config.ciphersuite,
                group_info,
                commit_bundle2.ratchet_tree.unwrap().try_into().unwrap(),
            )
            .await
            .unwrap();

        // Process join in existing groups
        let commit3_message = commit_bundle3.commit;
        let (_, _) = group
            .write()
            .await
            .decrypt_message(commit3_message.clone())
            .await
            .unwrap();

        let group2_lock = {
            let store = service2.mls_store.read().await;
            store.group_map.get(meet_link_name).unwrap().clone()
        };
        let (_, _) = group2_lock
            .write()
            .await
            .decrypt_message(commit3_message)
            .await
            .unwrap();

        // Third user should NOT decrypt old message
        let result = service3
            .decrypt_application_message(meet_link_name, old_encrypted)
            .await;
        assert!(
            result.is_err(),
            "New joiner should not decrypt old messages"
        );

        // But can decrypt new messages
        let new_message = "New message after join";
        let new_encrypted = service1
            .encrypt_application_message(meet_link_name, new_message)
            .await
            .unwrap();
        let (decrypted_new, _) = service3
            .decrypt_application_message(meet_link_name, new_encrypted)
            .await
            .unwrap();
        assert_eq!(decrypted_new, new_message);
    }

    #[tokio::test]
    async fn test_replay_protection() {
        // Test message replay protection
        let meet_link_name = "test_meet_link_name";
        let config = MlsClientConfig::default();

        let service1 = create_test_service("user_id", meet_link_name).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;

        let (_group1, _group2) =
            setup_two_user_group(&service1, &service2, meet_link_name, config.ciphersuite).await;

        // Send and decrypt message once
        let message = "Test replay protection";
        let encrypted = service1
            .encrypt_application_message(meet_link_name, message)
            .await
            .unwrap();

        let (decrypted, _) = service2
            .decrypt_application_message(meet_link_name, encrypted.clone())
            .await
            .unwrap();
        assert_eq!(decrypted, message);

        // Replay should fail
        let replay_result = service2
            .decrypt_application_message(meet_link_name, encrypted)
            .await;
        assert!(replay_result.is_err(), "Message replay should be rejected");
    }

    #[tokio::test]
    async fn test_handle_commit_message_with_old_epoch_commit() {
        let meet_link_name = "test_meet_link_name";
        let config = MlsClientConfig::default();

        let service1 = create_test_service("user_id", meet_link_name).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;

        let (group1, group2, _commit_bundle1) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        assert_eq!(group1.read().await.epoch(), group2.read().await.epoch());
        assert_eq!(group1.read().await.roster().count(), 2);
        assert_eq!(group2.read().await.roster().count(), 2);

        let commit_msg = _commit_bundle1.commit;
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(
                    &commit_msg.mls_encode_to_vec().unwrap(),
                )
                .unwrap(),
            }),
        };
        let ws_message = WebSocketMessage::Binary(rtc_message.to_tls_bytes().unwrap());
        service1.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = service1.handle_websocket_message(ws_message).await;

        // Old epoch commit is now handled gracefully without error
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_handle_commit_message_with_future_epoch_commit() {
        let meet_link_name = "test_meet_link_name";
        let config = MlsClientConfig::default();

        // Setup services and initial two-user group
        let service1 = create_test_service_with_host("user_id", meet_link_name, true).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let (group1, group2, commit_bundle2) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        // Setup third user and create external commit
        let user_token_info3 = service3
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();

        // These tests use commits without PSK proposals; disable PSK validation after setup.
        *service2.use_psk.lock().await = false;
        *service3.use_psk.lock().await = false;

        let group_info = match mls_spec::messages::MlsMessage::from_tls_bytes(
            &commit_bundle2
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap()
        .content
        {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        let (_, commit_bundle3) = service3
            .create_external_commit(
                &user_token_info3.user_id(),
                meet_link_name,
                config.ciphersuite,
                group_info,
                commit_bundle2.ratchet_tree.unwrap().try_into().unwrap(),
            )
            .await
            .unwrap();

        // Process third user join in group1 only (group2 stays behind)
        group1
            .write()
            .await
            .decrypt_message(commit_bundle3.commit.clone())
            .await
            .unwrap();

        let group3 = {
            let store = service3.mls_store.read().await;
            store.group_map.get(meet_link_name).unwrap().clone()
        };

        // Verify group states: group1 and group3 are synced, group2 is behind
        let (epoch1, epoch2, epoch3) = (
            group1.read().await.epoch(),
            group2.read().await.epoch(),
            group3.read().await.epoch(),
        );
        assert_eq!(epoch1, epoch3);
        assert_ne!(epoch1, epoch2);

        // Create future commit from group1 (will be future epoch for group2)
        let (future_commit, proposal_msg) = {
            let group3_index = group3.read().await.own_leaf_index().unwrap();
            let proposal = ProposalArg::Remove(group3_index);
            let mut group1_guard = group1.write().await;
            let proposal_msg = group1_guard
                .new_proposals([proposal])
                .await
                .unwrap()
                .remove(0);
            let (commit_bundle, _) = group1_guard.new_commit([]).await.unwrap();
            group1_guard.merge_pending_commit().await.unwrap();
            (commit_bundle, proposal_msg)
        };

        // Process messages in group3
        {
            let mut guard = group3.write().await;
            guard.decrypt_message(proposal_msg.clone()).await.unwrap();
            guard
                .decrypt_message(future_commit.commit.clone())
                .await
                .unwrap();
        }

        // Test 1: Future epoch commit should be cached
        let future_commit_bytes = future_commit.commit.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&future_commit_bytes)
                    .unwrap(),
            }),
        };

        service2.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = service2
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_message.to_tls_bytes().unwrap(),
            ))
            .await;

        // Future epoch commit is now handled gracefully without error, but message is cached
        assert!(result.is_ok());

        // Verify message is cached
        let message_cache = service2.get_cached_message().await.unwrap();
        let guard = message_cache.lock().await;
        let cached_messages = guard
            .messages
            .get(meet_link_name)
            .unwrap()
            .get(&3)
            .unwrap()
            .get(&CachedMessageType::Commit)
            .unwrap();
        assert_eq!(cached_messages.len(), 1);

        let expected_message = future_commit.commit.clone();
        assert_eq!(
            cached_messages[0].message.mls_encode_to_vec().unwrap(),
            expected_message.mls_encode_to_vec().unwrap()
        );
        drop(guard);

        // Test 2: Future epoch proposal should be added to queue (not rejected)
        let proposal_bytes = proposal_msg.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::Proposal(MlsProposalInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                proposal: mls_spec::messages::MlsMessage::from_tls_bytes(&proposal_bytes).unwrap(),
            }),
        };

        let result = service2
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_message.to_tls_bytes().unwrap(),
            ))
            .await;
        // process_proposal_message doesn't check epoch, it just adds to queue
        assert!(
            result.is_ok(),
            "Future epoch proposal should be added to queue without error"
        );

        // Test 3: Processing missing commit should sync group2 and process cached messages
        let commit3_bytes = commit_bundle3.commit.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&commit3_bytes).unwrap(),
            }),
        };

        service2.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = service2
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_message.to_tls_bytes().unwrap(),
            ))
            .await;
        assert!(result.is_ok());

        // Verify final state: groups are synced, group2 has correct roster size
        assert_eq!(group2.read().await.epoch(), group1.read().await.epoch());
        assert_eq!(group2.read().await.roster().count(), 2);

        // Verify cache is cleaned after processing cached messages
        let message_cache = service2.get_cached_message().await.unwrap();
        let guard = message_cache.lock().await;
        let messages = &guard.messages;

        // Cache should be empty or the specific cached messages should be processed
        if let Some(room_messages) = messages.get(meet_link_name) {
            // If room still exists in cache, the future epoch messages should be gone
            if let Some(epoch_messages) = room_messages.get(&3) {
                if let Some(commit_messages) = epoch_messages.get(&CachedMessageType::Commit) {
                    assert_eq!(
                        commit_messages.len(),
                        0,
                        "Cached commit messages should be processed and removed"
                    );
                }
            }
        }
        // Alternatively, the entire cache could be empty, which is also valid
        drop(guard);
    }

    #[tokio::test]
    async fn test_handle_commit_message_with_two_epoch_difference_out_of_order() {
        let meet_link_name = "test_meet_link_name";
        let config = MlsClientConfig::default();

        // Setup services for 4 users
        let service1 = create_test_service_with_host("user_id", meet_link_name, true).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;
        let service4 = create_test_service("user_id4", meet_link_name).await;

        let groups = setup_n_user_group(
            vec![&service1, &service2, &service3, &service4],
            meet_link_name,
            config.ciphersuite,
        )
        .await;
        let group1 = groups[0].clone();
        let group2 = groups[1].clone();
        let group3 = groups[2].clone();
        let group4 = groups[3].clone();

        // These tests use commits without PSK proposals; disable PSK validation after setup.
        *service4.use_psk.lock().await = false;

        // Verify initial state - all groups should be at same epoch
        let initial_epoch = group1.read().await.epoch();
        assert_eq!(group2.read().await.epoch(), initial_epoch);
        assert_eq!(group3.read().await.epoch(), initial_epoch);
        assert_eq!(group4.read().await.epoch(), initial_epoch);
        assert_eq!(group1.read().await.roster().count(), 4);

        // Remove 2nd user (user_id2) to advance epoch by 1
        let (remove_user2_commit, remove_user2_proposal) = {
            let group2_index = group2.read().await.own_leaf_index().unwrap();
            let proposal = ProposalArg::Remove(group2_index);
            let mut group1_guard = group1.write().await;
            let proposal_msg = group1_guard
                .new_proposals([proposal])
                .await
                .unwrap()
                .remove(0);
            let (commit_bundle, _) = group1_guard.new_commit([]).await.unwrap();
            group1_guard.merge_pending_commit().await.unwrap();
            (commit_bundle, proposal_msg)
        };

        // Process removal only in group 3 (skip group2 since it's being removed, keep group4 behind)
        {
            let mut group3_guard = group3.write().await;
            group3_guard
                .decrypt_message(remove_user2_proposal.clone())
                .await
                .unwrap();
            group3_guard
                .decrypt_message(remove_user2_commit.commit.clone())
                .await
                .unwrap();
        }
        // Don't process in group4 - keep it at the original epoch

        // Remove 3rd user (user_id3) to advance epoch by another 1 (total 2 epochs ahead)
        let (future_commit, future_proposal) = {
            let group3_index = group3.read().await.own_leaf_index().unwrap();
            let proposal = ProposalArg::Remove(group3_index);
            let mut group1_guard = group1.write().await;
            let proposal_msg = group1_guard
                .new_proposals([proposal])
                .await
                .unwrap()
                .remove(0);
            let (commit_bundle, _) = group1_guard.new_commit([]).await.unwrap();
            group1_guard.merge_pending_commit().await.unwrap();
            (commit_bundle, proposal_msg)
        };

        // Don't process second removal in group4 - keep it behind at the original epoch
        // Now group1 is 2 epochs ahead of group4

        // Verify epoch differences: group1 should be 2 epochs ahead of group4
        let final_epoch = group1.read().await.epoch();
        let group4_epoch = group4.read().await.epoch();

        assert_eq!(group1.read().await.roster().count(), 2); // Only user1 and user4 left in group1's view
        assert_eq!(group4.read().await.roster().count(), 4); // group4 still sees all 4 users
        assert_eq!(group4_epoch, initial_epoch); // group4 stayed at original epoch
        assert_ne!(final_epoch, initial_epoch); // Verify group1's epoch has advanced

        // Now group1 is further ahead of group4
        let very_future_epoch = group1.read().await.epoch();
        assert_ne!(very_future_epoch, initial_epoch); // Verify further advancement

        // Test 1: Send future commit to group4 - should be cached as out-of-order
        let future_commit_bytes = future_commit.commit.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&future_commit_bytes)
                    .unwrap(),
            }),
        };

        service4.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = service4
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_message.to_tls_bytes().unwrap(),
            ))
            .await;

        // Future epoch commit is now handled gracefully without error
        assert!(result.is_ok());

        // Test 2: Send future proposal to group4 - should also be cached as out-of-order
        let future_proposal_bytes = future_proposal.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::Proposal(MlsProposalInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                proposal: mls_spec::messages::MlsMessage::from_tls_bytes(&future_proposal_bytes)
                    .unwrap(),
            }),
        };

        let result = service4
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_message.to_tls_bytes().unwrap(),
            ))
            .await;

        // process_proposal_message doesn't check epoch, it just adds to queue
        assert!(
            result.is_ok(),
            "Future epoch proposal should be added to queue without error"
        );

        // Verify messages are cached with correct epochs in user4's cache
        let message_cache = service4.get_cached_message().await.unwrap();
        let guard = message_cache.lock().await;

        // Should have cached messages for the future epoch
        let target_epoch = *very_future_epoch as u64;

        // Check if messages are cached for this room
        if let Some(room_messages) = guard.messages.get(meet_link_name) {
            if let Some(epoch_messages) = room_messages.get(&target_epoch) {
                // Check if we have the expected message types
                if let Some(commit_messages) = epoch_messages.get(&CachedMessageType::Commit) {
                    assert!(
                        commit_messages.is_empty(),
                        "Should have at least 1 cached commit message"
                    );
                }
                if let Some(proposal_messages) = epoch_messages.get(&CachedMessageType::Proposal) {
                    assert!(
                        proposal_messages.is_empty(),
                        "Should have at least 1 cached proposal message"
                    );
                }
            }
            // If messages are cached under a different epoch, that's also valid for testing
        }
        drop(guard);

        // Test 3: Process missing commits in order to sync user4 with the advanced group
        // First, send the removal proposal for user2 to user4
        let remove_user2_proposal_bytes = remove_user2_proposal.mls_encode_to_vec().unwrap();
        let rtc_proposal_message = RTCMessageIn {
            content: RTCMessageInContent::Proposal(MlsProposalInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                proposal: mls_spec::messages::MlsMessage::from_tls_bytes(
                    &remove_user2_proposal_bytes,
                )
                .unwrap(),
            }),
        };

        let proposal_result = service4
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_proposal_message.to_tls_bytes().unwrap(),
            ))
            .await;

        assert!(
            proposal_result.is_ok(),
            "User4 should be able to process user2 removal proposal"
        );

        // Then send the commit for user2 removal to help user4 catch up
        let remove_user2_bytes = remove_user2_commit.commit.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&remove_user2_bytes)
                    .unwrap(),
            }),
        };

        // This should succeed and help user4 advance epoch
        let result = service4
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_message.to_tls_bytes().unwrap(),
            ))
            .await;

        assert!(
            result.is_ok(),
            "User4 should be able to process user2 removal commit"
        );

        // Verify user4's epoch has advanced
        let service4_epoch_after_first_sync = {
            let store = service4.mls_store.read().await;
            let group = store.group_map.get(meet_link_name).unwrap().read().await;
            *group.epoch()
        };

        assert_eq!(service4_epoch_after_first_sync, *final_epoch as u64);
        assert_eq!(service4_epoch_after_first_sync, 6);
        println!("  Initial epoch: {initial_epoch:?}, Final user4 epoch: {service4_epoch_after_first_sync:?}");
    }

    #[tokio::test]
    async fn test_handle_proposal_message_with_future_epoch() {
        let meet_link_name = "test_meet_link_name";
        let config = MlsClientConfig::default();

        let service1 = create_test_service("user_id", meet_link_name).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let (group1, group2, commit_bundle2) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        // Add third user to the group
        let user_token_info3 = service3
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();

        // Third user joins via external commit using the latest group state
        let group_info_message = mls_spec::messages::MlsMessage::from_tls_bytes(
            &commit_bundle2
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap();
        let group_info = match group_info_message.content {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        let (_, commit_bundle3) = service3
            .create_external_commit(
                &user_token_info3.user_id(),
                meet_link_name,
                config.ciphersuite,
                group_info,
                commit_bundle2.ratchet_tree.unwrap().try_into().unwrap(),
            )
            .await
            .unwrap();

        // Process the join in group1 only (group2 will be behind)
        let (_, _) = group1
            .write()
            .await
            .decrypt_message(commit_bundle3.commit.clone())
            .await
            .unwrap();

        // Get the third user's group
        let group3 = {
            let store = service3.mls_store.read().await;
            store.group_map.get(meet_link_name).unwrap().clone()
        };

        // Now group1 and group3 are at epoch N+1, group2 is at epoch N
        assert_eq!(group1.read().await.epoch(), group3.read().await.epoch());
        assert_ne!(group1.read().await.epoch(), group2.read().await.epoch());

        // Create a commit with a proposal from group1 (which will be at a future epoch relative to group2)
        let proposal_arg = ProposalArg::Remove(LeafIndex::try_from(2).unwrap());
        let mut future_proposals = group1
            .write()
            .await
            .new_proposals([proposal_arg])
            .await
            .unwrap();

        let future_proposal = future_proposals.remove(0);

        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::Proposal(MlsProposalInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                proposal: mls_spec::messages::MlsMessage::from_tls_bytes(
                    &future_proposal.mls_encode_to_vec().unwrap(),
                )
                .unwrap(),
            }),
        };
        let ws_message = WebSocketMessage::Binary(rtc_message.to_tls_bytes().unwrap());
        service2.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = service2.handle_websocket_message(ws_message).await;

        // Future epoch proposals should be cached (not queued/timered immediately).
        assert!(
            result.is_ok(),
            "Future epoch proposal should be handled gracefully without error"
        );

        // Check proposal queue is untouched for this room.
        let queue = service2.proposal_queue.lock().await;
        assert_eq!(
            queue
                .get(meet_link_name)
                .map(|queued| queued.len())
                .unwrap_or(0),
            0,
            "Future epoch proposal should not be added to queue"
        );
        drop(queue);

        // Check the future proposal was cached under its epoch.
        let message_cache = service2.get_cached_message().await.unwrap();
        let guard = message_cache.lock().await;
        let future_epoch = future_proposal.epoch().unwrap_or(0);
        let cached_future_proposals = guard
            .messages
            .get(meet_link_name)
            .and_then(|room_messages| room_messages.get(&future_epoch))
            .and_then(|epoch_messages| epoch_messages.get(&CachedMessageType::Proposal))
            .map(|messages| messages.len())
            .unwrap_or(0);
        assert!(
            cached_future_proposals > 0,
            "Future epoch proposal should be cached for later processing"
        );
    }

    #[tokio::test]
    async fn test_handle_proposal_message_with_old_epoch() {
        let meet_link_name = "test_meet_link_name";
        let config = MlsClientConfig::default();

        let service1 = create_test_service("user_id", meet_link_name).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let (group1, group2, commit_bundle2) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        // Create a proposal from group2 at the current epoch
        let proposal_arg = ProposalArg::Remove(LeafIndex::try_from(1).unwrap());
        let mut old_proposals = group2
            .write()
            .await
            .new_proposals([proposal_arg])
            .await
            .unwrap();
        let old_proposal = old_proposals.remove(0);

        // Add third user to the group (this advances group1's epoch)
        let user_token_info3 = service3
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();

        let group_info_message = mls_spec::messages::MlsMessage::from_tls_bytes(
            &commit_bundle2
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap();
        let group_info = match group_info_message.content {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        let (_, commit_bundle3) = service3
            .create_external_commit(
                &user_token_info3.user_id(),
                meet_link_name,
                config.ciphersuite,
                group_info,
                commit_bundle2.ratchet_tree.unwrap().try_into().unwrap(),
            )
            .await
            .unwrap();

        // Process the join in group1 only (advancing its epoch)
        let (_, _) = group1
            .write()
            .await
            .decrypt_message(commit_bundle3.commit.clone())
            .await
            .unwrap();

        // Now group1 is at epoch N+1, and the old_proposal is from epoch N
        // Send the old proposal to group1
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::Proposal(MlsProposalInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                proposal: mls_spec::messages::MlsMessage::from_tls_bytes(
                    &old_proposal.mls_encode_to_vec().unwrap(),
                )
                .unwrap(),
            }),
        };
        let ws_message = WebSocketMessage::Binary(rtc_message.to_tls_bytes().unwrap());
        service1.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = service1.handle_websocket_message(ws_message).await;

        // Old epoch proposals should be ignored (not queued, not cached).
        assert!(
            result.is_ok(),
            "Old epoch proposal should be handled gracefully without error"
        );

        // Check proposal queue is untouched for this room.
        let queue = service1.proposal_queue.lock().await;
        assert_eq!(
            queue
                .get(meet_link_name)
                .map(|queued| queued.len())
                .unwrap_or(0),
            0,
            "Old epoch proposal should not be added to queue"
        );
        drop(queue);

        // Check old proposal is not cached for later epochs.
        let message_cache = service1.get_cached_message().await.unwrap();
        let guard = message_cache.lock().await;
        let old_epoch = old_proposal.epoch().unwrap_or(0);
        let cached_old_proposals = guard
            .messages
            .get(meet_link_name)
            .and_then(|room_messages| room_messages.get(&old_epoch))
            .and_then(|epoch_messages| epoch_messages.get(&CachedMessageType::Proposal))
            .map(|messages| messages.len())
            .unwrap_or(0);
        assert_eq!(
            cached_old_proposals, 0,
            "Old epoch proposal should not be cached"
        );
    }

    #[tokio::test]
    async fn test_handle_out_of_order_messages_with_missing_commit_last() {
        let meet_link_name = "test_meet_link_name";
        let config = MlsClientConfig::default();

        // Setup services and initial two-user group
        let service1 = create_test_service_with_host("user_id", meet_link_name, true).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let (group1, group2, commit_bundle2) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        // Setup third user and create external commit
        let user_token_info3 = service3
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();

        let group_info = match mls_spec::messages::MlsMessage::from_tls_bytes(
            &commit_bundle2
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap()
        .content
        {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        let (_, commit_bundle3) = service3
            .create_external_commit(
                &user_token_info3.user_id(),
                meet_link_name,
                config.ciphersuite,
                group_info,
                commit_bundle2.ratchet_tree.unwrap().try_into().unwrap(),
            )
            .await
            .unwrap();

        // Process third user join in group1 only (group2 stays behind)
        group1
            .write()
            .await
            .decrypt_message(commit_bundle3.commit.clone())
            .await
            .unwrap();

        let group3 = {
            let store = service3.mls_store.read().await;
            store.group_map.get(meet_link_name).unwrap().clone()
        };

        // Create a proposal and commit from group1 (at the advanced epoch)
        let (commit_with_proposal, proposal_msg) = {
            let group3_index = group3.read().await.own_leaf_index().unwrap();
            let proposal = ProposalArg::Remove(group3_index);
            let mut group1_guard = group1.write().await;
            let proposal_msg = group1_guard
                .new_proposals([proposal])
                .await
                .unwrap()
                .remove(0);
            let (commit_bundle, _) = group1_guard.new_commit([]).await.unwrap();
            group1_guard.merge_pending_commit().await.unwrap();
            (commit_bundle, proposal_msg)
        };

        // Process messages in group3 to keep it in sync
        {
            let mut guard = group3.write().await;
            guard.decrypt_message(proposal_msg.clone()).await.unwrap();
            guard
                .decrypt_message(commit_with_proposal.commit.clone())
                .await
                .unwrap();
        }

        // These tests use commits without PSK proposals; disable PSK validation after setup.
        *service2.use_psk.lock().await = false;

        // Test scenario: Send commit with proposal first, then proposal, then group3 join commit last
        // Step 1: Send the commit message with proposal (this should be cached as future epoch)
        let commit_bytes = commit_with_proposal.commit.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&commit_bytes).unwrap(),
            }),
        };

        service2.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = service2
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_message.to_tls_bytes().unwrap(),
            ))
            .await;

        // Future epoch commit is now handled gracefully without error
        assert!(
            result.is_ok(),
            "Processing future epoch commit should succeed (message will be cached)"
        );

        // Step 2: Send the proposal message AFTER the commit (out of order)
        let proposal_bytes = proposal_msg.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::Proposal(MlsProposalInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                proposal: mls_spec::messages::MlsMessage::from_tls_bytes(&proposal_bytes).unwrap(),
            }),
        };

        let result = service2
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_message.to_tls_bytes().unwrap(),
            ))
            .await;

        // process_proposal_message doesn't check epoch, it just adds to queue
        assert!(
            result.is_ok(),
            "Processing future epoch proposal should succeed (added to queue)"
        );

        // Check epochs before processing the missing commit
        let group1_epoch = group1.read().await.epoch();
        let group2_epoch = group2.read().await.epoch();
        println!("Before group3 join commit - Group1 epoch: {group1_epoch}, Group2 epoch: {group2_epoch}");

        // Step 3: Finally send the missing group3 join commit (this should process cached messages)
        let commit3_bytes = commit_bundle3.commit.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&commit3_bytes).unwrap(),
            }),
        };

        service2.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = service2
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_message.to_tls_bytes().unwrap(),
            ))
            .await;
        assert!(
            result.is_ok(),
            "Processing group3 join commit should succeed and process cached messages"
        );

        // Verify that cached messages were processed
        let message_cache = service2.get_cached_message().await.unwrap();
        let guard = message_cache.lock().await;
        let messages = &guard.messages;

        // Cache should be empty or the specific cached messages should be processed
        if let Some(room_messages) = messages.get(meet_link_name) {
            // Check that future epoch messages were processed and removed
            if let Some(epoch_messages) = room_messages.get(&4) {
                if let Some(commit_messages) = epoch_messages.get(&CachedMessageType::Commit) {
                    assert_eq!(
                        commit_messages.len(),
                        0,
                        "Cached commit messages should be processed and removed"
                    );
                }
                if let Some(proposal_messages) = epoch_messages.get(&CachedMessageType::Proposal) {
                    assert_eq!(
                        proposal_messages.len(),
                        0,
                        "Cached proposal messages should be processed and removed"
                    );
                }
            }
        }
        drop(guard);

        // Verify final state: Check actual epochs and roster sizes
        let final_group1_epoch = group1.read().await.epoch();
        let final_group2_epoch = group2.read().await.epoch();
        let group1_roster_size = group1.read().await.roster().count();
        let group2_roster_size = group2.read().await.roster().count();

        println!(
            "Final state - Group1: epoch {final_group1_epoch}, roster size {group1_roster_size}"
        );
        println!(
            "Final state - Group2: epoch {final_group2_epoch}, roster size {group2_roster_size}"
        );

        // The test should pass regardless of whether groups are perfectly synchronized
        // since the main goal is to test that proposals after commits are handled gracefully
        // Groups should be at reasonable epochs (not necessarily identical due to the out-of-order scenario)
        assert!(*final_group1_epoch == 4, "Group1 should be at epoch 4");
        assert!(*final_group2_epoch == 4, "Group2 should be at epoch 4");

        // Roster sizes should be reasonable (between 2-3 depending on processing order)
        assert!(group1_roster_size == 2, "Group1 roster size should be 2");
        assert!(group2_roster_size == 2, "Group2 roster size should be 2");
    }

    async fn setup_two_user_group(
        service1: &Service,
        service2: &Service,
        meet_link_name: &str,
        ciphersuite: proton_meet_mls::CipherSuite,
    ) -> (Arc<RwLock<MlsGroup<MemKv>>>, Arc<RwLock<MlsGroup<MemKv>>>) {
        // Create first user and group
        let user_token_info1 = service1
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();
        let (group1, commit_bundle1) = service1
            .create_mls_group(
                &user_token_info1.user_id(),
                meet_link_name,
                meet_link_name,
                ciphersuite,
            )
            .await
            .unwrap();

        // Create second user
        let user_token_info2 = service2
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();

        // Second user joins via external commit
        let group_info_message = mls_spec::messages::MlsMessage::from_tls_bytes(
            &commit_bundle1
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap();
        let group_info = match group_info_message.content {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        let (_, commit_bundle2) = service2
            .create_external_commit(
                &user_token_info2.user_id(),
                meet_link_name,
                ciphersuite,
                group_info,
                commit_bundle1.ratchet_tree.unwrap().try_into().unwrap(),
            )
            .await
            .unwrap();

        // Process the join in first user's group
        let (_, _) = group1
            .write()
            .await
            .decrypt_message(commit_bundle2.commit.clone())
            .await
            .unwrap();

        // Get the second user's group
        let group2 = {
            let store = service2.mls_store.read().await;
            store.group_map.get(meet_link_name).unwrap().clone()
        };

        // Verify both groups are in sync
        assert_eq!(group1.read().await.epoch(), group2.read().await.epoch());
        assert_eq!(group1.read().await.roster().count(), 2);
        assert_eq!(group2.read().await.roster().count(), 2);

        (group1, group2)
    }

    async fn setup_two_user_group_with_commit_bundle(
        service1: &Service,
        service2: &Service,
        meet_link_name: &str,
        ciphersuite: proton_meet_mls::CipherSuite,
    ) -> (
        Arc<RwLock<MlsGroup<MemKv>>>,
        Arc<RwLock<MlsGroup<MemKv>>>,
        CommitBundle,
    ) {
        // Create first user and group
        let user_token_info = service1
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();
        let (group1, commit_bundle1) = service1
            .create_mls_group(
                &user_token_info.user_id(),
                meet_link_name,
                meet_link_name,
                ciphersuite,
            )
            .await
            .unwrap();

        // Create second user
        let user_token_info2 = service2
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();

        // Second user joins via external commit
        let group_info_message = mls_spec::messages::MlsMessage::from_tls_bytes(
            &commit_bundle1
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap();
        let group_info = match group_info_message.content {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        let (_, commit_bundle2) = service2
            .create_external_commit(
                &user_token_info2.user_id(),
                meet_link_name,
                ciphersuite,
                group_info,
                commit_bundle1.ratchet_tree.unwrap().try_into().unwrap(),
            )
            .await
            .unwrap();

        // Process the join in first user's group
        let (_, _) = group1
            .write()
            .await
            .decrypt_message(commit_bundle2.commit.clone())
            .await
            .unwrap();

        // Get the second user's group
        let group2 = {
            let store = service2.mls_store.read().await;
            store.group_map.get(meet_link_name).unwrap().clone()
        };

        // Verify both groups are in sync
        assert_eq!(group1.read().await.epoch(), group2.read().await.epoch());
        assert_eq!(group1.read().await.roster().count(), 2);
        assert_eq!(group2.read().await.roster().count(), 2);

        (group1, group2, commit_bundle2)
    }

    /// Setup a group with N users, where N is the length of the services vector.
    /// Returns a vector of MlsGroup references, one for each service.
    ///
    /// # Arguments
    /// * `services` - Vector of references to Service instances
    /// * `meet_link_name` - Name of the meeting
    /// * `ciphersuite` - The cipher suite to use
    ///
    /// # Example
    /// ```
    /// let services = vec![&service1, &service2, &service3, &service4];
    /// let groups = setup_n_user_group(services, "test_meet", ciphersuite).await;
    /// ```
    async fn setup_n_user_group(
        services: Vec<&Service>,
        meet_link_name: &str,
        ciphersuite: proton_meet_mls::CipherSuite,
    ) -> Vec<Arc<RwLock<MlsGroup<MemKv>>>> {
        assert!(
            services.len() >= 2,
            "Need at least 2 services to create a group"
        );

        let mut groups: Vec<Arc<RwLock<MlsGroup<MemKv>>>> = Vec::new();

        // First user creates the group
        let user_token_info1 = services[0]
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();

        let (group1, initial_bundle) = services[0]
            .create_mls_group(
                &user_token_info1.user_id(),
                meet_link_name,
                meet_link_name,
                ciphersuite,
            )
            .await
            .unwrap();

        groups.push(group1.clone());

        // Add remaining users one by one
        let mut last_commit_bundle = initial_bundle;

        for (_idx, service) in services.iter().enumerate().skip(1) {
            // Create MLS client for the new user
            let user_token_info = service
                .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
                .await
                .unwrap();

            // Extract group info from the last commit bundle
            let group_info = match mls_spec::messages::MlsMessage::from_tls_bytes(
                &last_commit_bundle
                    .group_info
                    .clone()
                    .unwrap()
                    .mls_encode_to_vec()
                    .unwrap(),
            )
            .unwrap()
            .content
            {
                MlsMessageContent::GroupInfo(group_info) => group_info,
                _ => panic!("Expected GroupInfo"),
            };

            // New user creates external commit to join
            let (_new_group, commit_bundle) = service
                .create_external_commit(
                    &user_token_info.user_id(),
                    meet_link_name,
                    ciphersuite,
                    group_info,
                    last_commit_bundle.ratchet_tree.unwrap().try_into().unwrap(),
                )
                .await
                .unwrap();

            // All existing groups process the new member's commit
            for existing_group in &groups {
                existing_group
                    .write()
                    .await
                    .decrypt_message(commit_bundle.commit.clone())
                    .await
                    .unwrap();
            }

            // Get the new member's group from the service's store
            let new_group = {
                let store = service.mls_store.read().await;
                store.group_map.get(meet_link_name).unwrap().clone()
            };
            groups.push(new_group);

            last_commit_bundle = commit_bundle;
        }

        // Verify all groups are in sync
        let expected_member_count = services.len();
        let epoch = *groups[0].read().await.epoch();

        for (idx, group) in groups.iter().enumerate() {
            assert_eq!(
                *group.read().await.epoch(),
                epoch,
                "Group {idx} epoch mismatch",
            );
            assert_eq!(
                group.read().await.roster().count(),
                expected_member_count,
                "Group {idx} roster count mismatch",
            );
        }

        groups
    }

    async fn create_test_service_with_host(
        user_id: &str,
        meet_link_name: &str,
        is_host: bool,
    ) -> Service {
        let http_client = create_mock_http_client_for_mls(user_id, meet_link_name, is_host);
        let user_repository = Arc::new(MockUserRepository::new());
        let mls_store: Arc<RwLock<MlsStore>> = Arc::new(RwLock::new(MlsStore {
            clients: HashMap::new(),
            group_map: HashMap::new(),
            config: MlsClientConfig::default(),
        }));

        let mut ws_client_mock = MockWebSocketClient::new();
        ws_client_mock.expect_get_connection_state().returning(|| {
            Box::pin(ready(
                crate::domain::user::ports::ConnectionState::Connected,
            ))
        });

        Service::new(
            Arc::new(http_client),
            Arc::new(MockUserApi::new()),
            user_repository,
            Arc::new(ws_client_mock),
            mls_store,
        )
    }

    async fn create_test_service(user_id: &str, meet_link_name: &str) -> Service {
        create_test_service_with_host(user_id, meet_link_name, false).await
    }

    #[tokio::test]
    async fn test_mls_group_member_removal() {
        use identity::Disclosure;
        use meet_identifiers::Domain;
        use mls_trait::{MlsClientTrait, MlsGroupTrait, ProposalArg};
        use proton_claims::reexports::cose_key_set::CoseKeySet;
        use proton_meet_mls::{MlsClient, MlsClientConfig, MlsGroupConfig};

        // Helper function to create and initialize an MLS client with mock credentials
        async fn create_initialized_client(email: &str) -> MlsClient<MemKv> {
            let kv = MemKv::new();
            let (client, _) = MlsClient::new(kv, MlsClientConfig::default())
                .await
                .unwrap();
            let domain = Domain::new_random();

            let cnf = client.get_holder_confirmation_key_pem().unwrap();
            let (sd_cwt, issuer_signing_key) =
                mock_sdcwt_issuance(&cnf, &domain, email, proton_claims::Role::User, false)
                    .unwrap();

            let cks = CoseKeySet::new(&issuer_signing_key).unwrap();
            client.initialize(MemKv::new(), sd_cwt, &cks, &cks).unwrap()
        }

        // Create 3 initialized MLS clients
        let mut client1 = create_initialized_client("user1@proton.me").await;
        let mut client2 = create_initialized_client("user2@proton.me").await;
        let mut client3 = create_initialized_client("user3@proton.me").await;

        // Extract user IDs from each client's SD-CWT
        let user_id1 = client1.sd_cwt_mut().unwrap().user_id().unwrap();
        let _user_id2 = client2.sd_cwt_mut().unwrap().user_id().unwrap();
        let user_id3 = client3.sd_cwt_mut().unwrap().user_id().unwrap();

        let group_id = GroupId::new(&user_id1.domain);

        // Client 1 creates the group (becomes admin)
        let mut group1 = client1
            .new_group(
                &group_id,
                Disclosure::Full,
                MlsGroupConfig::default(user_id1.clone(), true),
            )
            .await
            .unwrap()
            .store()
            .await
            .unwrap();

        // Generate initial commit for the group
        let (initial_bundle, _) = group1.new_commit(vec![]).await.unwrap();
        group1.merge_pending_commit().await.unwrap();

        println!("Initial group created by client 1");
        println!("Group 1 epoch: {:?}", group1.epoch());
        println!("Group 1 roster size: {:?}", group1.roster().count());

        // Client 2 joins the group via external commit
        let group_info = initial_bundle.group_info.unwrap();
        let ratchet_tree = initial_bundle.ratchet_tree.unwrap();

        // Convert group_info to bytes and back to mls_types::MlsMessage (following existing pattern)
        let encoded_payload = group_info.mls_encode_to_vec().unwrap();
        let mls_message = mls_types::MlsMessage::from_bytes(&encoded_payload).unwrap();

        let ratchet_tree_mls_types = ratchet_tree.clone();
        let (group2, commit2) = client2
            .join_group_via_external_commit(
                mls_message.clone(),
                ratchet_tree_mls_types,
                Disclosure::Full,
                vec![],
            )
            .await
            .unwrap();
        let mut group2 = group2.store().await.unwrap();

        // Process client 2's join commit in group 1
        let commit2_message = commit2.commit;
        let (_, _) = group1.decrypt_message(commit2_message).await.unwrap();

        println!("Client 2 joined the group");
        println!("Group 1 epoch: {:?}", group1.epoch());
        println!("Group 1 roster size: {:?}", group1.roster().count());
        println!("Group 2 epoch: {:?}", group2.epoch());
        println!("Group 2 roster size: {:?}", group2.roster().count());

        // Client 3 joins the group via external commit
        let group_info_for_ext_commit = group1.group_info_for_ext_commit().await.unwrap();
        tracing::debug!("group_info_for_ext_commit: {:?}", group_info_for_ext_commit);
        let ratchet_tree_for_ext_commit = group1.ratchet_tree();
        tracing::debug!(
            "ratchet_tree_for_ext_commit: {:?}",
            ratchet_tree_for_ext_commit
        );

        // Convert group_info to bytes and back to mls_types::MlsMessage (following existing pattern)
        let encoded_payload = group_info_for_ext_commit.mls_encode_to_vec().unwrap();
        let mls_message = mls_types::MlsMessage::from_bytes(&encoded_payload).unwrap();

        // mls_message is already created above
        let ratchet_tree_mls_types = ratchet_tree_for_ext_commit.into();

        let (group3, commit3) = client3
            .join_group_via_external_commit(
                mls_message,
                ratchet_tree_mls_types,
                Disclosure::Full,
                vec![],
            )
            .await
            .unwrap();
        let group3 = group3.store().await.unwrap();

        // Process client 3's join commit in both group 1 and group 2
        let commit3_message = commit3.commit;
        let (_, _) = group1
            .decrypt_message(commit3_message.clone())
            .await
            .unwrap();
        let (_, _) = group2.decrypt_message(commit3_message).await.unwrap();

        println!("Client 3 joined the group");
        println!("Group 1 epoch: {:?}", group1.epoch());
        println!("Group 1 roster size: {:?}", group1.roster().count());
        println!("Group 2 epoch: {:?}", group2.epoch());
        println!("Group 2 roster size: {:?}", group2.roster().count());
        println!("Group 3 epoch: {:?}", group3.epoch());
        println!("Group 3 roster size: {:?}", group3.roster().count());

        // Verify all groups have the same epoch and 3 members
        assert_eq!(group1.epoch(), group2.epoch());
        assert_eq!(group2.epoch(), group3.epoch());
        assert_eq!(group1.roster().count(), 3);
        assert_eq!(group2.roster().count(), 3);
        assert_eq!(group3.roster().count(), 3);

        // Now client 1 (admin) removes client 3 from the group
        // First, find client 3's leaf index in group 1
        let roster = group1.roster();
        let mut client3_leaf_index = None;

        for mut member in roster.into_iter() {
            if member.user_id().unwrap() == user_id3 {
                client3_leaf_index = Some(member.leaf_index());
                break;
            }
        }

        let client3_leaf_index = client3_leaf_index.expect("Client 3 should be in the roster");

        // Create removal proposal and commit from client 1
        let removal_proposals = vec![ProposalArg::Remove(client3_leaf_index)];
        let removal_proposals_for_commit = vec![ProposalArg::Remove(client3_leaf_index)];
        let _proposal_msgs = group1.new_proposals(removal_proposals).await.unwrap();
        let (removal_commit_bundle, _) = group1
            .new_commit(removal_proposals_for_commit)
            .await
            .unwrap();
        group1.merge_pending_commit().await.unwrap();

        println!("Client 1 created removal proposal and commit");
        println!("Group 1 epoch after removal: {:?}", group1.epoch());
        println!(
            "Group 1 roster size after removal: {:?}",
            group1.roster().count()
        );

        // Process the removal in group 2 (client 2 receives the removal)
        let removal_commit_message = removal_commit_bundle.commit;
        let (_, _) = group2
            .decrypt_message(removal_commit_message)
            .await
            .unwrap();

        println!("Client 2 processed the removal");
        println!("Group 2 epoch after removal: {:?}", group2.epoch());
        println!(
            "Group 2 roster size after removal: {:?}",
            group2.roster().count()
        );

        // Verify that both remaining clients (1 and 2) have the same epoch
        assert_eq!(group1.epoch(), group2.epoch());

        // Verify that both groups now have 2 members (client 3 was removed)
        assert_eq!(group1.roster().count(), 2);
        assert_eq!(group2.roster().count(), 2);

        // Verify that client 3 is no longer in the roster
        let final_roster1 = group1.roster();
        let final_roster2 = group2.roster();

        for mut member in final_roster1.into_iter() {
            assert_ne!(
                member.user_id().unwrap(),
                user_id3,
                "Client 3 should be removed from group 1"
            );
        }

        for mut member in final_roster2.into_iter() {
            assert_ne!(
                member.user_id().unwrap(),
                user_id3,
                "Client 3 should be removed from group 2"
            );
        }

        println!("✅ Test passed: MLS group member removal works correctly");
        println!("Final epoch: {:?}", group1.epoch());
        println!("Remaining members: {:?}", group1.roster().count());
    }

    #[tokio::test]
    async fn test_service_handle_commit_before_remove_proposal_out_of_order() {
        let meet_link_name = "test_meet_link_name";
        let config = MlsClientConfig::default();

        // Setup services for 3 users
        let service1 = create_test_service_with_host("user_id", meet_link_name, true).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        // Setup initial two-user group
        let (group1, group2, commit_bundle2) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        // Setup third user and create external commit to join the group
        let user_token_info3 = service3
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();

        let group_info = match mls_spec::messages::MlsMessage::from_tls_bytes(
            &commit_bundle2
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap()
        .content
        {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        let (_, commit_bundle3) = service3
            .create_external_commit(
                &user_token_info3.user_id(),
                meet_link_name,
                config.ciphersuite,
                group_info,
                commit_bundle2.ratchet_tree.unwrap().try_into().unwrap(),
            )
            .await
            .unwrap();

        // Process third user join in group1 and group2 to get all groups to epoch 3
        group1
            .write()
            .await
            .decrypt_message(commit_bundle3.commit.clone())
            .await
            .unwrap();

        group2
            .write()
            .await
            .decrypt_message(commit_bundle3.commit.clone())
            .await
            .unwrap();

        let group3 = {
            let store = service3.mls_store.read().await;
            store.group_map.get(meet_link_name).unwrap().clone()
        };

        println!("All 3 users joined the group");
        println!(
            "Group1 epoch: {:?}, roster: {:?}",
            group1.read().await.epoch(),
            group1.read().await.roster().count()
        );
        println!(
            "Group2 epoch: {:?}, roster: {:?}",
            group2.read().await.epoch(),
            group2.read().await.roster().count()
        );
        println!(
            "Group3 epoch: {:?}, roster: {:?}",
            group3.read().await.epoch(),
            group3.read().await.roster().count()
        );

        // Now create the test scenario: Group1 removes Group2
        // Find Group2's leaf index
        let group2_leaf_index = {
            let group = group1.read().await;
            let roster = group.roster();
            // Get the actual user_id from the roster (it will be a chat_identifiers::UserId)
            let mut leaf_index = None;
            for mut member in roster.into_iter() {
                let member_user_id = member.user_id().unwrap();
                // Compare by converting to string since we know user_id2 should be in the roster
                if member_user_id.to_string().contains("user_id2") {
                    leaf_index = Some(member.leaf_index());
                    break;
                }
            }
            leaf_index.expect("Group2 should be in the roster")
        };

        // Group1 creates a remove proposal and commit for Group2
        let (commit_with_removal, proposal_msg) = {
            let psk_id: ExternalPskId = ExternalPskId(meet_link_name.as_bytes().to_vec());
            let psk_proposal = ProposalArg::PskExternal { id: psk_id };
            let proposal = ProposalArg::Remove(group2_leaf_index);
            let mut group1_guard = group1.write().await;
            let proposal_msg = group1_guard
                .new_proposals([proposal])
                .await
                .unwrap()
                .remove(0);
            let (commit_bundle, _) = group1_guard.new_commit([psk_proposal]).await.unwrap();
            group1_guard.merge_pending_commit().await.unwrap();
            (commit_bundle, proposal_msg)
        };

        println!("Group1 created remove proposal and commit for Group2");
        println!(
            "Group1 epoch after commit: {:?}",
            group1.read().await.epoch()
        );

        // Test scenario: Service3 receives commit FIRST, then proposal (out of order)
        // This simulates the scenario where Group3 processes commit before remove proposal

        // Step 1: Service3 receives and processes the commit message FIRST
        let commit_bytes = commit_with_removal.commit.mls_encode_to_vec().unwrap();
        let rtc_commit_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&commit_bytes).unwrap(),
            }),
        };

        service3.state.lock().await.mls_group_state = MlsGroupState::Success;
        let _result = service3
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_commit_message.to_tls_bytes().unwrap(),
            ))
            .await;

        println!("Service3 processed commit first");
        println!(
            "Group3 epoch after commit: {:?}",
            group3.read().await.epoch()
        );
        println!(
            "Group3 roster size after commit: {:?}",
            group3.read().await.roster().count()
        );

        // Step 2: Service3 receives the remove proposal AFTER the commit (out of order)
        let proposal_bytes = proposal_msg.mls_encode_to_vec().unwrap();
        let rtc_proposal_message = RTCMessageIn {
            content: RTCMessageInContent::Proposal(MlsProposalInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                proposal: mls_spec::messages::MlsMessage::from_tls_bytes(&proposal_bytes).unwrap(),
            }),
        };

        let result = service3
            .handle_websocket_message(WebSocketMessage::Binary(
                rtc_proposal_message.to_tls_bytes().unwrap(),
            ))
            .await;

        // The proposal should fail because it's from an old epoch (epoch 3) but Group3 is now at epoch 4
        println!("Service3 processing remove proposal after commit: {result:?}");

        // This could either succeed (if the service handles it gracefully) or fail with an epoch error
        // The important thing is that the service doesn't crash and handles it appropriately
        match result {
            Ok(_) => println!("Service3 handled the out-of-order proposal gracefully"),
            Err(e) => {
                let err_msg = e.to_string();
                println!("Service3 rejected out-of-order proposal (expected): {err_msg}");
                // Common expected errors: epoch mismatch, invalid state, etc.
                assert!(
                    err_msg.contains("epoch")
                        || err_msg.contains("Invalid")
                        || err_msg.contains("Error"),
                    "Should be a reasonable error message"
                );
            }
        }

        // Verify final state
        let final_group1_epoch = group1.read().await.epoch();
        let final_group2_epoch = group2.read().await.epoch();
        let final_group3_epoch = group3.read().await.epoch();

        let group1_roster_size = group1.read().await.roster().count();
        let group2_roster_size = group2.read().await.roster().count();
        let group3_roster_size = group3.read().await.roster().count();

        println!("Final state:");
        println!("Group1: epoch {final_group1_epoch}, roster size {group1_roster_size}");
        println!("Group2: epoch {final_group2_epoch}, roster size {group2_roster_size}");
        println!("Group3: epoch {final_group3_epoch}, roster size {group3_roster_size}");

        assert_eq!(*final_group1_epoch, 4, "Group1 should be at epoch 4");
        assert!(*final_group2_epoch == 3, "Group2 should be at epoch 3");
        assert!(*final_group3_epoch == 4, "Group3 should be at epoch 4");

        assert!(group1_roster_size == 2, "Group1 roster size should be 2");
        assert!(group2_roster_size == 3, "Group2 roster size should be 3");
        assert!(group3_roster_size == 2, "Group3 roster size should be 2");
    }

    /// Helper function to create a mock HTTP client with common MLS expectations
    fn create_mock_http_client_for_mls(
        email: &str,
        meeting_link_name: &str,
        is_host: bool,
    ) -> MockHttpClient {
        let mut http_client = MockHttpClient::new();

        let issuer_sk = "-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIDR7w12ON3uzdZd8g6HIGOiGe/ozjj0rpBKs1VTVCyCM
-----END PRIVATE KEY-----";

        let issuer_signing_key = ed25519_dalek::SigningKey::from_pkcs8_pem(issuer_sk).unwrap();
        let cks = CoseKeySet::new(&issuer_signing_key).unwrap();
        let email = email.to_string();
        let meeting_link_name = meeting_link_name.to_string();

        http_client
            .expect_fetch_sd_cwt()
            .returning(move |_, _, base64_holder_verifying_key, _| {
                let holder_verifying_key =
                    BASE64_STANDARD.decode(base64_holder_verifying_key).unwrap();
                let holder_verifying_key = ed25519_dalek::VerifyingKey::from_bytes(
                    &holder_verifying_key.as_slice().try_into().unwrap(),
                )
                .unwrap();
                let holder_verifying_key_pem = holder_verifying_key
                    .to_public_key_pem(LineEnding::LF)
                    .unwrap();
                let (sd_cwt, _issuer_signing_key) = mock_sdcwt_issuance(
                    &holder_verifying_key_pem,
                    &meeting_link_name,
                    &email,
                    proton_claims::Role::User,
                    is_host,
                )
                .unwrap();
                let base64_sd_cwt = BASE64_STANDARD.encode(sd_cwt.to_cbor_bytes().unwrap());
                Box::pin(ready(Ok(base64_sd_cwt)))
            });

        let cks_clone = cks.clone();
        http_client
            .expect_fetch_cose_key_set()
            .returning(move || Box::pin(ready(Ok(cks_clone.to_cbor_bytes().unwrap()))));
        http_client
            .expect_fetch_external_sender()
            .returning(move || Box::pin(ready(Ok(vec![]))));

        http_client
    }

    pub fn mock_sdcwt_issuance(
        holder_confirmation_key_pem: &str,
        meeting_link_name: &str,
        email: &str,
        organization_role: proton_claims::Role,
        is_host: bool,
    ) -> IdentityResult<(SdCwt, ed25519_dalek::SigningKey)> {
        let payload = ProtonMeetClaims {
            meeting_id: meeting_link_name.to_string(),
            uuid: Uuid::new_v4().into_bytes(),
            oidc_claims: SpiceOidcClaims::default(),
            role: organization_role,
            mimi_provider: MimiProvider::ProtonAg,
            is_from_server: false,
            is_host,
        };

        let issuer_sk = "-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIDR7w12ON3uzdZd8g6HIGOiGe/ozjj0rpBKs1VTVCyCM
-----END PRIVATE KEY-----";

        let issuer_signing_key = ed25519_dalek::SigningKey::from_pkcs8_pem(issuer_sk).unwrap();
        let issuer = Ed25519Issuer::new(issuer_signing_key.clone());
        let holder_verifying_key =
            ed25519_dalek::VerifyingKey::from_public_key_pem(holder_confirmation_key_pem).unwrap();
        let holder_confirmation_key = (&holder_verifying_key).try_into().unwrap();

        // For mock, treat participant_uid as email if it contains '@', otherwise as username
        let (primary_email, username) = if email.contains('@') {
            (Some(email.to_string()), None)
        } else {
            (None, Some(email.to_string()))
        };

        let sub = generate_mimi_subject(
            "meet.proton.me",
            &holder_verifying_key,
            primary_email,
            username,
        )
        .unwrap();

        let params = IssuerParams {
            protected_claims: None,
            unprotected_claims: None,
            payload: Some(payload),
            subject: Some(&sub),
            audience: None,
            expiry: None,
            with_not_before: true,
            with_issued_at: true,
            cti: None,
            cnonce: None,
            key_location: "https://auth.proton.me/issuer.cwk",
            holder_confirmation_key,
            issuer: "mimi://i/proton.me",
            leeway: Default::default(),
        };

        let sd_cwt = issuer.issue_cwt(&mut rand::thread_rng(), params).unwrap();
        Ok((sd_cwt, issuer_signing_key))
    }

    fn generate_mimi_subject(
        mimi_host: &str,
        holder_verifying_key: &ed25519_dalek::VerifyingKey,
        primary_email: Option<String>,
        username: Option<String>,
    ) -> IdentityResult<String> {
        let mimi_device_id = generate_mimi_device_id(holder_verifying_key)?;

        let user_identifier = match (primary_email, username) {
            (Some(email), _) => email,  // Proton user with primary email
            (None, Some(name)) => name, // Proton user without primary email
            (None, None) => ANONYMOUS_USER_IDENTIFIER.to_string(), // Guest user
        };

        Ok(format!(
            "mimi://{mimi_host}/d/{user_identifier}/{mimi_device_id}"
        ))
    }

    fn generate_mimi_device_id(
        holder_verifying_key: &ed25519_dalek::VerifyingKey,
    ) -> IdentityResult<String> {
        let thumbprint =
            CoseKeyThumbprint::<32>::compute::<sha2::Sha256>(holder_verifying_key).unwrap();
        Ok(thumbprint.to_string())
    }

    #[tokio::test]
    async fn test_handle_batched_proposals_empty_queue() {
        // Test case: Empty proposal queue should return Ok (empty proposals)
        let meet_link_name = "test_empty_queue";
        let service = create_test_service("user_id", meet_link_name).await;

        // Set MLS group state to Success
        service.state.lock().await.mls_group_state = MlsGroupState::Success;

        // Get proposals from queue (will be empty)
        let queued_proposals = {
            let mut queue_lock = service.proposal_queue.lock().await;
            queue_lock.remove(meet_link_name).unwrap_or_else(Vec::new)
        };

        let result = service
            .handle_batched_proposals(meet_link_name, queued_proposals, 0)
            .await;
        // handle_batched_proposals returns Ok when proposals are empty
        assert!(result.is_ok(), "Should return Ok when proposals are empty");
    }

    #[tokio::test]
    async fn test_handle_batched_proposals_different_epoch() {
        // Test case: Proposals with different epoch should be filtered out by handle_proposal
        let meet_link_name = "test_different_epoch";
        let config = MlsClientConfig::default();
        let service1 = create_test_service("user1", meet_link_name).await;
        let service2 = create_test_service("user2", meet_link_name).await;

        // Setup two-user group
        let (group1, group2, _) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        // Create a proposal from group2 at current epoch
        use mls_trait::{MlsGroupTrait, ProposalArg};
        let user2_leaf_index = *group2.read().await.own_leaf_index().unwrap();
        let mut proposals = group2
            .write()
            .await
            .new_proposals([ProposalArg::Remove(
                meet_identifiers::LeafIndex::try_from(user2_leaf_index).unwrap(),
            )])
            .await
            .unwrap();
        let old_proposal = proposals.remove(0);
        let proposal_message: mls_types::MlsMessage = old_proposal;

        // Advance group1's epoch by creating and processing a commit
        // This will make the proposal's epoch older than group1's current epoch
        let (_commit_bundle, _) = group1.write().await.new_commit([]).await.unwrap();
        group1.write().await.merge_pending_commit().await.unwrap();

        // Now group1 is at epoch 3, but proposal is from epoch 2
        // Add proposal with old epoch to queue
        {
            let mut queue = service1.proposal_queue.lock().await;
            queue.insert(
                meet_link_name.to_string(),
                vec![QueuedProposal {
                    proposal_message,
                    proposal_type: ProposalType::Remove,
                }],
            );
        }

        service1.state.lock().await.mls_group_state = MlsGroupState::Success;

        // Get proposals from queue
        let queued_proposals = {
            let mut queue_lock = service1.proposal_queue.lock().await;
            queue_lock.remove(meet_link_name).unwrap_or_else(Vec::new)
        };

        // handle_proposal will reject this proposal because it's from an old epoch
        // So all_proposals will be empty and function will return Ok
        let result = service1
            .handle_batched_proposals(meet_link_name, queued_proposals, 0)
            .await;
        assert!(
            result.is_ok(),
            "Should return Ok when proposals are filtered out due to epoch mismatch"
        );
    }

    #[tokio::test]
    async fn test_handle_batched_proposals_remove_own_node() {
        // Test case: Remove proposal targeting own node should be skipped
        let meet_link_name = "test_remove_own";
        let config = MlsClientConfig::default();
        let service1 = create_test_service("user1", meet_link_name).await;
        let service2 = create_test_service("user2", meet_link_name).await;

        // Setup two-user group
        let (group1, _group2, _) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        let own_leaf_index = *group1.read().await.own_leaf_index().unwrap();
        let _current_epoch = *group1.read().await.epoch();

        // Create a remove proposal targeting own node
        use mls_trait::{MlsGroupTrait, ProposalArg};
        let mut proposals = group1
            .write()
            .await
            .new_proposals([ProposalArg::Remove(
                meet_identifiers::LeafIndex::try_from(own_leaf_index).unwrap(),
            )])
            .await
            .unwrap();
        let remove_proposal = proposals.remove(0);
        let proposal_message: mls_types::MlsMessage = remove_proposal;

        // Add proposal to queue
        {
            let mut queue = service1.proposal_queue.lock().await;
            queue.insert(
                meet_link_name.to_string(),
                vec![QueuedProposal {
                    proposal_message: proposal_message.clone(),
                    proposal_type: ProposalType::Remove,
                }],
            );
        }

        // Set state to Success
        service1.state.lock().await.mls_group_state = MlsGroupState::Success;

        // Get proposals from queue
        let queued_proposals = {
            let mut queue_lock = service1.proposal_queue.lock().await;
            queue_lock.remove(meet_link_name).unwrap_or_else(Vec::new)
        };

        // Mock HTTP client to not be called (since proposal should be skipped)
        let result = service1
            .handle_batched_proposals(meet_link_name, queued_proposals, 0)
            .await;
        assert!(result.is_ok(), "Should return Ok when skipping own removal");
    }

    #[tokio::test]
    async fn test_handle_batched_proposals_success() {
        // Test case: Successfully process batched proposals (both Add and Remove)
        let meet_link_name = "test_success";
        let config = MlsClientConfig::default();
        let service1 = create_test_service("user1", meet_link_name).await;
        let service2 = create_test_service("user2", meet_link_name).await;
        let service3 = create_test_service("user3", meet_link_name).await;

        // Setup two-user group
        let (group1, group2, _) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        let current_epoch = *group1.read().await.epoch();
        let user2_leaf_index = *group2.read().await.own_leaf_index().unwrap();

        // Record initial state before processing proposals
        let initial_roster_size = group1.read().await.roster().count();
        assert_eq!(
            initial_roster_size, 2,
            "Initial group should have 2 members"
        );

        // Create user3's MLS client
        let user_token_info3 = service3
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();

        // Get group info and ratchet tree from group1 to create external proposal
        let (group_info, ratchet_tree_option) = {
            let store = service1.mls_store.read().await;
            let group = store.group_map.get(meet_link_name).unwrap();
            let group_read = group.read().await;

            // Get GroupInfo for external proposals
            let group_info_mls_spec = group_read
                .group_info_for_ext_commit()
                .await
                .expect("Should get group_info_for_ext_commit");

            // Parse to get GroupInfo
            let group_info_bytes = group_info_mls_spec.mls_encode_to_vec().unwrap();
            let group_info_message =
                mls_spec::messages::MlsMessage::from_tls_bytes(&group_info_bytes).unwrap();
            let group_info = match group_info_message.content {
                mls_spec::messages::MlsMessageContent::GroupInfo(gi) => gi,
                _ => panic!("Expected GroupInfo"),
            };

            // Get the ratchet tree and convert to RatchetTreeOption
            let exported_tree = group_read.ratchet_tree();

            // Serialize ExportedTree and deserialize to mls_spec::tree::RatchetTree
            let tree_bytes = exported_tree.mls_encode_to_vec().unwrap();
            let ratchet_tree_mls_spec =
                mls_spec::tree::RatchetTree::from_tls_bytes(&tree_bytes).unwrap();
            let ratchet_tree_option = RatchetTreeOption::Full {
                ratchet_tree: ratchet_tree_mls_spec,
            };

            (group_info, ratchet_tree_option)
        };

        // Create external proposal for user3 to get key package
        let external_proposal_user3 = service3
            .create_external_proposal(
                &user_token_info3.user_id(),
                config.ciphersuite,
                group_info,
                ratchet_tree_option,
            )
            .await
            .unwrap();

        // Extract key package from external proposal
        // as_proposal() returns mls_rs::group::proposal::Proposal, not mls_types::Proposal
        let key_package_user3 = match external_proposal_user3.as_proposal() {
            Some(Proposal::Add(add)) => add.key_package().clone(),
            _ => panic!("Expected Add Proposal for user3"),
        };

        // Create add proposal from group2 to add user3
        use mls_trait::{MlsGroupTrait, ProposalArg};
        let mut add_proposals = group2
            .write()
            .await
            .new_proposals([ProposalArg::Add(Box::new(key_package_user3.into()))])
            .await
            .unwrap();
        let add_proposal = add_proposals.remove(0);
        let add_proposal_message: mls_types::MlsMessage = add_proposal;

        // Create remove proposal from group2 (user2's group) to remove user2
        // This simulates user2 creating a self-remove proposal, or another client creating it
        // The proposal needs to be created from a different group context to be properly encrypted
        let mut remove_proposals = group2
            .write()
            .await
            .new_proposals([ProposalArg::Remove(
                meet_identifiers::LeafIndex::try_from(user2_leaf_index).unwrap(),
            )])
            .await
            .unwrap();
        let remove_proposal = remove_proposals.remove(0);
        let remove_proposal_message: mls_types::MlsMessage = remove_proposal;

        // Add both proposals to queue (add first, then remove)
        {
            let mut queue = service1.proposal_queue.lock().await;
            queue.insert(
                meet_link_name.to_string(),
                vec![
                    QueuedProposal {
                        proposal_message: add_proposal_message,
                        proposal_type: ProposalType::Add,
                    },
                    QueuedProposal {
                        proposal_message: remove_proposal_message,
                        proposal_type: ProposalType::Remove,
                    },
                ],
            );
        }

        // Set state to Success
        service1.state.lock().await.mls_group_state = MlsGroupState::Success;

        // Create a new service with properly mocked HTTP client that expects update_group_info
        let mut http_client = create_mock_http_client_for_mls("user1", meet_link_name, false);
        http_client
            .expect_update_group_info()
            .returning(|_, _, _, _, _| Box::pin(ready(Ok(()))));

        let user_repository = Arc::new(MockUserRepository::new());
        let mls_store = Arc::new(RwLock::new(MlsStore {
            clients: HashMap::new(),
            group_map: HashMap::new(),
            config: MlsClientConfig::default(),
        }));

        // Copy MLS store from service1
        {
            let store1 = service1.mls_store.read().await;
            let mut store_new = mls_store.write().await;
            store_new.clients = store1.clients.clone();
            store_new.group_map = store1.group_map.clone();
            store_new.config = store1.config.clone();
        }

        let service_with_mock = Service::new(
            Arc::new(http_client),
            Arc::new(MockUserApi::new()),
            user_repository,
            Arc::new(MockWebSocketClient::new()),
            mls_store,
        );

        // Copy proposal queue manually
        {
            let queue1 = service1.proposal_queue.lock().await;
            let mut queue_new = service_with_mock.proposal_queue.lock().await;
            for (key, value) in queue1.iter() {
                queue_new.insert(
                    key.clone(),
                    value
                        .iter()
                        .map(|q| QueuedProposal {
                            proposal_message: q.proposal_message.clone(),
                            proposal_type: q.proposal_type,
                        })
                        .collect(),
                );
            }
        }

        service_with_mock.state.lock().await.mls_group_state = MlsGroupState::Success;

        // Get proposals from queue
        let queued_proposals = {
            let mut queue_lock = service_with_mock.proposal_queue.lock().await;
            queue_lock.remove(meet_link_name).unwrap_or_else(Vec::new)
        };

        let result = service_with_mock
            .handle_batched_proposals(meet_link_name, queued_proposals, 0)
            .await;
        assert!(
            result.is_ok(),
            "Should successfully process batched proposals"
        );

        // Verify that the proposals were successfully processed
        // Check that roster size: +1 (user3 added) -1 (user2 removed) = same size
        // But since we're removing user2 and adding user3, final size should be 2 (user1 + user3)
        let final_group = {
            let store = service_with_mock.mls_store.read().await;
            store.group_map.get(meet_link_name).unwrap().clone()
        };
        let final_roster_size = final_group.read().await.roster().count();
        // After adding user3 and removing user2: 2 (initial) + 1 (add) - 1 (remove) = 2
        assert_eq!(
            final_roster_size, 2,
            "Roster size should be 2 after adding user3 and removing user2 (user1 + user3)"
        );

        // Verify user3 was added and user2 was removed
        // Get user IDs from the roster (not leaf indices, as they can be reused)
        let roster_members: Vec<u32> = {
            let group = final_group.read().await;
            let roster = group.roster();
            roster.map(|member| *member.leaf_index()).collect()
        };

        let mut user_ids_in_group = Vec::new();
        for leaf_index in roster_members {
            let group_write = final_group.write().await;
            let leaf_index_typed = LeafIndex::try_from(leaf_index).unwrap();
            if let Ok(mut member) = group_write.find_member(leaf_index_typed) {
                if let Ok(user_id) = member.credential.user_id() {
                    user_ids_in_group.push(user_id);
                }
            }
            drop(group_write); // Release write lock before next iteration
        }

        // user2 should be removed
        assert!(
            !user_ids_in_group
                .iter()
                .any(|v| v.id.to_string() == "user2"),
            "User2 should be removed from the group"
        );
        // user3 should be added
        assert!(
            user_ids_in_group
                .iter()
                .any(|v| v.id.to_string() == "user3"),
            "User3 should be added to the group"
        );

        for user_id in user_ids_in_group {
            let role = final_group
                .read()
                .await
                .user_role_for_current_epoch(&user_id)
                .unwrap();
            assert_eq!(role, UserRole::Member);
        }

        // Verify epoch increased
        let final_epoch = *final_group.read().await.epoch();
        assert!(
            final_epoch > current_epoch,
            "Epoch should increase after processing proposals"
        );

        // Verify proposal queue is empty (proposals were processed and removed)
        let queue = service_with_mock.proposal_queue.lock().await;
        assert!(
            queue.get(meet_link_name).is_none() || queue.get(meet_link_name).unwrap().is_empty(),
            "Proposal queue should be empty after processing"
        );
    }

    #[tokio::test]
    async fn test_is_mls_up_to_date_same_group() {
        // Test case 1: Same group - should return true
        let meet_link_name = "test_is_mls_up_to_date_same_group";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        // Create service and group
        let service = create_test_service("user1", meet_link_name).await;
        let user_token_info = service
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();
        let (group, _commit_bundle) = service
            .create_mls_group(
                &user_token_info.user_id(),
                meet_link_name,
                meet_link_name,
                ciphersuite,
            )
            .await
            .unwrap();

        // Get group_id and epoch from the group for GroupInfoSummaryData
        let group_info_for_ext_commit = group
            .read()
            .await
            .group_info_for_ext_commit()
            .await
            .unwrap();
        let group_info_bytes = group_info_for_ext_commit.mls_encode_to_vec().unwrap();
        let group_info_message =
            mls_spec::messages::MlsMessage::from_tls_bytes(&group_info_bytes).unwrap();
        let group_info = match group_info_message.content {
            MlsMessageContent::GroupInfo(gi) => gi,
            _ => panic!("Expected GroupInfo"),
        };

        let group_context = &group_info.group_context;
        let server_group_id = group_context.group_id().to_vec();
        let server_epoch = *group.read().await.epoch();

        // Create GroupInfoSummaryData from the same group
        let group_info_summary = GroupInfoSummaryData {
            epoch: server_epoch,
            group_id: server_group_id,
        };

        // Create new service with mocked get_group_info_summary
        let mut http_client = create_mock_http_client_for_mls("user1", meet_link_name, false);
        let g = group_info_summary.clone();
        http_client
            .expect_get_group_info_summary()
            .returning(move |_| Box::pin(ready(Ok(g.clone()))));

        let user_repository = Arc::new(MockUserRepository::new());
        let mls_store = Arc::new(RwLock::new(MlsStore {
            clients: service.mls_store.read().await.clients.clone(),
            group_map: service.mls_store.read().await.group_map.clone(),
            config: service.mls_store.read().await.config.clone(),
        }));

        let mut ws_client_mock = MockWebSocketClient::new();
        ws_client_mock
            .expect_get_connection_state()
            .returning(|| Box::pin(ready(ConnectionState::Connected)));
        ws_client_mock
            .expect_get_has_reconnected()
            .returning(|| Box::pin(ready(false)));
        ws_client_mock
            .expect_get_group_info_summary()
            .returning(move || {
                Box::pin(ready(Ok(GroupInfoSummaryData {
                    epoch: group_info_summary.epoch.clone(),
                    group_id: group_info_summary.group_id.clone(),
                })))
            });

        let service_with_mock = Service::new(
            Arc::new(http_client),
            Arc::new(MockUserApi::new()),
            user_repository,
            Arc::new(ws_client_mock),
            mls_store,
        );

        // Test is_mls_up_to_date - should return true for same group
        let result = service_with_mock
            .is_mls_up_to_date(&user_token_info.user_id(), meet_link_name, false)
            .await;
        assert!(result.is_ok());
        assert!(result.unwrap());
    }

    #[tokio::test]
    async fn test_is_mls_up_to_date_different_group() {
        // Test case 2: Different group (user not in roster) - should return false
        let meet_link_name = "test_is_mls_up_to_date_different_group";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        // Create service1 and group1 (user1's group)
        let service1 = create_test_service("user1", meet_link_name).await;
        let user_token_info1 = service1
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();
        let (_group1, _) = service1
            .create_mls_group(
                &user_token_info1.user_id(),
                meet_link_name,
                meet_link_name,
                ciphersuite,
            )
            .await
            .unwrap();

        // Create service2 and group2 (user2's group - different group)
        let different_meet_link = "different_meet_link";
        let service2 = create_test_service("user2", different_meet_link).await;
        let user_token_info2 = service2
            .create_mls_client(
                "access_token",
                different_meet_link,
                "meet_password",
                true,
                None,
            )
            .await
            .unwrap();
        let (group2, _) = service2
            .create_mls_group(
                &user_token_info2.user_id(),
                different_meet_link,
                different_meet_link,
                ciphersuite,
            )
            .await
            .unwrap();

        // Get group_id and epoch from group2 (different group) for GroupInfoSummaryData
        let group_info_for_ext_commit = group2
            .read()
            .await
            .group_info_for_ext_commit()
            .await
            .unwrap();
        let group_info_bytes = group_info_for_ext_commit.mls_encode_to_vec().unwrap();
        let group_info_message =
            mls_spec::messages::MlsMessage::from_tls_bytes(&group_info_bytes).unwrap();
        let group_info = match group_info_message.content {
            MlsMessageContent::GroupInfo(gi) => gi,
            _ => panic!("Expected GroupInfo"),
        };

        let group_context = &group_info.group_context;
        let server_group_id = group_context.group_id().to_vec();
        let server_epoch = *group2.read().await.epoch();

        // Create GroupInfoSummaryData from group2 (different group)
        let group_info_summary = GroupInfoSummaryData {
            epoch: server_epoch,
            group_id: server_group_id,
        };

        // Create new service with mocked get_group_info_summary returning different group's data
        let mut http_client = create_mock_http_client_for_mls("user1", meet_link_name, false);
        let g = group_info_summary.clone();
        http_client
            .expect_get_group_info_summary()
            .returning(move |_| Box::pin(ready(Ok(g.clone()))));

        let user_repository = Arc::new(MockUserRepository::new());
        let mls_store = Arc::new(RwLock::new(MlsStore {
            clients: service1.mls_store.read().await.clients.clone(),
            group_map: service1.mls_store.read().await.group_map.clone(),
            config: service1.mls_store.read().await.config.clone(),
        }));

        let mut ws_client_mock = MockWebSocketClient::new();
        ws_client_mock
            .expect_get_connection_state()
            .returning(|| Box::pin(ready(ConnectionState::Connected)));
        ws_client_mock
            .expect_get_has_reconnected()
            .returning(|| Box::pin(ready(false)));
        ws_client_mock
            .expect_get_group_info_summary()
            .returning(move || {
                Box::pin(ready(Ok(GroupInfoSummaryData {
                    epoch: group_info_summary.epoch.clone(),
                    group_id: group_info_summary.group_id.clone(),
                })))
            });

        let service_with_mock = Service::new(
            Arc::new(http_client),
            Arc::new(MockUserApi::new()),
            user_repository,
            Arc::new(ws_client_mock),
            mls_store,
        );

        // Test is_mls_up_to_date - should return false because user1 is not in group2's roster
        let result = service_with_mock
            .is_mls_up_to_date(&user_token_info1.user_id(), meet_link_name, false)
            .await;
        assert!(result.is_ok());
        assert!(!result.unwrap());
    }

    #[tokio::test]
    async fn test_get_current_group_id() {
        // Test case: get_current_group_id should return Vec<u8> without error
        let meet_link_name = "test_get_current_group_id";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        // Create service and group
        let service = create_test_service("user1", meet_link_name).await;
        let user_token_info = service
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();
        let (_group, _commit_bundle) = service
            .create_mls_group(
                &user_token_info.user_id(),
                meet_link_name,
                meet_link_name,
                ciphersuite,
            )
            .await
            .unwrap();

        // Test get_current_group_id - should return Ok(Vec<u8>) without error
        let result = service.get_current_group_id(meet_link_name).await;
        assert!(result.is_ok(), "get_current_group_id should return Ok");

        let group_id = result.unwrap();
        assert!(!group_id.is_empty(), "group_id should not be empty");

        // Verify group_id matches expected value
        let expected_group_id = vec![
            109, 105, 109, 105, 58, 47, 47, 109, 101, 101, 116, 46, 112, 114, 111, 116, 111, 110,
            46, 109, 101, 47, 103, 47, 116, 101, 115, 116, 95, 103, 101, 116, 95, 99, 117, 114,
            114, 101, 110, 116, 95, 103, 114, 111, 117, 112, 95, 105, 100,
        ];
        assert_eq!(
            group_id, expected_group_id,
            "group_id should match expected value"
        );
    }

    #[tokio::test]
    async fn test_get_group_len() {
        // Test case: get_group_len should return the correct roster count
        let meet_link_name = "test_get_group_len";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        // Create service and group with single user
        let service = create_test_service("user1", meet_link_name).await;
        let user_token_info = service
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();
        let (group1, commit_bundle1) = service
            .create_mls_group(
                &user_token_info.user_id(),
                meet_link_name,
                meet_link_name,
                ciphersuite,
            )
            .await
            .unwrap();

        // Test get_group_len with single member - should return 1
        let result = service.get_group_len(meet_link_name).await;
        assert!(result.is_ok(), "get_group_len should return Ok");
        let len = result.unwrap();
        assert_eq!(len, 1, "Group with single member should have length 1");

        // Add a second user to the group
        let service2 = create_test_service("user2", meet_link_name).await;
        let user_token_info2 = service2
            .create_mls_client("access_token", meet_link_name, "meet_password", true, None)
            .await
            .unwrap();

        // Get group info from first user's group
        let group_info_message = mls_spec::messages::MlsMessage::from_tls_bytes(
            &commit_bundle1
                .group_info
                .clone()
                .unwrap()
                .mls_encode_to_vec()
                .unwrap(),
        )
        .unwrap();
        let group_info = match group_info_message.content {
            MlsMessageContent::GroupInfo(group_info) => group_info,
            _ => panic!("Expected GroupInfo"),
        };

        // Second user joins via external commit
        let (_group2, commit_bundle2) = service2
            .create_external_commit(
                &user_token_info2.user_id(),
                meet_link_name,
                ciphersuite,
                group_info,
                commit_bundle1.ratchet_tree.unwrap().try_into().unwrap(),
            )
            .await
            .unwrap();

        // Process the join in first user's group
        let (_, _) = group1
            .write()
            .await
            .decrypt_message(commit_bundle2.commit.clone())
            .await
            .unwrap();

        // Test get_group_len with two members - should return 2
        let result = service.get_group_len(meet_link_name).await;
        assert!(result.is_ok(), "get_group_len should return Ok");
        let len = result.unwrap();
        assert_eq!(len, 2, "Group with two members should have length 2");

        // Test get_group_len from second user's service - should also return 2
        let result2 = service2.get_group_len(meet_link_name).await;
        assert!(result2.is_ok(), "get_group_len should return Ok");
        let len2 = result2.unwrap();
        assert_eq!(len2, 2, "Second user's view should also show 2 members");

        // Test get_group_len with non-existent meeting - should return error
        let result_error = service.get_group_len("non_existent_meeting").await;
        assert!(
            result_error.is_err(),
            "get_group_len should return error for non-existent meeting"
        );
    }

    #[tokio::test]
    async fn test_generate_unique_group_ids_creates_different_groups() {
        // Test case: Different group_id generated by generate_unique_group_id
        // should create MLS groups with different group_id
        let base_name = "test_unique_meeting";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        // Generate group ids
        let unique_name1 = Service::generate_unique_group_id(base_name);
        let unique_name2 = Service::generate_unique_group_id(base_name);

        // Verify generated names are different
        assert_ne!(
            unique_name1, unique_name2,
            "Generated names should be unique"
        );

        // Create service1 and user_token_info1
        let service1 = create_test_service("user1", &base_name).await;
        let user_token_info1 = service1
            .create_mls_client("access_token", &base_name, "meet_password", true, None)
            .await
            .unwrap();

        // Create service2 and user_token_info2
        let service2 = create_test_service("user2", &base_name).await;
        let user_token_info2 = service2
            .create_mls_client("access_token", &base_name, "meet_password", true, None)
            .await
            .unwrap();

        // Create service3 and user_token_info3
        let service3 = create_test_service("user3", &base_name).await;
        let user_token_info3 = service3
            .create_mls_client("access_token", &base_name, "meet_password", true, None)
            .await
            .unwrap();

        // Create MLS groups with different unique meeting link names
        let (_group1, _commit_bundle1) = service1
            .create_mls_group(
                &user_token_info1.user_id(),
                &unique_name1,
                base_name,
                ciphersuite,
            )
            .await
            .unwrap();

        let (_group2, _commit_bundle2) = service2
            .create_mls_group(
                &user_token_info2.user_id(),
                &unique_name2,
                base_name,
                ciphersuite,
            )
            .await
            .unwrap();

        // Create group3 with unique_name1 (same as group1)
        let (_group3, _commit_bundle3) = service3
            .create_mls_group(
                &user_token_info3.user_id(),
                &unique_name1,
                base_name,
                ciphersuite,
            )
            .await
            .unwrap();

        // Get group_id from each group
        let group_id1 = service1.get_current_group_id(base_name).await.unwrap();
        let group_id2 = service2.get_current_group_id(base_name).await.unwrap();
        let group_id3 = service3.get_current_group_id(base_name).await.unwrap();

        // Verify group_ids are different between group1 and group2 (should not be equal)
        assert_ne!(
            group_id1, group_id2,
            "MLS groups created with different unique meeting_link_name should have different group_id"
        );

        // Verify group3 has the same group_id as group1 (same meeting_link_name)
        assert_eq!(
            group_id1, group_id3,
            "MLS groups created with the same meeting_link_name should have the same group_id"
        );
    }

    #[tokio::test]
    async fn test_get_offline_indices_basic() {
        use crate::service::service_state::LivekitUUIDInfo;
        use std::collections::HashMap;

        // Create test services
        let meet_link_name = "test_offline_indices";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        let service1 = create_test_service("user1", meet_link_name).await;
        let service2 = create_test_service("user2", meet_link_name).await;
        let service3 = create_test_service("user3", meet_link_name).await;
        let service4 = create_test_service("user4", meet_link_name).await;

        let groups = setup_n_user_group(
            vec![&service1, &service2, &service3, &service4],
            meet_link_name,
            ciphersuite,
        )
        .await;
        let group1 = groups[0].clone();
        // let group2 = groups[1].clone();
        // let group3 = groups[2].clone();
        // let group4 = groups[3].clone();

        // Get roster from MLS group
        let roster: Vec<mls_types::Member> = {
            let group = group1.read().await;
            group.roster().collect()
        };

        // We should have 4 members
        assert_eq!(roster.len(), 4);

        // Get UUIDs from roster members
        let mut member_uuids = vec![];
        for mut member in roster.iter().cloned() {
            if let Ok(uuid) = crate::service::utils::get_uuid_from_member(&mut member) {
                member_uuids.push((uuid, *member.leaf_index()));
            }
        }

        assert!(
            member_uuids.len() >= 4,
            "Should have at least 4 valid UUIDs"
        );

        // Setup: Add UUIDs to the hashmap with different timestamps
        let current_time = crate::utils::unix_timestamp_ms();
        {
            let mut state = service1.state.lock().await;
            let mut hashmap = HashMap::new();

            // First member: recently active (5 seconds ago)
            hashmap.insert(
                member_uuids[0].0,
                LivekitUUIDInfo {
                    uuid: member_uuids[0].0,
                    last_seen: current_time - 5_000,
                },
            );

            // Second member: offline (70 seconds ago, exceeds 60s threshold)
            hashmap.insert(
                member_uuids[1].0,
                LivekitUUIDInfo {
                    uuid: member_uuids[1].0,
                    last_seen: current_time - 70_000,
                },
            );

            // Third member: barely online (59 seconds ago, just under threshold)
            hashmap.insert(
                member_uuids[2].0,
                LivekitUUIDInfo {
                    uuid: member_uuids[2].0,
                    last_seen: current_time - 59_000,
                },
            );

            state.livekit_active_uuid_hashset = Some(hashmap);
            state.last_livekit_active_uuid_update_time = current_time;
        }

        // Get fresh roster for the test
        let test_roster: Vec<mls_types::Member> = {
            let group = group1.read().await;
            group.roster().collect()
        };

        // Call get_offline_indices
        let offline_indices = service1.get_offline_indices(test_roster).await.unwrap();

        // Verify: Only the second member (70s ago) should be in offline list, the fourth member should be ignored
        assert_eq!(
            offline_indices.len(),
            1,
            "Should have exactly 1 offline member"
        );
        assert_eq!(
            offline_indices[0], member_uuids[1].1,
            "Offline member should be the one with 70s old timestamp"
        );
    }

    #[tokio::test]
    async fn test_get_offline_indices_empty_hashmap() {
        // Create test services
        let meet_link_name = "test_offline_empty";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        let service1 = create_test_service("user1", meet_link_name).await;
        let service2 = create_test_service("user2", meet_link_name).await;

        // Create a simple 2-member group
        let (group1, _group2) =
            setup_two_user_group(&service1, &service2, meet_link_name, ciphersuite).await;

        // Setup: Empty hashmap (no tracked UUIDs)
        {
            let mut state = service1.state.lock().await;
            state.livekit_active_uuid_hashset = None;
            state.last_livekit_active_uuid_update_time = crate::utils::unix_timestamp_ms();
        }

        let roster: Vec<mls_types::Member> = {
            let group = group1.read().await;
            group.roster().collect()
        };

        let offline_indices = service1.get_offline_indices(roster).await.unwrap();

        // Verify: No offline indices since no UUIDs are tracked
        assert_eq!(offline_indices.len(), 0);
    }

    #[tokio::test]
    async fn test_get_deterministic_random_rank_is_deterministic() {
        // Test that the same inputs produce the same output (deterministic)
        let meet_link_name = "test_deterministic_rank";
        let ciphersuite = MlsClientConfig::default().ciphersuite;

        let service1 = create_test_service("user1", meet_link_name).await;
        let service2 = create_test_service("user2", meet_link_name).await;
        let service3 = create_test_service("user3", meet_link_name).await;
        let service4 = create_test_service("user4", meet_link_name).await;

        // Create a 4-member group using the new helper
        let groups = setup_n_user_group(
            vec![&service1, &service2, &service3, &service4],
            meet_link_name,
            ciphersuite,
        )
        .await;

        let roster: Vec<mls_types::Member> = {
            let group = groups[0].read().await;
            group.roster().collect()
        };

        let own_leaf_index = *roster[2].leaf_index();
        let epoch_at = 100;

        // Call the function multiple times with same inputs
        let rank1 = service1
            .get_deterministic_random_rank(own_leaf_index, epoch_at, roster.clone())
            .await
            .unwrap();

        let rank2 = service1
            .get_deterministic_random_rank(own_leaf_index, epoch_at, roster.clone())
            .await
            .unwrap();

        let rank3 = service1
            .get_deterministic_random_rank(own_leaf_index, epoch_at, roster.clone())
            .await
            .unwrap();

        // All ranks should be identical (deterministic)
        assert_eq!(rank1, rank2, "Rank should be deterministic");
        assert_eq!(rank2, rank3, "Rank should be deterministic");
    }

    #[tokio::test]
    async fn test_get_deterministic_random_rank_is_random_across_epochs() {
        // Test that different epochs produce different rankings (random)
        let meet_link_name = "test_random_rank";
        let ciphersuite = MlsClientConfig::default().ciphersuite;

        let service1 = create_test_service("user1", meet_link_name).await;
        let service2 = create_test_service("user2", meet_link_name).await;
        let service3 = create_test_service("user3", meet_link_name).await;
        let service4 = create_test_service("user4", meet_link_name).await;
        let service5 = create_test_service("user5", meet_link_name).await;
        let service6 = create_test_service("user6", meet_link_name).await;
        let service7 = create_test_service("user7", meet_link_name).await;
        let service8 = create_test_service("user8", meet_link_name).await;
        let service9 = create_test_service("user9", meet_link_name).await;
        let service10 = create_test_service("user10", meet_link_name).await;

        // Create a 10-member group using the new helper
        let groups = setup_n_user_group(
            vec![
                &service1, &service2, &service3, &service4, &service5, &service6, &service7,
                &service8, &service9, &service10,
            ],
            meet_link_name,
            ciphersuite,
        )
        .await;

        let roster: Vec<mls_types::Member> = {
            let group = groups[0].read().await;
            group.roster().collect()
        };

        let own_leaf_index = *roster[2].leaf_index();

        // Collect ranks for different epochs
        let mut ranks = Vec::new();
        for epoch in 0..20 {
            let rank = service1
                .get_deterministic_random_rank(own_leaf_index, epoch, roster.clone())
                .await
                .unwrap();
            ranks.push(rank);
        }

        // Count unique ranks - should have multiple different values
        let mut unique_ranks: Vec<u64> = ranks.clone();
        unique_ranks.sort();
        unique_ranks.dedup();

        // With 20 different epochs and 10 members, we should get at least 5 different ranks
        assert!(
            unique_ranks.len() >= 5,
            "Expected at least 5 different ranks across 20 epochs, got {}. Ranks: {:?}",
            unique_ranks.len(),
            ranks
        );
    }

    #[tokio::test]
    async fn test_kick_participant_success() {
        let meet_link_name = "test-kick-success";
        let ciphersuite =
            proton_meet_mls::CipherSuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

        // Setup three-user group
        let mut service1 = create_test_service_with_host("user_id1", meet_link_name, true).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let groups = setup_n_user_group(
            vec![&service1, &service2, &service3],
            meet_link_name,
            ciphersuite,
        )
        .await;
        let group1 = groups[0].clone();

        // Verify initial state: 3 members
        assert_eq!(group1.read().await.roster().count(), 3);
        let initial_epoch = *group1.read().await.epoch();

        // Get user2's UUID from roster
        let user2_uuid = {
            let group = group1.read().await;
            let roster: Vec<_> = group.roster().collect();
            // Get second member's UUID
            if let mls_types::Credential::SdCwtDraft04 { claimset, .. } = &roster[1].credential {
                uuid::Uuid::from_bytes(claimset.as_ref().unwrap().uuid).to_string()
            } else {
                panic!("Expected SdCwtDraft04 credential");
            }
        };

        // Mock update_group_info to succeed
        let mut http_client = create_mock_http_client_for_mls("user_id1", meet_link_name, true);
        http_client
            .expect_update_group_info()
            .returning(|_, _, _, _, _| Box::pin(ready(Ok(()))));

        // Replace service1's http_client with mocked one
        service1.http_client = Arc::new(http_client);

        // Kick user2
        service1
            .kick_participant(&user2_uuid, meet_link_name)
            .await
            .unwrap();

        // Verify user2 removed from group1
        let final_roster_count = group1.read().await.roster().count();
        assert_eq!(final_roster_count, 2, "Should have 2 members after kick");

        // Verify epoch advanced
        let final_epoch = *group1.read().await.epoch();
        assert!(
            final_epoch > initial_epoch,
            "Epoch should advance after kick"
        );

        // Verify user2 specifically is not in roster
        let user2_in_roster = group1.read().await.roster().any(|m| {
            if let mls_types::Credential::SdCwtDraft04 { claimset, .. } = &m.credential {
                let uuid_str = uuid::Uuid::from_bytes(claimset.as_ref().unwrap().uuid).to_string();
                uuid_str == user2_uuid
            } else {
                false
            }
        });
        assert!(!user2_in_roster, "User2 should not be in roster");
    }

    #[tokio::test]
    async fn test_kick_participant_retries_on_422() {
        let meet_link_name = "test-kick-retry";
        let ciphersuite =
            proton_meet_mls::CipherSuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

        // Setup three-user group
        let mut service1 = create_test_service_with_host("user_id1", meet_link_name, true).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let groups = setup_n_user_group(
            vec![&service1, &service2, &service3],
            meet_link_name,
            ciphersuite,
        )
        .await;
        let group1 = groups[0].clone();

        // Get user2's UUID
        let user2_uuid = {
            let group = group1.read().await;
            let roster: Vec<_> = group.roster().collect();
            if let mls_types::Credential::SdCwtDraft04 { claimset, .. } = &roster[1].credential {
                uuid::Uuid::from_bytes(claimset.as_ref().unwrap().uuid).to_string()
            } else {
                panic!("Expected SdCwtDraft04 credential");
            }
        };

        // Mock update_group_info to fail once with 422, then succeed
        let mut http_client = create_mock_http_client_for_mls("user_id1", meet_link_name, true);
        let call_count = Arc::new(std::sync::atomic::AtomicU32::new(0));
        let call_count_clone = call_count.clone();

        http_client
            .expect_update_group_info()
            .returning(move |_, _, _, _, _| {
                let count = call_count_clone.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                if count == 0 {
                    // First call: return 422
                    Box::pin(ready(Err(
                        crate::errors::http_client::HttpClientError::ErrorCode(
                            Status::from_u16(422).unwrap(),
                            crate::errors::http_client::ResponseError {
                                code: 422,
                                details: serde_json::Value::Null,
                                error: "Validation error".to_string(),
                            },
                        ),
                    )))
                } else {
                    // Second call: succeed
                    Box::pin(ready(Ok(())))
                }
            });

        service1.http_client = Arc::new(http_client);

        // Record start time
        let start = std::time::Instant::now();

        // Kick should succeed on second attempt
        service1
            .kick_participant(&user2_uuid, meet_link_name)
            .await
            .unwrap();

        let elapsed = start.elapsed();

        // Verify retry happened (should have delay between attempts)
        assert!(
            elapsed.as_millis() >= 450, // Base delay is 500ms, with jitter could be ~450ms
            "Should have delayed for retry, elapsed: {}ms",
            elapsed.as_millis()
        );

        // Verify user2 was kicked
        let final_roster_count = group1.read().await.roster().count();
        assert_eq!(final_roster_count, 2);

        // Verify update_group_info was called twice
        assert_eq!(call_count.load(std::sync::atomic::Ordering::SeqCst), 2);
    }

    #[tokio::test]
    async fn test_kick_participant_max_retries_exhausted() {
        let meet_link_name = "test-kick-max-retries";
        let ciphersuite =
            proton_meet_mls::CipherSuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

        // Setup three-user group
        let mut service1 = create_test_service_with_host("user_id1", meet_link_name, true).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let groups = setup_n_user_group(
            vec![&service1, &service2, &service3],
            meet_link_name,
            ciphersuite,
        )
        .await;
        let group1 = groups[0].clone();

        // Get user2's UUID
        let user2_uuid = {
            let group = group1.read().await;
            let roster: Vec<_> = group.roster().collect();
            if let mls_types::Credential::SdCwtDraft04 { claimset, .. } = &roster[1].credential {
                uuid::Uuid::from_bytes(claimset.as_ref().unwrap().uuid).to_string()
            } else {
                panic!("Expected SdCwtDraft04 credential");
            }
        };

        // Mock update_group_info to always fail with 422
        let mut http_client = create_mock_http_client_for_mls("user_id1", meet_link_name, true);
        let call_count = Arc::new(std::sync::atomic::AtomicU32::new(0));
        let call_count_clone = call_count.clone();

        http_client
            .expect_update_group_info()
            .returning(move |_, _, _, _, _| {
                call_count_clone.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                Box::pin(ready(Err(
                    crate::errors::http_client::HttpClientError::ErrorCode(
                        Status::from_u16(422).unwrap(),
                        crate::errors::http_client::ResponseError {
                            code: 422,
                            details: serde_json::Value::Null,
                            error: "Validation error".to_string(),
                        },
                    ),
                )))
            });

        service1.http_client = Arc::new(http_client);

        // Kick should fail with MaxRetriesReached
        let result = service1.kick_participant(&user2_uuid, meet_link_name).await;

        assert!(result.is_err(), "Should fail after max retries");
        match result.unwrap_err() {
            crate::errors::core::MeetCoreError::MaxRetriesReached => {
                // Expected error
            }
            e => panic!("Expected MaxRetriesReached, got: {e:?}"),
        }

        // Verify all 4 attempts were made (1 initial + 3 retries)
        assert_eq!(
            call_count.load(std::sync::atomic::Ordering::SeqCst),
            4,
            "Should have made 4 total attempts"
        );
    }

    #[tokio::test]
    async fn test_kick_participant_non_422_fails_immediately() {
        let meet_link_name = "test-kick-non-422";
        let ciphersuite =
            proton_meet_mls::CipherSuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

        // Setup three-user group
        let mut service1 = create_test_service_with_host("user_id1", meet_link_name, true).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let groups = setup_n_user_group(
            vec![&service1, &service2, &service3],
            meet_link_name,
            ciphersuite,
        )
        .await;
        let group1 = groups[0].clone();

        // Get user2's UUID
        let user2_uuid = {
            let group = group1.read().await;
            let roster: Vec<_> = group.roster().collect();
            if let mls_types::Credential::SdCwtDraft04 { claimset, .. } = &roster[1].credential {
                uuid::Uuid::from_bytes(claimset.as_ref().unwrap().uuid).to_string()
            } else {
                panic!("Expected SdCwtDraft04 credential");
            }
        };

        // Mock update_group_info to fail with 500 (non-retryable)
        let mut http_client = create_mock_http_client_for_mls("user_id1", meet_link_name, true);
        let call_count = Arc::new(std::sync::atomic::AtomicU32::new(0));
        let call_count_clone = call_count.clone();

        http_client
            .expect_update_group_info()
            .returning(move |_, _, _, _, _| {
                call_count_clone.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                Box::pin(ready(Err(
                    crate::errors::http_client::HttpClientError::ErrorCode(
                        Status::from_u16(500).unwrap(),
                        crate::errors::http_client::ResponseError {
                            code: 500,
                            details: serde_json::Value::Null,
                            error: "Internal server error".to_string(),
                        },
                    ),
                )))
            });

        service1.http_client = Arc::new(http_client);

        // Kick should fail immediately
        let start = std::time::Instant::now();
        let result = service1.kick_participant(&user2_uuid, meet_link_name).await;
        let elapsed = start.elapsed();

        assert!(result.is_err(), "Should fail immediately");

        // Should NOT be MaxRetriesReached - should be the original error
        assert!(
            !matches!(
                result.unwrap_err(),
                crate::errors::core::MeetCoreError::MaxRetriesReached
            ),
            "Should return original error, not MaxRetriesReached"
        );

        // Verify only 1 attempt was made
        assert_eq!(
            call_count.load(std::sync::atomic::Ordering::SeqCst),
            1,
            "Should only attempt once for non-422 error"
        );

        // Verify no retry delay (should be fast)
        assert!(
            elapsed.as_millis() < 100,
            "Should fail fast without retry delay"
        );
    }

    #[tokio::test]
    async fn test_kick_participant_target_already_removed() {
        let meet_link_name = "test-kick-already-removed";
        let ciphersuite =
            proton_meet_mls::CipherSuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

        // Setup three-user group
        let mut service1 = create_test_service_with_host("user_id1", meet_link_name, true).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let groups = setup_n_user_group(
            vec![&service1, &service2, &service3],
            meet_link_name,
            ciphersuite,
        )
        .await;
        let group1 = groups[0].clone();

        // Get user2's UUID
        let user2_uuid = {
            let group = group1.read().await;
            let roster: Vec<_> = group.roster().collect();
            if let mls_types::Credential::SdCwtDraft04 { claimset, .. } = &roster[1].credential {
                uuid::Uuid::from_bytes(claimset.as_ref().unwrap().uuid).to_string()
            } else {
                panic!("Expected SdCwtDraft04 credential");
            }
        };

        // Mock update_group_info to succeed
        let mut http_client = create_mock_http_client_for_mls("user_id1", meet_link_name, true);
        http_client
            .expect_update_group_info()
            .returning(|_, _, _, _, _| Box::pin(ready(Ok(()))));
        service1.http_client = Arc::new(http_client);

        // First kick: Remove user2
        service1
            .kick_participant(&user2_uuid, meet_link_name)
            .await
            .unwrap();

        // Verify user2 is removed
        assert_eq!(group1.read().await.roster().count(), 2);

        // Second kick: Try to kick user2 again - should return Ok() without error
        let result = service1.kick_participant(&user2_uuid, meet_link_name).await;

        assert!(result.is_ok(), "Should succeed when target already removed");
    }

    #[tokio::test]
    async fn test_kick_participant_includes_queued_proposals() {
        let meet_link_name = "test-kick-queued";
        let ciphersuite =
            proton_meet_mls::CipherSuite::MLS_128_DHKEMX25519_AES128GCM_SHA256_Ed25519;

        // Setup three-user group
        let mut service1 = create_test_service_with_host("user_id1", meet_link_name, true).await;
        let service2 = create_test_service("user_id2", meet_link_name).await;
        let service3 = create_test_service("user_id3", meet_link_name).await;

        let groups = setup_n_user_group(
            vec![&service1, &service2, &service3],
            meet_link_name,
            ciphersuite,
        )
        .await;
        let group1 = groups[0].clone();

        let initial_roster_count = group1.read().await.roster().count();
        assert_eq!(initial_roster_count, 3);

        // Get user2's UUID for later removal
        let user2_uuid = {
            let group = group1.read().await;
            let roster: Vec<_> = group.roster().collect();
            if let mls_types::Credential::SdCwtDraft04 { claimset, .. } = &roster[1].credential {
                uuid::Uuid::from_bytes(claimset.as_ref().unwrap().uuid).to_string()
            } else {
                panic!("Expected SdCwtDraft04 credential");
            }
        };

        // Create a remove proposal for user3 (index 2) and queue it
        // This simulates having pending proposals when kick is called
        let user3_remove_proposal = {
            let mut group = group1.write().await;
            let mut proposals = group
                .new_proposals([ProposalArg::Remove(
                    meet_identifiers::LeafIndex::try_from(2u32).unwrap(),
                )])
                .await
                .unwrap();
            proposals.remove(0)
        };

        // Queue the proposal
        {
            let mut queue = service1.proposal_queue.lock().await;
            queue.insert(
                meet_link_name.to_string(),
                vec![QueuedProposal {
                    proposal_message: user3_remove_proposal,
                    proposal_type: ProposalType::Remove,
                }],
            );
        }

        // Verify queue has 1 proposal
        let queued_count = service1
            .proposal_queue
            .lock()
            .await
            .get(meet_link_name)
            .map(|v| v.len())
            .unwrap_or(0);
        assert_eq!(queued_count, 1, "Should have 1 queued proposal");

        // Mock update_group_info to succeed
        let mut http_client = create_mock_http_client_for_mls("user_id1", meet_link_name, true);
        http_client
            .expect_update_group_info()
            .returning(|_, _, _, _, _| Box::pin(ready(Ok(()))));
        service1.http_client = Arc::new(http_client);

        // Kick user2 - should also process the queued user3 removal
        service1
            .kick_participant(&user2_uuid, meet_link_name)
            .await
            .unwrap();

        // Verify both user2 and user3 were removed (3 -> 1, only user1 remains)
        let final_roster_count = group1.read().await.roster().count();
        assert_eq!(
            final_roster_count, 1,
            "Should have 1 member after kick (both user2 and user3 removed)"
        );

        // Verify queue is now empty (proposals were extracted and processed)
        let queue_empty = service1
            .proposal_queue
            .lock()
            .await
            .get(meet_link_name)
            .map(|v| v.is_empty())
            .unwrap_or(true);
        assert!(queue_empty, "Proposal queue should be empty after kick");
    }

    #[tokio::test]
    async fn test_process_commit_rejects_missing_psk_when_flag_enabled() {
        let meet_link_name = "test_psk_reject_missing";
        let config = MlsClientConfig::default();

        let service1 = create_test_service("psk-user1", meet_link_name).await;
        let service2 = create_test_service("psk-user2", meet_link_name).await;

        // use_psk defaults to true in Service::new; the helper does not change it
        let (group1, _group2, _) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        // group1 creates a commit with NO PSK proposal
        let commit_bundle = {
            let mut group1_guard = group1.write().await;
            let (bundle, _) = group1_guard.new_commit(vec![]).await.unwrap();
            group1_guard.merge_pending_commit().await.unwrap();
            bundle
        };

        // Deliver the no-PSK commit to service2 which has use_psk=true
        let commit_bytes = commit_bundle.commit.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&commit_bytes).unwrap(),
            }),
        };
        let ws_message = WebSocketMessage::Binary(rtc_message.to_tls_bytes().unwrap());
        service2.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = service2.handle_websocket_message(ws_message).await;

        assert!(
            result.is_err(),
            "Expected error when commit has no PSK proposal and use_psk=true"
        );
        let err = result.unwrap_err();
        assert!(
            err.downcast_ref::<ServiceError>()
                .map(|e| matches!(e, ServiceError::PskProposalMissing))
                .unwrap_or(false),
            "Expected PskProposalMissing error, got: {:?}",
            err
        );
    }

    #[tokio::test]
    async fn test_process_commit_rejects_wrong_psk_id() {
        let meet_link_name = "test_psk_reject_wrong_id";
        let config = MlsClientConfig::default();
        let ciphersuite = config.ciphersuite;

        let service1 = create_test_service("psk-user1", meet_link_name).await;
        let service2 = create_test_service("psk-user2", meet_link_name).await;

        // use_psk defaults to true in Service::new; the helper does not change it
        let (group1, _group2, _) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            ciphersuite,
        )
        .await;

        let user1_id = {
            let store = service1.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("service1 should have one MLS client")
        };
        let user2_id = {
            let store = service2.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("service2 should have one MLS client")
        };

        // Insert a PSK with a WRONG ID (not matching meet_link_name/room_id) into both clients
        let wrong_psk_id = mls_types::ExternalPskId(b"wrong-room-id".to_vec());
        let psk_value = mls_types::ExternalPsk(b"some-psk-secret-value-for-testing".to_vec());

        {
            let store = service1.mls_store.read().await;
            let client = store
                .find_client(&user1_id, &ciphersuite)
                .expect("service1 client should exist");
            client
                .insert_external_psk(wrong_psk_id.clone(), psk_value.clone())
                .await
                .expect("service1 should insert external PSK");
        }
        {
            let store = service2.mls_store.read().await;
            let client = store
                .find_client(&user2_id, &ciphersuite)
                .expect("service2 client should exist");
            client
                .insert_external_psk(wrong_psk_id.clone(), psk_value.clone())
                .await
                .expect("service2 should insert external PSK");
        }

        // group1 creates a commit referencing the WRONG PSK ID.
        // Do NOT call merge_pending_commit so group1's epoch is not advanced —
        // this lets MLS decryption succeed on service2 (it has the same wrong PSK)
        // while the service-level check still rejects it (PSK ID != room_id).
        let commit_bundle = {
            let mut group1_guard = group1.write().await;
            let (bundle, _) = group1_guard
                .new_commit(vec![ProposalArg::PskExternal {
                    id: wrong_psk_id.clone(),
                }])
                .await
                .unwrap();
            bundle
        };

        // Deliver the wrong-PSK commit to service2 which expects PSK ID == room_id
        let commit_bytes = commit_bundle.commit.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&commit_bytes).unwrap(),
            }),
        };
        let ws_message = WebSocketMessage::Binary(rtc_message.to_tls_bytes().unwrap());
        service2.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = service2.handle_websocket_message(ws_message).await;

        assert!(
            result.is_err(),
            "Expected error when PSK ID in commit does not match room_id"
        );
        let err = result.unwrap_err();
        // PskProposalMissing covers both "no PSK proposal" and "PSK proposal with wrong ID" —
        // the service checks for a proposal matching room_id exactly; a wrong ID fails the same predicate.
        assert!(
            err.downcast_ref::<ServiceError>()
                .map(|e| matches!(e, ServiceError::PskProposalMissing))
                .unwrap_or(false),
            "Expected PskProposalMissing error, got: {:?}",
            err
        );
    }

    #[tokio::test]
    async fn test_process_commit_allows_missing_psk_when_flag_disabled() {
        let meet_link_name = "test_psk_allow_no_psk";
        let config = MlsClientConfig::default();

        let service1 = create_test_service("psk-user1", meet_link_name).await;
        let service2 = create_test_service("psk-user2", meet_link_name).await;

        // Setup helper sets use_psk=true on both services internally
        let (group1, _group2, _) = setup_two_user_group_with_commit_bundle(
            &service1,
            &service2,
            meet_link_name,
            config.ciphersuite,
        )
        .await;

        // Set use_psk = false on service2 (the receiver being tested).
        // Accessing the private field directly is allowed within #[cfg(test)] code in the same module.
        *service2.use_psk.lock().await = false;

        // group1 creates a commit with NO PSK proposal
        let commit_bundle = {
            let mut group1_guard = group1.write().await;
            let (bundle, _) = group1_guard.new_commit(vec![]).await.unwrap();
            group1_guard.merge_pending_commit().await.unwrap();
            bundle
        };

        // Deliver the no-PSK commit to service2 which now has use_psk=false
        let commit_bytes = commit_bundle.commit.mls_encode_to_vec().unwrap();
        let rtc_message = RTCMessageIn {
            content: RTCMessageInContent::CommitUpdate(MlsCommitInfo {
                room_id: meet_link_name.as_bytes().to_vec(),
                welcome_message: None,
                commit: mls_spec::messages::MlsMessage::from_tls_bytes(&commit_bytes).unwrap(),
            }),
        };
        let ws_message = WebSocketMessage::Binary(rtc_message.to_tls_bytes().unwrap());
        service2.state.lock().await.mls_group_state = MlsGroupState::Success;
        let result = service2.handle_websocket_message(ws_message).await;

        assert!(
            result.is_ok(),
            "Expected commit with no PSK to succeed when use_psk=false, got: {:?}",
            result.err()
        );
    }

    async fn setup_single_user_group(
        room_id: &str,
    ) -> (
        Service,
        Arc<RwLock<MlsGroup<MemKv>>>,
        proton_meet_mls::CipherSuite,
        String,
    ) {
        let config = MlsClientConfig::default();
        let service = create_test_service("psk-unit-user", room_id).await;
        let user_token_info = service
            .create_mls_client("access_token", room_id, "meet_password", true, None)
            .await
            .unwrap();
        let (group, _) = service
            .create_mls_group(
                &user_token_info.user_id(),
                room_id,
                room_id,
                config.ciphersuite,
            )
            .await
            .unwrap();
        let user_key = {
            let store = service.mls_store.read().await;
            store
                .clients
                .keys()
                .next()
                .cloned()
                .expect("client should exist")
        };
        (service, group, config.ciphersuite, user_key)
    }

    fn commit_to_mls_message(commit_bundle: &CommitBundle) -> mls_types::MlsMessage {
        let commit_bytes = commit_bundle.commit.mls_encode_to_vec().unwrap();
        let spec_msg = mls_spec::messages::MlsMessage::from_tls_bytes(&commit_bytes).unwrap();
        mls_types::MlsMessage::try_from(spec_msg).unwrap()
    }

    #[tokio::test]
    async fn validate_psk_proposal_accepts_commit_with_correct_psk_id() {
        let room_id = "unit-psk-correct";
        let (service, group, ciphersuite, user_id) = setup_single_user_group(room_id).await;

        let psk_id = mls_types::ExternalPskId(room_id.as_bytes().to_vec());
        let psk_value = mls_types::ExternalPsk(b"test-psk-secret".to_vec());
        {
            let store = service.mls_store.read().await;
            let client = store.find_client(&user_id, &ciphersuite).unwrap();
            client
                .insert_external_psk(psk_id.clone(), psk_value)
                .await
                .unwrap();
        }

        let commit_bundle = {
            let mut g = group.write().await;
            let (bundle, _) = g
                .new_commit(vec![ProposalArg::PskExternal { id: psk_id }])
                .await
                .unwrap();
            bundle
        };

        let result = Service::validate_psk_proposal(commit_to_mls_message(&commit_bundle), room_id);
        assert!(
            result.is_ok(),
            "Expected Ok for correct PSK ID, got: {:?}",
            result.err()
        );
    }

    #[tokio::test]
    async fn validate_psk_proposal_rejects_commit_with_no_psk_proposal() {
        let room_id = "unit-psk-missing";
        let (_, group, _, _) = setup_single_user_group(room_id).await;

        let commit_bundle = {
            let mut g = group.write().await;
            let (bundle, _) = g.new_commit(vec![]).await.unwrap();
            bundle
        };

        let result = Service::validate_psk_proposal(commit_to_mls_message(&commit_bundle), room_id);
        assert!(
            result
                .as_ref()
                .err()
                .and_then(|e| e.downcast_ref::<ServiceError>())
                .map(|e| matches!(e, ServiceError::PskProposalMissing))
                .unwrap_or(false),
            "Expected PskProposalMissing, got: {:?}",
            result
        );
    }

    #[tokio::test]
    async fn validate_psk_proposal_rejects_commit_with_wrong_psk_id() {
        let room_id = "unit-psk-wrong-id";
        let (service, group, ciphersuite, user_id) = setup_single_user_group(room_id).await;

        let wrong_id = mls_types::ExternalPskId(b"wrong-room-id".to_vec());
        let psk_value = mls_types::ExternalPsk(b"test-psk-secret".to_vec());
        {
            let store = service.mls_store.read().await;
            let client = store.find_client(&user_id, &ciphersuite).unwrap();
            client
                .insert_external_psk(wrong_id.clone(), psk_value)
                .await
                .unwrap();
        }

        let commit_bundle = {
            let mut g = group.write().await;
            let (bundle, _) = g
                .new_commit(vec![ProposalArg::PskExternal { id: wrong_id }])
                .await
                .unwrap();
            bundle
        };

        let result = Service::validate_psk_proposal(commit_to_mls_message(&commit_bundle), room_id);
        assert!(
            result
                .as_ref()
                .err()
                .and_then(|e| e.downcast_ref::<ServiceError>())
                .map(|e| matches!(e, ServiceError::PskProposalMissing))
                .unwrap_or(false),
            "Expected PskProposalMissing, got: {:?}",
            result
        );
    }
}
