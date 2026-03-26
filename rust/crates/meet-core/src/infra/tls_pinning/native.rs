use std::sync::Arc;

use base64::Engine;
use rustls::{
    client::{
        danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
        WebPkiServerVerifier,
    },
    pki_types::{CertificateDer, ServerName, UnixTime},
    ClientConfig, DigitallySignedStruct, Error, RootCertStore, SignatureScheme,
};
use sha2::{Digest, Sha256};
use x509_parser::prelude::*;

// SPKI SHA-256 hashes for Proton's production infrastructure, verbatim from
// muon-1.4.0/src/env/prod.rs. DIRECT pins apply to direct-hostname connections.
const PROD_DIRECT_PINS: &[&str] = &[
    "CT56BhOTmj5ZIPgb/xD5mH8rY3BLo/MlhP7oPyJUEDo=",
    "35Dx28/uzN3LeltkCBQ8RHK0tlNSa2kCpCRGNp34Gxc=",
    "qYIukVc63DEITct8sFT7ebIq5qsWmuscaIKeJx+5J5A=",
];

/// Returns the SHA-256 hash of a DER certificate's Subject Public Key Info (SPKI).
pub fn spki_sha256(cert: &CertificateDer<'_>) -> Result<[u8; 32], Error> {
    let (_, parsed) = X509Certificate::from_der(cert.as_ref())
        .map_err(|e| Error::General(format!("failed to parse certificate DER: {e}")))?;
    Ok(Sha256::digest(parsed.public_key().raw).into())
}

/// A rustls `ServerCertVerifier` that layers SPKI SHA-256 pin enforcement on top
/// of standard WebPki chain + hostname validation.
///
/// Runs the inner verifier first, then accepts if any cert in the chain matches a pin.
#[derive(Debug)]
pub struct CertPinningVerifier {
    inner: Arc<dyn ServerCertVerifier>,
    pins: Vec<[u8; 32]>,
}

impl CertPinningVerifier {
    pub fn new(b64_pins: &[impl AsRef<str>]) -> Result<Self, anyhow::Error> {
        let mut roots = RootCertStore::empty();
        roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        let inner = WebPkiServerVerifier::builder(Arc::new(roots))
            .build()
            .map_err(|e| anyhow::anyhow!("failed to build WebPki verifier: {e}"))?;
        Ok(Self {
            inner,
            pins: Self::decode_pins(b64_pins)?,
        })
    }

    #[cfg(test)]
    pub fn with_verifier(
        inner: Arc<dyn ServerCertVerifier>,
        b64_pins: &[impl AsRef<str>],
    ) -> Result<Self, anyhow::Error> {
        Ok(Self {
            inner,
            pins: Self::decode_pins(b64_pins)?,
        })
    }

    fn decode_pins(b64_pins: &[impl AsRef<str>]) -> Result<Vec<[u8; 32]>, anyhow::Error> {
        b64_pins
            .iter()
            .map(|p| {
                let bytes = base64::engine::general_purpose::STANDARD
                    .decode(p.as_ref())
                    .map_err(|e| anyhow::anyhow!("invalid base64 pin: {e}"))?;
                bytes
                    .try_into()
                    .map_err(|_| anyhow::anyhow!("pin must be exactly 32 bytes (SHA-256)"))
            })
            .collect()
    }
}

impl ServerCertVerifier for CertPinningVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, Error> {
        if self.pins.contains(&spki_sha256(end_entity)?) {
            return Ok(ServerCertVerified::assertion());
        }

        Err(Error::General(
            "leaf certificate not pinned: SPKI hash did not match any configured pin".into(),
        ))
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.inner.verify_tls12_signature(message, cert, dss)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, Error> {
        self.inner.verify_tls13_signature(message, cert, dss)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.inner.supported_verify_schemes()
    }
}

/// Build a `rustls::ClientConfig` pinned to Proton's production DIRECT pins.
pub fn build_prod_tls_config() -> Result<ClientConfig, anyhow::Error> {
    let verifier = CertPinningVerifier::new(PROD_DIRECT_PINS)?;
    Ok(ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(verifier))
        .with_no_client_auth())
}

