#![no_main]
//! Fuzz the legacy chat envelope extractor.
//!
//! `extract_mls_ciphertext(&[u8])` (meet-chat/src/envelope.rs:3) is the first
//! thing run on an inbound chat frame: if it starts with `{` it is parsed as a
//! JSON envelope and the `message` field is decoded from Latin-1 back into raw
//! MLS ciphertext bytes; otherwise the bytes are passed through unchanged. It
//! runs on attacker-controlled input, so it must never panic.
//!
//! Oracles:
//!  1. Never panics.
//!  2. Non-`{`-prefixed input is returned byte-for-byte unchanged (pure passthrough).
//!  3. Any byte produced from the JSON path fits in a u8 (Latin-1 invariant) —
//!     enforced implicitly by the fact that it returns `Ok`.
use libfuzzer_sys::fuzz_target;
use proton_meet_chat::extract_mls_ciphertext;

fuzz_target!(|data: &[u8]| {
    if let Ok(out) = extract_mls_ciphertext(data)
        && data.first() != Some(&b'{')
    {
        assert_eq!(
            out, data,
            "non-JSON input must pass through unchanged: in={data:?} out={out:?}"
        );
    }
});
