use std::{str::FromStr, sync::Arc};

use identity::{Disclosure, PresentationContext};
use meet_identifiers::{Domain, GroupId, Id};
use meet_type::fanout::{MlsCommitInfo, MlsWelcomeInfo};
use mls_rs_codec::MlsEncode;
use mls_spec::{
    defs::ProtocolVersion,
    drafts::ratchet_tree_options::RatchetTreeOption,
    group::{group_info::GroupInfo, welcome::Welcome},
    messages::{MlsMessage, MlsMessageContent},
    Parsable, Serializable,
};
use mls_trait::{
    meet_policy::RoomKind, MlsClientTrait, MlsGroupConfig, MlsGroupTrait, ProposalArg,
};
use mls_types::{ExternalPskId, PublicRatchetTree};
use proton_meet_macro::async_trait;
use proton_meet_mls::{MlsStore, MlsStoreError};
use tokio::sync::RwLock;
use uuid::Uuid;

use crate::domain::mls::ports::{KeyPackageError, KeyPackagePort};
use crate::domain::user::models::{meeting_link_name::MeetingLinkName, UserId};
use crate::service::service::{psk_id_for_commit, public_ratchet_tree_has_agent};

#[derive(Clone)]
pub struct MlsService {
    mls_store: Arc<RwLock<MlsStore>>,
}

impl MlsService {
    pub fn new(mls_store: Arc<RwLock<MlsStore>>) -> Self {
        Self { mls_store }
    }

    pub async fn create_mls_group(
        &self,
        meeting_link_name: &MeetingLinkName,
        user_id: &UserId,
        room_kind: Option<RoomKind>,
    ) -> Result<(MlsMessage, RatchetTreeOption), MlsServiceError> {
        let mut mls_store = self.mls_store.write().await;
        let cs = mls_store.config.ciphersuite;
        let client = mls_store.find_client(&user_id.to_string(), &cs)?;

        let user_id = client.user_id()?;
        let group_id = GroupId {
            id: Id::from_str(&Self::generate_unique_group_id(meeting_link_name.as_str()))?,
            domain: Domain::from_str("meet.proton.me")?,
        };

        let is_host = client
            .new_sd_kbt(Disclosure::Full, None, &PresentationContext::Default)?
            .0
            .sd_cwt_payload()?
            .inner
            .extra
            .as_ref()
            .ok_or(MlsServiceError::NoExtraPayload)?
            .is_host;
        let group_config = match room_kind {
            Some(room_kind) => MlsGroupConfig::new(user_id.clone(), room_kind, is_host),
            // None => MlsGroupConfig::new(
            //     user_id.clone(),
            //     // todo: remove this test code and replace with basic default room kind (no waiting room)
            //     RoomKind::BasicRoomWithWaiting {
            //         other_users: vec![],
            //     },
            //     is_host,
            // ),
            None => MlsGroupConfig::default(user_id.clone(), is_host),
        };
        let mut group = client
            .new_group(&group_id, Disclosure::Full, group_config)
            .await?
            .store()
            .await?;

        let (bundle, ..) = group
            .new_commit([ProposalArg::PskExternal {
                id: ExternalPskId(meeting_link_name.as_str().as_bytes().to_vec()),
            }])
            .await?;
        group.merge_pending_commit().await?;

        assert!(group.roster().count() == 1);
        assert!(bundle.group_info.is_some());
        assert!(bundle.ratchet_tree.is_some());

        let group_to_save = Arc::new(RwLock::new(group));
        mls_store.group_map.insert(
            meeting_link_name.as_str().to_string(),
            group_to_save.clone(),
        );

        let group_info = bundle.group_info.ok_or(MlsServiceError::NoGroupInfo)?;
        let group_info_message = Self::convert_mls_types_to_spec(&group_info)?;
        let ratchet_tree = bundle.ratchet_tree.ok_or(MlsServiceError::NoRatchetTree)?;
        let ratchet_tree_option: RatchetTreeOption = ratchet_tree
            .try_into()
            .map_err(|_| MlsServiceError::RatchetTreeOptionError)?;

        Ok((group_info_message, ratchet_tree_option))
    }

