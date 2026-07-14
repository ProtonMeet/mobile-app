//! Static test fixtures (binary blobs, canned TLS payloads, etc.).

/// TLS-encoded `mls_spec::messages::MlsMessage` (GroupInfo) for [`HttpClient`](crate::domain::user::ports::HttpClient) port tests.
///
/// # How this file was generated
///
/// 1. `MlsService::create_mls_group` on a one-member test group (`mls_service` test helper:
///    `create_initialized_client` + external PSK for meeting link `http-client-port-fixture`).
/// 2. Take the returned `MlsMessage` (group info) and serialize with `mls_spec::Serializable::to_tls_bytes()`.
/// 3. Write the bytes to `http_client_group_info_fixture.bin`.
///
/// Regenerate after MLS/ciphersuite changes if port tests fail to parse the fixture.
pub const HTTP_CLIENT_GROUP_INFO_TLS: &[u8] = include_bytes!("http_client_group_info_fixture.bin");