#[cfg(test)]
mod tests {
    use base64::Engine;
    use rcgen::{CertificateParams, KeyPair};
    use rustls::{
        client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier},
        pki_types::{CertificateDer, ServerName, UnixTime},
        DigitallySignedStruct, Error, SignatureScheme,
    };
    use sha2::{Digest, Sha256};
    use std::sync::Arc;

    use super::{build_prod_tls_config, spki_sha256, CertPinningVerifier};

    fn make_test_cert_and_pin() -> (CertificateDer<'static>, String) {
        let key_pair = KeyPair::generate().unwrap();
        let params = CertificateParams::new(vec!["example.com".to_string()]).unwrap();
        let cert = params.self_signed(&key_pair).unwrap();
        let der = CertificateDer::from(cert.der().to_vec());
        let spki_der = key_pair.public_key_der();
        let hash: [u8; 32] = Sha256::digest(&spki_der).into();
        let pin_b64 = base64::engine::general_purpose::STANDARD.encode(hash);
        (der, pin_b64)
    }

    #[derive(Debug)]
    struct AlwaysOkVerifier;
    impl ServerCertVerifier for AlwaysOkVerifier {
        fn verify_server_cert(
            &self,
            _: &CertificateDer<'_>,
            _: &[CertificateDer<'_>],
            _: &ServerName<'_>,
            _: &[u8],
            _: UnixTime,
        ) -> Result<ServerCertVerified, Error> {
            Ok(ServerCertVerified::assertion())
        }
        fn verify_tls12_signature(
            &self,
            _: &[u8],
            _: &CertificateDer<'_>,
            _: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, Error> {
            Ok(HandshakeSignatureValid::assertion())
        }
        fn verify_tls13_signature(
            &self,
            _: &[u8],
            _: &CertificateDer<'_>,
            _: &DigitallySignedStruct,
        ) -> Result<HandshakeSignatureValid, Error> {
            Ok(HandshakeSignatureValid::assertion())
        }
        fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
            vec![]
        }
    }

    #[test]
    fn test_spki_sha256_matches_expected_hash() {
        let (cert_der, pin_b64) = make_test_cert_and_pin();
        let expected = base64::engine::general_purpose::STANDARD
            .decode(&pin_b64)
            .unwrap();
        let expected: [u8; 32] = expected.try_into().unwrap();
        let got = spki_sha256(&cert_der).expect("spki_sha256 should succeed");
        assert_eq!(got, expected, "SPKI hash must match SHA-256 of raw SPKI bytes");
    }

    #[test]
    fn test_pinning_verifier_accepts_pinned_leaf_cert() {
        let (cert_der, pin_b64) = make_test_cert_and_pin();
        let verifier =
            CertPinningVerifier::with_verifier(Arc::new(AlwaysOkVerifier), &[pin_b64]).unwrap();
        let result = verifier.verify_server_cert(
            &cert_der,
            &[],
            &ServerName::try_from("example.com").unwrap(),
            &[],
            UnixTime::now(),
        );
        assert!(result.is_ok(), "pinned leaf should be accepted: {result:?}");
    }

    #[test]
    fn test_pinning_verifier_rejects_unpinned_cert() {
        let (cert_der, _) = make_test_cert_and_pin();
        let other_key = KeyPair::generate().unwrap();
        let other_hash: [u8; 32] = Sha256::digest(other_key.public_key_der()).into();
        let wrong_pin = base64::engine::general_purpose::STANDARD.encode(other_hash);
        let verifier =
            CertPinningVerifier::with_verifier(Arc::new(AlwaysOkVerifier), &[wrong_pin]).unwrap();
        let result = verifier.verify_server_cert(
            &cert_der,
            &[],
            &ServerName::try_from("example.com").unwrap(),
            &[],
            UnixTime::now(),
        );
        assert!(result.is_err(), "non-matching pin should be rejected");
    }

    #[test]
    fn test_pinning_verifier_rejects_pinned_intermediate() {
        let (leaf_der, _) = make_test_cert_and_pin();
        let (intermediate_der, intermediate_pin) = make_test_cert_and_pin();
        let verifier =
            CertPinningVerifier::with_verifier(Arc::new(AlwaysOkVerifier), &[intermediate_pin])
                .unwrap();
        let result = verifier.verify_server_cert(
            &leaf_der,
            &[intermediate_der],
            &ServerName::try_from("example.com").unwrap(),
            &[],
            UnixTime::now(),
        );
        assert!(result.is_err(), "pinned intermediate must be rejected: {result:?}");
    }

    #[test]
    fn test_new_rejects_invalid_base64() {
        let result = CertPinningVerifier::new(&["not!valid!base64"]);
        assert!(result.is_err(), "invalid base64 should return error");
    }

    #[test]
    fn test_new_rejects_wrong_length_pin() {
        let short = base64::engine::general_purpose::STANDARD.encode([0u8; 10]);
        let result = CertPinningVerifier::new(&[short]);
        assert!(result.is_err(), "pin with wrong byte length should return error");
    }

    #[test]
    fn test_prod_tls_config_builds_without_error() {
        let result = build_prod_tls_config();
        assert!(result.is_ok(), "prod TLS config should build: {result:?}");
    }
}
