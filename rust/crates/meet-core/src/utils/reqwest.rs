#[cfg(feature = "insecure-tls")]
pub fn dev_reqwest_builder() -> reqwest::ClientBuilder {
    // OK for local/dev only. Don't use in production.
    #[cfg(not(target_family = "wasm"))]
    return reqwest::Client::builder()
        .danger_accept_invalid_certs(true)
        .danger_accept_invalid_hostnames(true)
        .use_rustls_tls();

    #[cfg(target_family = "wasm")]
    return reqwest::Client::builder();
}

#[cfg(all(
    feature = "insecure-tls",
    not(target_family = "wasm"),
    not(target_os = "ios")
))]
pub fn dev_rustls_client_config() -> rustls::ClientConfig {
    rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(std::sync::Arc::new(InsecureCertVerifier))
        .with_no_client_auth()
}

#[cfg(all(
    feature = "insecure-tls",
    not(target_family = "wasm"),
    not(target_os = "ios")
))]
#[derive(Debug)]
struct InsecureCertVerifier;

#[cfg(all(
    feature = "insecure-tls",
    not(target_family = "wasm"),
    not(target_os = "ios")
))]
impl rustls::client::danger::ServerCertVerifier for InsecureCertVerifier {
    fn verify_server_cert(
        &self,
        _end_entity: &rustls::pki_types::CertificateDer<'_>,
        _intermediates: &[rustls::pki_types::CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp_response: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }
    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &rustls::pki_types::CertificateDer<'_>,
        _dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        Ok(rustls::client::danger::HandshakeSignatureValid::assertion())
    }
    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        vec![
            rustls::SignatureScheme::RSA_PKCS1_SHA256,
            rustls::SignatureScheme::ECDSA_NISTP256_SHA256,
            rustls::SignatureScheme::ED25519,
        ]
    }
}