    pub async fn join_group_via_external_commit(
        &self,
        meeting_link_name: &MeetingLinkName,
        user_id: &UserId,
        group_info: GroupInfo,
        ratchet_tree_option: RatchetTreeOption,
    ) -> Result<(MlsMessage, RatchetTreeOption, MlsCommitInfo), MlsServiceError> {
        let mut mls_store = self.mls_store.write().await;
        let cs = mls_store.config.ciphersuite;
        let client = mls_store.find_client(&user_id.to_string(), &cs)?;

        let group_info_msg = MlsMessage {
            version: ProtocolVersion::Mls10,
            content: MlsMessageContent::GroupInfo(group_info),
        };
        let group_info_msg = Self::convert_mls_spec_to_types(&group_info_msg)?;
        let ratchet_tree: PublicRatchetTree = ratchet_tree_option.try_into()?;

        // Pick the PSK id based on whether the group already contains an agent leaf.
        let psk_id = psk_id_for_commit(
            meeting_link_name.as_str(),
            public_ratchet_tree_has_agent(&ratchet_tree),
        );

        let result = client
            .join_group_via_external_commit(
                group_info_msg,
                ratchet_tree,
                Disclosure::Full,
                vec![psk_id],
            )
            .await;
        let (mls_group, commit_bundle) = match result {
            Ok((mls_group, commit_bundle)) => (mls_group, commit_bundle),
            Err(e) => {
                return Err(MlsServiceError::FailedToJoinGroupViaExternalCommit(e));
            }
        };
        let mls_group = mls_group.store().await?;
        let group_to_save = Arc::new(RwLock::new(mls_group));
        mls_store.group_map.insert(
            meeting_link_name.as_str().to_string(),
            group_to_save.clone(),
        );

        let group_info = commit_bundle
            .group_info
            .ok_or(MlsServiceError::NoGroupInfo)?;
        let group_info_message = Self::convert_mls_types_to_spec(&group_info)?;
        let ratchet_tree_option: RatchetTreeOption = commit_bundle
            .ratchet_tree
            .ok_or(MlsServiceError::NoRatchetTree)?
            .try_into()
            .map_err(|_| MlsServiceError::RatchetTreeOptionError)?;
        let welcome: Option<Welcome> = commit_bundle.welcome.map(TryInto::try_into).transpose()?;
        let mls_commit_info = MlsCommitInfo {
            room_id: meeting_link_name.as_str().as_bytes().to_vec(),
            welcome_message: welcome,
            commit: Self::convert_mls_types_to_spec(&commit_bundle.commit)?,
        };

        Ok((group_info_message, ratchet_tree_option, mls_commit_info))
    }

    pub async fn create_proposal_to_join_group(
        &self,
        user_id: &UserId,
        group_info: GroupInfo,
        ratchet_tree_option: RatchetTreeOption,
    ) -> Result<MlsMessage, MlsServiceError> {
        let mls_store = self.mls_store.read().await;
        let cs = mls_store.config.ciphersuite;
        let client = mls_store.find_client(&user_id.to_string(), &cs)?;

        let group_info_msg = MlsMessage {
            version: ProtocolVersion::Mls10,
            content: MlsMessageContent::GroupInfo(group_info),
        };
        let group_info_msg = Self::convert_mls_spec_to_types(&group_info_msg)?;
        let ratchet_tree: PublicRatchetTree = ratchet_tree_option.try_into()?;
        let add_proposal = client
            .join_via_external_proposal(group_info_msg, ratchet_tree, Disclosure::Full)
            .await?;
        let proposal_message = Self::convert_mls_types_to_spec(&add_proposal)?;
        Ok(proposal_message)
    }

