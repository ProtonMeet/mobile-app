use base64::{prelude::BASE64_STANDARD, Engine};
use serde::{Deserialize, Serialize};

use crate::error::ChatError;

/// Represents a chat message with participant information and seen status
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
    pub fn new(
        id: String,
        timestamp: i64,
        identity: String,
        name: String,
        seen: bool,
        message: String,
    ) -> Self {
        Self {
            id,
            timestamp,
            identity,
            name,
            seen,
            message,
        }
    }

    /// Convert the message to base64-encoded JSON
    pub fn to_base64(&self) -> Result<String, ChatError> {
        let json = serde_json::to_string(self).map_err(ChatError::SerializationError)?;
        Ok(BASE64_STANDARD.encode(json.as_bytes()))
    }

    /// Decode a message from base64-encoded JSON
    pub fn from_base64(b64: &str) -> Result<Self, ChatError> {
        let bytes = BASE64_STANDARD
            .decode(b64)
            .map_err(|e| ChatError::InvalidDataFormat(format!("Invalid base64: {e}")))?;
        let json_str =
            String::from_utf8(bytes).map_err(|e| ChatError::Utf8ConversionError(e.to_string()))?;
        let message = serde_json::from_str(&json_str).map_err(ChatError::SerializationError)?;
        Ok(message)
    }

    pub fn from_json(json: &str) -> Result<Self, ChatError> {
        let message = serde_json::from_str(json).map_err(ChatError::SerializationError)?;
        Ok(message)
    }

    pub fn to_json(&self) -> Result<String, ChatError> {
        let json = serde_json::to_string(self).map_err(ChatError::SerializationError)?;
        Ok(json)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use uuid::Uuid;

    #[test]
    fn test_meet_chat_message_new() {
        let id = Uuid::new_v4().to_string();
        let timestamp = chrono::Utc::now().timestamp_millis();
        let identity = "participant123".to_string();
        let name = "John Doe".to_string();
        let seen = true;
        let message = "Hello, world!".to_string();

        let chat_message = MeetChatMessage::new(
            id.clone(),
            timestamp,
            identity.clone(),
            name.clone(),
            seen,
            message.clone(),
        );

        assert_eq!(chat_message.id, id);
        assert_eq!(chat_message.timestamp, timestamp);
        assert_eq!(chat_message.identity, identity);
        assert_eq!(chat_message.name, name);
        assert_eq!(chat_message.seen, seen);
        assert_eq!(chat_message.message, message);
    }

    #[test]
    fn test_meet_chat_message_clone() {
        let original = MeetChatMessage::new(
            Uuid::new_v4().to_string(),
            chrono::Utc::now().timestamp_millis(),
            "identity1".to_string(),
            "Alice".to_string(),
            false,
            "Test message".to_string(),
        );

        let cloned = original.clone();

        assert_eq!(original.id, cloned.id);
        assert_eq!(original.timestamp, cloned.timestamp);
        assert_eq!(original.identity, cloned.identity);
        assert_eq!(original.name, cloned.name);
        assert_eq!(original.seen, cloned.seen);
        assert_eq!(original.message, cloned.message);
    }

    #[test]
    fn test_meet_chat_message_seen_status() {
        let message_seen = MeetChatMessage::new(
            Uuid::new_v4().to_string(),
            Utc::now().timestamp_millis(),
            "user1".to_string(),
            "User One".to_string(),
            true,
            "Seen message".to_string(),
        );

        let message_unseen = MeetChatMessage::new(
            Uuid::new_v4().to_string(),
            Utc::now().timestamp_millis(),
            "user2".to_string(),
            "User Two".to_string(),
            false,
            "Unseen message".to_string(),
        );

        assert!(message_seen.seen);
        assert!(!message_unseen.seen);
    }

    #[test]
    fn test_to_base64_and_from_base64() {
        let original = MeetChatMessage::new(
            Uuid::new_v4().to_string(),
            Utc::now().timestamp_millis(),
            "participant123".to_string(),
            "John Doe".to_string(),
            true,
            "Hello, world!".to_string(),
        );

        // Encode to base64
        let base64_str = original.to_base64().expect("Failed to encode to base64");

        // Decode from base64
        let decoded =
            MeetChatMessage::from_base64(&base64_str).expect("Failed to decode from base64");

        // Verify all fields match
        assert_eq!(original.id, decoded.id);
        assert_eq!(original.timestamp, decoded.timestamp);
        assert_eq!(original.identity, decoded.identity);
        assert_eq!(original.name, decoded.name);
        assert_eq!(original.seen, decoded.seen);
        assert_eq!(original.message, decoded.message);
    }

    #[test]
    fn test_from_base64_invalid_base64() {
        let invalid_base64 = "This is not valid base64!@#$%";
        let result = MeetChatMessage::from_base64(invalid_base64);

        assert!(result.is_err());
        if let Err(ChatError::InvalidDataFormat(msg)) = result {
            assert!(msg.contains("Invalid base64"));
        } else {
            panic!("Expected InvalidDataFormat error");
        }
    }

    #[test]
    fn test_from_base64_invalid_json() {
        // Valid base64 but invalid JSON content
        let invalid_json_base64 = BASE64_STANDARD.encode(b"not a json object");
        let result = MeetChatMessage::from_base64(&invalid_json_base64);
        assert!(result.is_err());
        if let Err(ChatError::SerializationError(_msg)) = result {
        } else {
            panic!("Expected InvalidDataFormat error");
        }
    }

    #[test]
    fn test_from_base64_invalid_utf8() {
        // Valid base64 but invalid UTF-8 content
        let invalid_utf8 = vec![0xFF, 0xFE, 0xFD];
        let invalid_utf8_base64 = BASE64_STANDARD.encode(&invalid_utf8);
        let result = MeetChatMessage::from_base64(&invalid_utf8_base64);
        print!("{result:?}");

        assert!(result.is_err());
        if let Err(ChatError::Utf8ConversionError(msg)) = result {
            assert!(msg.contains("invalid utf-8"));
        } else {
            panic!("Expected InvalidDataFormat error");
        }
    }

    #[test]
    fn test_base64_with_special_characters() {
        let message_with_special_chars = MeetChatMessage::new(
            Uuid::new_v4().to_string(),
            Utc::now().timestamp_millis(),
            "user@example.com".to_string(),
            "José García 🎉".to_string(),
            false,
            "Hello! 你好! مرحبا! 🚀🌟".to_string(),
        );

        let base64_str = message_with_special_chars
            .to_base64()
            .expect("Failed to encode");
        let decoded = MeetChatMessage::from_base64(&base64_str).expect("Failed to decode");

        assert_eq!(message_with_special_chars.identity, decoded.identity);
        assert_eq!(message_with_special_chars.name, decoded.name);
        assert_eq!(message_with_special_chars.message, decoded.message);
    }

    #[test]
    fn test_base64_with_empty_message() {
        let empty_message = MeetChatMessage::new(
            Uuid::new_v4().to_string(),
            Utc::now().timestamp_millis(),
            "user1".to_string(),
            "User One".to_string(),
            false,
            String::new(),
        );

        let base64_str = empty_message.to_base64().expect("Failed to encode");
        let decoded = MeetChatMessage::from_base64(&base64_str).expect("Failed to decode");

        assert_eq!(empty_message.message, decoded.message);
        assert_eq!(decoded.message, "");
    }

    #[test]
    fn test_base64_with_long_message() {
        let long_message = "a".repeat(10000);
        let message = MeetChatMessage::new(
            Uuid::new_v4().to_string(),
            Utc::now().timestamp_millis(),
            "user1".to_string(),
            "User One".to_string(),
            true,
            long_message.clone(),
        );

        let base64_str = message.to_base64().expect("Failed to encode");
        let decoded = MeetChatMessage::from_base64(&base64_str).expect("Failed to decode");

        assert_eq!(message.message, decoded.message);
        assert_eq!(decoded.message.len(), 10000);
    }
}
