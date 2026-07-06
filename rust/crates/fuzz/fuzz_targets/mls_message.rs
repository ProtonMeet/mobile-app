#![no_main]
//! Fuzz the TLS-encoded MLS message decoder — the untrusted-bytes entry point
//! that drives the create / join / remove / leave group operations.
//!
//! Every MLS operation the client performs starts by decoding an
//! `mls_spec::messages::MlsMessage` from attacker-influenced wire bytes (see
//! `MlsService::convert_mls_types_to_spec` / the http + ws receive paths, e.g.
//! `meet-core/src/service/mls_service.rs:226` and `infra/http_client.rs:337`):
//!   * a `Welcome`   → `join_group_via_welcome`
//!   * a `GroupInfo` → `create_mls_group` (out) / `join_group_via_external_commit` (in)
//!   * a `Commit` / `Proposal` (`MlsPublicMessage`) → remove / leave handling
//!
//! These are all `MlsMessageContent` variants, so decoding `MlsMessage` is the
//! shared, pure, crypto-free, stateless front door for all of them. A panic here
//! is a remotely-triggerable client crash (DoS) before any signature check.
//!
//! Oracles:
//!  1. Decoding never panics on arbitrary bytes.
//!  2. Re-encoding a decoded message never panics.
//!  3. Canonical-form stability: re-decoding the re-encoding succeeds and is a
//!     fixed point (encode∘decode is idempotent) — a divergence would indicate a
//!     non-canonical / ambiguous decode that two peers could interpret differently.
use libfuzzer_sys::fuzz_target;
use mls_spec::messages::MlsMessage;
use mls_spec::{Parsable, Serializable};

fuzz_target!(|data: &[u8]| {
    let Ok(msg) = MlsMessage::from_tls_bytes(data) else {
        return;
    };

    // Oracle 2: re-encoding a decoded message must not panic.
    let Ok(reencoded) = msg.to_tls_bytes() else {
        return;
    };

    // Oracle 3: the re-encoding must round-trip to a fixed point.
    let msg2 =
        MlsMessage::from_tls_bytes(&reencoded).expect("re-decoding a serialized MlsMessage failed");
    let reencoded2 = msg2
        .to_tls_bytes()
        .expect("re-encoding a re-decoded MlsMessage failed");
    assert_eq!(
        reencoded, reencoded2,
        "MLS message TLS re-encoding is not idempotent (non-canonical decode)"
    );
});