    pub async fn join_group_via_welcome(
        &self,
        user_id: &UserId,
        meeting_link_name: &MeetingLinkName,
        welcome_info: MlsWelcomeInfo,
    ) -> Result<(), MlsServiceError> {
        let welcome = welcome_info.welcome;
        let welcome_message = welcome.into_mls_message(ProtocolVersion::Mls10);
        let mut mls_store = self.mls_store.write().await;
        let cs = mls_store.config.ciphersuite;
        let client = mls_store.find_client(&user_id.to_string(), &cs)?;
        let welcome_message = Self::convert_mls_spec_to_types(&welcome_message)?;
        let ratchet_tree: PublicRatchetTree = welcome_info.ratchet_tree.try_into()?;
        let (mls_group, _) = client.join_group(welcome_message, ratchet_tree).await?;
        let mls_group = mls_group.store().await?;
        let group_to_save = Arc::new(RwLock::new(mls_group));
        mls_store.group_map.insert(
            meeting_link_name.as_str().to_string(),
            group_to_save.clone(),
        );

        Ok(())
    }

    /// Generates a unique group id by appending a UUID suffix.
    /// This is used to avoid conflicts when creating MLS groups with the same base name.
    fn generate_unique_group_id(base_name: &str) -> String {
        let uuid_suffix = Uuid::new_v4();
        format!("{base_name}_{uuid_suffix}")
    }

    pub fn convert_mls_types_to_spec(
        message: &mls_types::MlsMessage,
    ) -> Result<mls_spec::messages::MlsMessage, MlsServiceError> {
        let encoded = message.mls_encode_to_vec()?;
        Ok(mls_spec::messages::MlsMessage::from_tls_bytes(&encoded)?)
    }

    pub fn convert_mls_spec_to_types(
        message: &mls_spec::messages::MlsMessage,
    ) -> Result<mls_types::MlsMessage, MlsServiceError> {
        let encoded = message.to_tls_bytes()?;
        Ok(mls_types::MlsMessage::from_bytes(&encoded)?)
    }
}

#[async_trait]
impl KeyPackagePort for MlsService {
    async fn new_key_package(&self, user_id: &UserId) -> Result<Vec<u8>, KeyPackageError> {
        let mls_store = self.mls_store.read().await;
        let cs = mls_store.config.ciphersuite;
        let client = mls_store
            .find_client(&user_id.to_string(), &cs)
            .map_err(|e| match e {
                MlsStoreError::MlsClientNotFound => KeyPackageError::MlsClientNotFound,
            })?;

        let (key_packages, _expiration) = client.new_key_packages(1, Disclosure::Full).await?;
        let key_package = key_packages
            .first()
            .ok_or(KeyPackageError::FailedToGenerateKeyPackage)?;
        Ok(key_package.mls_encode_to_vec()?)
    }
}

