#![no_main]
//! Fuzz the legacy JSON chat-message parser used by the `parse_chat_message` FRB
//! API (meet-chat/src/legacy_wire.rs:18). This `serde_json::from_str` runs on a
//! client/server-supplied JSON string crossing the Flutter↔Rust bridge.
//!
//! Oracles:
//!  1. Parsing never panics.
//!  2. Round-trip: any successfully parsed message must re-serialize and
//!     re-parse to a byte-identical JSON encoding (serde round-trip stability).
use libfuzzer_sys::fuzz_target;
use proton_meet_chat::legacy_wire::MeetChatMessage;

fuzz_target!(|data: &[u8]| {
    let Ok(s) = std::str::from_utf8(data) else {
        return;
    };

    if let Ok(msg) = MeetChatMessage::from_json(s) {
        let json = serde_json::to_string(&msg).expect("serializing a parsed message must succeed");
        let reparsed = MeetChatMessage::from_json(&json)
            .expect("re-parsing a serialized message must succeed");
        let json2 = serde_json::to_string(&reparsed).expect("re-serialize must succeed");
        assert_eq!(json, json2, "JSON round-trip mismatch: {json} vs {json2}");
    }
});
