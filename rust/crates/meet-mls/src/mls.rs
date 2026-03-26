// use chat_identifiers::Domain;
// use mls_trait::{MlsClient, MlsClientConfig};
// use proton_claims::reexports::cose_key_set::CoseKeySet;

// use crate::kv::MemKv;

// #[derive(Debug, Clone)]
// pub struct Mls;

// impl Mls {
//     pub async fn new_client(
//         config: Option<MlsClientConfig>,
//         handle: &str,
//         email: &str,
//         organization: Option<String>,
//     ) -> MlsClient<MemKv> {
//         let kv = MemKv::new();

//         let client = MlsClient::new(kv.clone(), config.unwrap_or_default())
//             .await
//             .unwrap();
//         let domain = Domain::new_random();

//         let cnf = client.get_holder_confirmation_key_pem().unwrap();
//         let (sd_cwt, issuer_signing_key) = identity::mock_sdcwt_issuance(
//             &cnf,
//             &domain,
//             &handle.to_string().into(),
//             email.into(),
//             organization,
//             proton_claims::Role::User,
//         )
//         .unwrap();

//         let cks = CoseKeySet::new(&issuer_signing_key).unwrap();
//         let client = client.initialize(sd_cwt, &cks).unwrap();
//         client
//     }
// }
