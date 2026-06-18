use serde::{Deserialize, Serialize};

use crate::error::ChatError;

/// Legacy wire-format chat message (JSON) used by `parse_chat_message` FRB API.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MeetChatMessage {
    pub id: String,
    /// Unix timestamp in milliseconds
    pub timestamp: i64,
    pub identity: String,
    pub name: String,
    pub seen: bool,
    pub message: String,
}

impl MeetChatMessage {
    pub fn from_json(json: &str) -> Result<Self, ChatError> {
        serde_json::from_str(json).map_err(ChatError::SerializationError)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn from_json_roundtrip() {
        let json =
            r#"{"id":"1","timestamp":1000,"identity":"u","name":"n","seen":false,"message":"hi"}"#;
        let msg = MeetChatMessage::from_json(json).unwrap();
        assert_eq!(msg.message, "hi");
    }
}
