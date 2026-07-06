//! Mint structurally-valid seed inputs for the fuzz corpora.
//!
//! Random byte fuzzing rarely produces a valid CBOR `MimiContent`, so the
//! `mimi_content` target would otherwise only ever exercise the outer CBOR
//! reject path. This helper builds real messages with `build_mimi_message` and
//! writes their CBOR encodings into `corpus/mimi_content/`, plus a few seeds for
//! the text/JSON targets. Run with a normal toolchain (no sanitizer):
//!
//!     cargo run --bin gen_seeds
//!
//! (Re)generated seeds are git-ignored along with the rest of `corpus/`.
use std::fs;
use std::path::Path;

use mimi_content::MimiContentSerialize;
use proton_meet_chat::{build_mimi_message, meet_room_uri, ChatComposeRequest, MessageId};

fn write_seed(target: &str, name: &str, bytes: &[u8]) {
    let dir = Path::new("corpus").join(target);
    fs::create_dir_all(&dir).expect("create corpus dir");
    let path = dir.join(name);
    fs::write(&path, bytes).expect("write seed");
    println!("wrote {} ({} bytes)", path.display(), bytes.len());
}

fn main() {
    let sender = "mimi://meet.proton.me/d/alice@proton.me/device1";
    let room = meet_room_uri("FUZZROOM00");
    let ts = 1_700_000_000_000u64;
    let target =
        MessageId::from_hex("0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20")
            .expect("valid hex");

    // 1. A plain text message.
    let (msg, _) = build_mimi_message(
        &ChatComposeRequest::Message {
            text: "hello fuzz".to_string(),
            reply_to: None,
        },
        sender,
        &room,
        ts,
    )
    .expect("build text message");
    write_seed(
        "mimi_content",
        "text_message",
        &msg.to_cbor_bytes().expect("encode text message"),
    );

    // 2. A reaction (add).
    let (react, _) = build_mimi_message(
        &ChatComposeRequest::React {
            target,
            emoji: "👍".to_string(),
        },
        sender,
        &room,
        ts + 1,
    )
    .expect("build reaction");
    write_seed(
        "mimi_content",
        "reaction_add",
        &react.to_cbor_bytes().expect("encode reaction"),
    );

    // 3. A reaction removal (unreact).
    let (unreact, _) = build_mimi_message(
        &ChatComposeRequest::Unreact {
            target,
            replaces: target,
        },
        sender,
        &room,
        ts + 2,
    )
    .expect("build unreact");
    write_seed(
        "mimi_content",
        "reaction_remove",
        &unreact.to_cbor_bytes().expect("encode unreact"),
    );

    // Text/JSON target seeds.
    write_seed(
        "chat_envelope",
        "json_envelope",
        br#"{"type":"message","id":"u","message":"abc","timestamp":1}"#,
    );
    write_seed("chat_envelope", "raw_bytes", &[0x01, 0x02, 0x03]);
    write_seed(
        "legacy_chat_json",
        "valid",
        br#"{"id":"1","timestamp":1000,"identity":"u","name":"n","seen":false,"message":"hi"}"#,
    );
    write_seed(
        "message_id_hex",
        "valid",
        b"0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
    );

    println!("done");
}
