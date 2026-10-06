#![no_main]
//! Fuzz the incoming-chat decode pipeline: CBOR MimiContent decode → high-level
//! event decode.
//!
//! `parse_mimi_content(&[u8])` (meet-chat/src/mimi.rs:188) CBOR-decodes an
//! attacker-controlled chat payload that arrives over the wire (the MLS
//! application message body), and `decode_mimi_content(..)` (decode.rs:130) then
//! walks the decoded structure to produce a `ChatIncomingEvent`. Both run on
//! untrusted bytes before the content is ever shown to the user, so a panic here
//! is a remotely-triggerable client crash (DoS).
//!
//! Property: neither the decoder nor the full extraction pipeline may panic on
//! any input. We additionally drive the pipeline with two different
//! sender/timestamp shapes to exercise the `received_at_ms` / id handling.
use libfuzzer_sys::fuzz_target;
use proton_meet_chat::{MessageId, ParticipantId, decode_mimi_content, parse_mimi_content};

fuzz_target!(|data: &[u8]| {
    let Ok(content) = parse_mimi_content(data) else {
        return;
    };

    let id = MessageId::from_bytes([0u8; 32]);

    // Full incoming-message decode must not panic for any decodable content.
    let _ = decode_mimi_content(&content, id, ParticipantId("fuzzer".to_string()), 0);
    // Edge values for the client-supplied fields the pipeline threads through.
    let _ = decode_mimi_content(&content, id, ParticipantId(String::new()), u64::MAX);
});
