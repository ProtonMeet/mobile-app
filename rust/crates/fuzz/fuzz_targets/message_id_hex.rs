#![no_main]
//! Fuzz the 32-byte message-id hex parser (meet-chat/src/types.rs:19).
//! `MessageId::from_hex` decodes a 64-char hex string into a `[u8; 32]`; it is
//! used to parse ids that originate from the wire / FFI boundary.
//!
//! Oracles:
//!  1. Never panics (no out-of-bounds in the chunked `from_str_radix` loop).
//!  2. Any accepted string is exactly 64 chars and round-trips: `from_hex(s)`
//!     then `to_hex()` re-parses to an equal `MessageId`.
use libfuzzer_sys::fuzz_target;
use proton_meet_chat::MessageId;

fuzz_target!(|data: &[u8]| {
    let Ok(s) = std::str::from_utf8(data) else {
        return;
    };

    if let Ok(id) = MessageId::from_hex(s) {
        assert_eq!(s.len(), 64, "accepted hex id not 64 chars: {s:?}");
        let hex = id.to_hex();
        assert_eq!(hex.len(), 64, "to_hex did not emit 64 chars: {hex:?}");
        let reparsed = MessageId::from_hex(&hex).expect("re-parsing canonical hex must succeed");
        assert_eq!(id, reparsed, "hex round-trip mismatch for {s:?}");
    }
});
