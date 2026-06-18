pub mod compose;
pub mod decode;
pub mod envelope;
pub mod error;
pub mod mimi;
pub mod types;

#[cfg(feature = "wasm")]
pub mod wasm_types;

#[cfg(feature = "legacy-wire")]
pub mod legacy_wire;

pub use compose::compose_local_echo;
pub use decode::{decode_legacy_plaintext, decode_mimi_content, legacy_message_id};
pub use envelope::extract_mls_ciphertext;
pub use error::ChatError;
pub use mimi::{
    build_mimi_message, compute_message_id, compute_message_id_from_content, domain_id_from_mimi,
    meet_room_uri, mimi_id_from_domain, parse_mimi_content, LEGACY_MEET_MEDIA, MIMI_CONTENT_MEDIA,
};
pub use types::{
    ChatComposeRequest, ChatIncomingEvent, ChatOutgoingPacket, ChatProtocol, MessageId,
    ParticipantId, ReplyTarget,
};

#[cfg(feature = "wasm")]
pub use wasm_types::{ChatComposeResult, ChatEventKind, ChatIncomingEventInfo, ChatProtocolInfo};