#[derive(Debug, thiserror::Error)]
pub enum MlsServiceError {
    #[error("Mls store not found")]
    MlsStoreNotFound,
    #[error("Mls store error: {0}")]
    MlsStoreError(#[from] MlsStoreError),
    #[error("No group info in commit bundle")]
    NoGroupInfo,
    #[error("Domain error: {0}")]
    DomainError(#[from] meet_identifiers::ProtonMeetIdError),
    #[error("Mls trait error: {0}")]
    MlsTraitError(#[from] mls_trait::MlsError),
    #[error("Mls types error: {0}")]
    MlsTypesError(#[from] mls_types::MlsTypesError),
    #[error("Esdicawt spec error: {0}")]
    EsdicawtSpecError(#[from] proton_claims::reexports::spec::EsdicawtSpecError),
    #[error("No extra payload in sd cwt payload")]
    NoExtraPayload,
    #[error("Failed to convert mls_types to mls_spec: {0}")]
    MlsTypesToSpecError(#[from] mls_spec::MlsSpecError),
    #[error("Failed to encode mls_types: {0}")]
    MlsTypesEncodeError(#[from] mls_rs_codec::Error),
    #[error("No ratchet tree in commit bundle")]
    NoRatchetTree,
    #[error("Failed to convert ratchet tree option")]
    RatchetTreeOptionError,
    #[error("Failed to join group via external commit: {0}")]
    FailedToJoinGroupViaExternalCommit(mls_trait::MlsError),
    #[error("Failed to convert welcome message")]
    FailedToConvertWelcomeMessage(std::convert::Infallible),
    #[error("Mls group not found")]
    MlsGroupNotFound,
}

#[cfg(not(target_family = "wasm"))]
#[cfg(test)]
mod tests {
    use std::{collections::HashMap, sync::Arc};

    use cose_key_thumbprint::CoseKeyThumbprint;
    use ed25519_dalek::pkcs8::{DecodePrivateKey, DecodePublicKey};
    use identity::{Ed25519Issuer, IdentityResult, ProtonMeetIdentity, SdCwt};
    use meet_type::fanout::MlsWelcomeInfo;
    use mls_spec::{
        drafts::ratchet_tree_options::RatchetTreeOption, group::welcome::Welcome,
        messages::MlsMessageContent,
    };
    use mls_trait::{types::ReceivedMessage, MlsClientTrait, MlsGroupTrait};
    use proton_claims::{
        reexports::{cose_key_set::CoseKeySet, Issuer, IssuerParams, SpiceOidcClaims},
        ClientType, MimiProvider, ProtonMeetClaims,
    };
    use proton_meet_mls::{kv::MemKv, MlsClient, MlsClientConfig};
    use tokio::sync::RwLock;
    use uuid::Uuid;

    use super::MlsService;
    use crate::{
        domain::user::models::{meeting_link_name::MeetingLinkName, UserId},
        infra::crypto_client::derive_external_psk,
        infra::mimi_subject_parser::ANONYMOUS_USER_IDENTIFIER,
    };

    #[test]
    fn generate_unique_group_id_keeps_base_and_appends_uuid() {
        let base = "my-meeting-room";
        let id = MlsService::generate_unique_group_id(base);
        assert!(
            id.starts_with(&format!("{base}_")),
            "expected prefix {base}_, got {id}"
        );
        let suffix = id
            .strip_prefix(&format!("{base}_"))
            .expect("suffix after base_");
        assert!(
            Uuid::parse_str(suffix).is_ok(),
            "suffix should be a valid UUID: {suffix}"
        );
    }

    #[test]
    fn generate_unique_group_id_produces_distinct_values() {
        let a = MlsService::generate_unique_group_id("same-base");
        let b = MlsService::generate_unique_group_id("same-base");
        assert_ne!(a, b);
    }

    #[tokio::test]
    async fn convert_mls_spec_and_types_roundtrip_on_group_info() {
        let meeting_link_name = MeetingLinkName::from("unit-mls-convert-roundtrip");
        let mut client =
            create_initialized_client("host-convert@proton.me", true, "unit-mls-convert-roundtrip")
                .await;
        let psk_id = mls_types::ExternalPskId(meeting_link_name.as_str().as_bytes().to_vec());
        let psk_value = derive_external_psk("unit-convert-password", meeting_link_name.as_str())
            .expect("external PSK should be derived");
        client
            .insert_external_psk(psk_id, psk_value)
            .await
            .expect("external PSK should be inserted");

        let identifier = client
            .sd_cwt_mut()
            .expect("sd-cwt should be initialized")
            .user_id()
            .expect("sd-cwt should expose user id");
        let user_id = UserId::new(identifier.to_string());

        let config = MlsClientConfig::default();
        let mut clients_by_suite = HashMap::new();
        clients_by_suite.insert(config.ciphersuite, client);

        let mls_store = Arc::new(RwLock::new(proton_meet_mls::MlsStore {
            clients: HashMap::from([(user_id.to_string(), clients_by_suite)]),
            group_map: HashMap::new(),
            config,
        }));
        let service = MlsService::new(mls_store);

        let (group_info_spec, _) = service
            .create_mls_group(&meeting_link_name, &user_id, None)
            .await
            .expect("group creation should succeed");

        let types_msg = MlsService::convert_mls_spec_to_types(&group_info_spec)
            .expect("spec -> types should succeed");
        assert!(types_msg.as_group_info().is_some());

        let spec_again = MlsService::convert_mls_types_to_spec(&types_msg)
            .expect("types -> spec should succeed");
        assert!(matches!(
            spec_again.content,
            MlsMessageContent::GroupInfo(_)
        ));
    }

    #[tokio::test]
    async fn join_group_via_external_commit_joins_guest() {
        let meeting_link_name = MeetingLinkName::from("unit-join-external-commit");
        let mut host_client =
            create_initialized_client("host-join@proton.me", true, "unit-join-external-commit")
                .await;
        let psk_id = mls_types::ExternalPskId(meeting_link_name.as_str().as_bytes().to_vec());
        let psk_value = derive_external_psk("unit-join-password", meeting_link_name.as_str())
            .expect("external PSK should be derived");
        host_client
            .insert_external_psk(psk_id.clone(), psk_value.clone())
            .await
            .expect("host external PSK should be inserted");

        let host_user_id = UserId::new(
            host_client
                .sd_cwt_mut()
                .expect("sd-cwt should be initialized")
                .user_id()
                .expect("sd-cwt should expose user id")
                .to_string(),
        );

        let mut guest_client =
            create_initialized_client("guest-join@proton.me", false, "unit-join-external-commit")
                .await;
        guest_client
            .insert_external_psk(psk_id, psk_value)
            .await
            .expect("guest external PSK should be inserted");
        let guest_user_id = UserId::new(
            guest_client
                .sd_cwt_mut()
                .expect("sd-cwt should be initialized")
                .user_id()
                .expect("sd-cwt should expose user id")
                .to_string(),
        );

        let config = MlsClientConfig::default();
        let cs = config.ciphersuite;
        let mut host_map = HashMap::new();
        host_map.insert(cs, host_client);
        let mut guest_map = HashMap::new();
        guest_map.insert(cs, guest_client);

        let mls_store = Arc::new(RwLock::new(proton_meet_mls::MlsStore {
            clients: HashMap::from([
                (host_user_id.to_string(), host_map),
                (guest_user_id.to_string(), guest_map),
            ]),
            group_map: HashMap::new(),
            config,
        }));
        let service = MlsService::new(mls_store.clone());

        let (group_info_msg, ratchet_tree_option) = service
            .create_mls_group(&meeting_link_name, &host_user_id, None)
            .await
            .expect("host should create group");

        let host_group = {
            let store = mls_store.read().await;
            store
                .group_map
                .get(meeting_link_name.as_str())
                .cloned()
                .expect("host group should be in store after create_mls_group")
        };
        let epoch_before = *host_group.read().await.epoch();

        let group_info = match group_info_msg.content {
            MlsMessageContent::GroupInfo(gi) => gi,
            other => panic!("expected GroupInfo from create_mls_group, got {other:?}"),
        };

        let (_gi_out, _tree_out, commit_info) = service
            .join_group_via_external_commit(
                &meeting_link_name,
                &guest_user_id,
                group_info,
                ratchet_tree_option,
            )
            .await
            .expect("guest should join via external commit");

        assert_eq!(
            commit_info.room_id,
            meeting_link_name.as_str().as_bytes().to_vec()
        );

        let commit_types = MlsService::convert_mls_spec_to_types(&commit_info.commit)
            .expect("guest commit spec -> types should succeed");
        let (received_message, _) = host_group
            .write()
            .await
            .decrypt_message(commit_types)
            .await
            .expect("host should decrypt guest external-join commit");
        assert!(
            matches!(received_message, ReceivedMessage::Commit { .. }),
            "host should observe a Commit after processing external join, got {received_message:?}"
        );

        let epoch_after = *host_group.read().await.epoch();
        assert_eq!(
            epoch_after,
            epoch_before + 1,
            "host epoch should advance by one after processing external join commit"
        );
    }

    /// Guest uses GroupInfo + ratchet tree to build an unsigned external Add proposal
    /// (unlike `join_group_via_external_commit`, which returns a full commit bundle).
    #[tokio::test]
    async fn create_proposal_to_join_group_produces_add_proposal_message() {
        let meeting_link_name = MeetingLinkName::from("unit-proposal-join");
        let mut host_client =
            create_initialized_client("host-proposal@proton.me", true, "unit-proposal-join").await;
        let psk_id = mls_types::ExternalPskId(meeting_link_name.as_str().as_bytes().to_vec());
        let psk_value = derive_external_psk("unit-proposal-psk", meeting_link_name.as_str())
            .expect("external PSK should be derived");
        host_client
            .insert_external_psk(psk_id.clone(), psk_value.clone())
            .await
            .expect("host external PSK should be inserted");

        let host_user_id = UserId::new(
            host_client
                .sd_cwt_mut()
                .expect("sd-cwt should be initialized")
                .user_id()
                .expect("sd-cwt should expose user id")
                .to_string(),
        );

        let mut guest_client =
            create_initialized_client("guest-proposal@proton.me", false, "unit-proposal-join")
                .await;
        guest_client
            .insert_external_psk(psk_id, psk_value)
            .await
            .expect("guest external PSK should be inserted");
        let guest_user_id = UserId::new(
            guest_client
                .sd_cwt_mut()
                .expect("sd-cwt should be initialized")
                .user_id()
                .expect("sd-cwt should expose user id")
                .to_string(),
        );

        let config = MlsClientConfig::default();
        let cs = config.ciphersuite;
        let mut host_map = HashMap::new();
        host_map.insert(cs, host_client);
        let mut guest_map = HashMap::new();
        guest_map.insert(cs, guest_client);

        let mls_store = Arc::new(RwLock::new(proton_meet_mls::MlsStore {
            clients: HashMap::from([
                (host_user_id.to_string(), host_map),
                (guest_user_id.to_string(), guest_map),
            ]),
            group_map: HashMap::new(),
            config,
        }));
        let service = MlsService::new(mls_store);

        let (group_info_msg, ratchet_tree_option) = service
            .create_mls_group(&meeting_link_name, &host_user_id, None)
            .await
            .expect("host should create group");

        let group_info = match group_info_msg.content {
            MlsMessageContent::GroupInfo(gi) => gi,
            other => panic!("expected GroupInfo from create_mls_group, got {other:?}"),
        };

        let proposal = service
            .create_proposal_to_join_group(&guest_user_id, group_info, ratchet_tree_option)
            .await
            .expect("guest should build external add proposal");

        assert!(
            matches!(proposal.content, MlsMessageContent::MlsPublicMessage(_)),
            "expected MlsPublicMessage carrying external add proposal, got {:?}",
            proposal.content
        );

        MlsService::convert_mls_spec_to_types(&proposal)
            .expect("proposal spec -> types roundtrip should work");
    }

    /// Welcome-based join (proposal path): host commits guest's external Add proposal, guest joins with
    /// [`MlsWelcomeInfo`] + ratchet tree — mirrors production flow vs pure external commit self-add.
    #[tokio::test]
    async fn join_group_via_welcome_joins_guest_after_host_commits_proposal() {
        let meeting_link_name = MeetingLinkName::from("unit-join-via-welcome");
        let mut host_client =
            create_initialized_client("host-welcome@proton.me", true, "unit-join-via-welcome")
                .await;
        let psk_id = mls_types::ExternalPskId(meeting_link_name.as_str().as_bytes().to_vec());
        let psk_value = derive_external_psk("unit-welcome-psk", meeting_link_name.as_str())
            .expect("external PSK should be derived");
        host_client
            .insert_external_psk(psk_id.clone(), psk_value.clone())
            .await
            .expect("host external PSK should be inserted");

        let host_user_id = UserId::new(
            host_client
                .sd_cwt_mut()
                .expect("sd-cwt should be initialized")
                .user_id()
                .expect("sd-cwt should expose user id")
                .to_string(),
        );

        let mut guest_client =
            create_initialized_client("guest-welcome@proton.me", false, "unit-join-via-welcome")
                .await;
        guest_client
            .insert_external_psk(psk_id, psk_value)
            .await
            .expect("guest external PSK should be inserted");
        let guest_user_id = UserId::new(
            guest_client
                .sd_cwt_mut()
                .expect("sd-cwt should be initialized")
                .user_id()
                .expect("sd-cwt should expose user id")
                .to_string(),
        );

        let config = MlsClientConfig::default();
        let cs = config.ciphersuite;
        let mut host_map = HashMap::new();
        host_map.insert(cs, host_client);
        let mut guest_map = HashMap::new();
        guest_map.insert(cs, guest_client);

        let mls_store = Arc::new(RwLock::new(proton_meet_mls::MlsStore {
            clients: HashMap::from([
                (host_user_id.to_string(), host_map),
                (guest_user_id.to_string(), guest_map),
            ]),
            group_map: HashMap::new(),
            config,
        }));
        let service = MlsService::new(mls_store.clone());

        let (group_info_msg, ratchet_tree_option_initial) = service
            .create_mls_group(&meeting_link_name, &host_user_id, None)
            .await
            .expect("host should create group");

        let host_group = {
            let store = mls_store.read().await;
            store
                .group_map
                .get(meeting_link_name.as_str())
                .cloned()
                .expect("host group should be in store after create_mls_group")
        };
        let initial_epoch = *host_group.read().await.epoch();

        let group_info = match group_info_msg.content {
            MlsMessageContent::GroupInfo(gi) => gi,
            other => panic!("expected GroupInfo from create_mls_group, got {other:?}"),
        };

        let proposal_spec = service
            .create_proposal_to_join_group(
                &guest_user_id,
                group_info,
                ratchet_tree_option_initial.clone(),
            )
            .await
            .expect("guest should build external add proposal");

        let proposal_types = MlsService::convert_mls_spec_to_types(&proposal_spec)
            .expect("proposal spec -> types should succeed");

        let commit_bundle = {
            let mut group_write = host_group.write().await;
            let (received, _) = group_write
                .decrypt_message(proposal_types)
                .await
                .expect("host should decrypt guest add proposal");
            assert!(
                matches!(received, ReceivedMessage::Proposal),
                "host should observe a Proposal, got {received:?}"
            );

            let (bundle, _) = group_write
                .new_commit(vec![])
                .await
                .expect("host should commit pending proposal");
            group_write
                .merge_pending_commit()
                .await
                .expect("host should merge commit");
            bundle
        };

        assert_eq!(host_group.read().await.roster().count(), 2);
        let epoch_after_commit = *host_group.read().await.epoch();
        assert_eq!(epoch_after_commit, initial_epoch + 1);

        let welcome_mls = commit_bundle
            .welcome
            .expect("commit should include Welcome for the new member");
        let ratchet_tree_option: RatchetTreeOption = commit_bundle
            .ratchet_tree
            .expect("commit should include ratchet tree")
            .try_into()
            .expect("ratchet tree types -> RatchetTreeOption");

        let welcome_spec: Welcome = welcome_mls
            .try_into()
            .expect("welcome types -> mls_spec Welcome");

        let welcome_info = MlsWelcomeInfo {
            room_id: meeting_link_name.as_str().as_bytes().to_vec(),
            welcome: welcome_spec,
            ratchet_tree: ratchet_tree_option.clone(),
        };

        service
            .join_group_via_welcome(&guest_user_id, &meeting_link_name, welcome_info)
            .await
            .expect("guest should join via Welcome");

        let guest_group_entry = {
            let store = mls_store.read().await;
            store
                .group_map
                .get(meeting_link_name.as_str())
                .cloned()
                .expect("guest group should be stored after join_group_via_welcome")
        };

        assert_eq!(guest_group_entry.read().await.roster().count(), 2);
        assert_eq!(
            *guest_group_entry.read().await.epoch(),
            epoch_after_commit,
            "guest epoch should match host after welcome join"
        );
    }

    #[tokio::test]
    async fn create_mls_group_creates_bundle_and_stores_group() {
        let meeting_link_name = MeetingLinkName::from("unit-create-mls-group");
        let mut client =
            create_initialized_client("host-user@proton.me", true, "unit-create-mls-group").await;
        let psk_id = mls_types::ExternalPskId(meeting_link_name.as_str().as_bytes().to_vec());
        let psk_value = derive_external_psk("unit-meeting-password", meeting_link_name.as_str())
            .expect("external PSK should be derived");
        client
            .insert_external_psk(psk_id, psk_value)
            .await
            .expect("external PSK should be inserted");

        let identifier = client
            .sd_cwt_mut()
            .expect("sd-cwt should be initialized")
            .user_id()
            .expect("sd-cwt should expose user id");
        let user_id = UserId::new(identifier.to_string());

        let config = MlsClientConfig::default();
        let mut clients_by_suite = HashMap::new();
        clients_by_suite.insert(config.ciphersuite, client);

        let mls_store = Arc::new(RwLock::new(proton_meet_mls::MlsStore {
            clients: HashMap::from([(user_id.to_string(), clients_by_suite)]),
            group_map: HashMap::new(),
            config,
        }));
        let service = MlsService::new(mls_store.clone());

        let _ = service
            .create_mls_group(&meeting_link_name, &user_id, None)
            .await
            .expect("group creation should succeed");

        let stored_group = {
            let store = mls_store.read().await;
            store
                .group_map
                .get(meeting_link_name.as_str())
                .cloned()
                .expect("group should be saved in store")
        };
        assert_eq!(stored_group.read().await.roster().count(), 1);
    }

    async fn create_initialized_client(
        email: &str,
        is_host: bool,
        meeting_id_for_claims: &str,
    ) -> MlsClient<MemKv> {
        let (client, _) = MlsClient::new(MemKv::new(), MlsClientConfig::default())
            .await
            .expect("client should be created");
        let holder_confirmation_key_pem = client
            .get_holder_confirmation_key_pem()
            .expect("holder confirmation key should be generated");
        let (sd_cwt, issuer_signing_key) = mock_sdcwt_issuance(
            &holder_confirmation_key_pem,
            meeting_id_for_claims,
            email,
            proton_claims::Role::User,
            is_host,
        )
        .expect("sd-cwt issuance should succeed");
        let cks = CoseKeySet::new(&issuer_signing_key).expect("issuer CKS should be created");

        client
            .initialize(MemKv::new(), sd_cwt, &cks, &cks)
            .expect("client should initialize with issued identity")
    }

    fn mock_sdcwt_issuance(
        holder_confirmation_key_pem: &str,
        meeting_link_name: &str,
        email: &str,
        organization_role: proton_claims::Role,
        is_host: bool,
    ) -> IdentityResult<(SdCwt, ed25519_dalek::SigningKey)> {
        let payload = ProtonMeetClaims {
            meeting_id: meeting_link_name.to_owned(),
            uuid: Uuid::new_v4().into_bytes(),
            oidc_claims: SpiceOidcClaims::default(),
            role: organization_role,
            mimi_provider: MimiProvider::ProtonAg,
            is_from_server: false,
            is_host,
            client_type: ClientType::Guest,
        };

        let issuer_sk = "-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEIDR7w12ON3uzdZd8g6HIGOiGe/ozjj0rpBKs1VTVCyCM
-----END PRIVATE KEY-----";
        let issuer_signing_key = ed25519_dalek::SigningKey::from_pkcs8_pem(issuer_sk).unwrap();
        let issuer = Ed25519Issuer::new(issuer_signing_key.clone());

        let holder_verifying_key =
            ed25519_dalek::VerifyingKey::from_public_key_pem(holder_confirmation_key_pem).unwrap();
        let holder_confirmation_key = (&holder_verifying_key).try_into().unwrap();

        let sub = generate_mimi_subject(
            "meet.proton.me",
            &holder_verifying_key,
            Some(email.to_string()),
            None,
        )?;
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
            (Some(email), _) => email,
            (None, Some(name)) => name,
            (None, None) => ANONYMOUS_USER_IDENTIFIER.to_string(),
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
}
