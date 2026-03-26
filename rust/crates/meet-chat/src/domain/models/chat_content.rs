use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// This struct represents the **root data format** your app stores & transmits.
///
/// It is designed to be:
///
///  **Backward compatible:**
///   - Adding new fields will not break older data, because new fields use `#[serde(default)]` or `Option`.
///   - Removing optional fields is generally safe; serde ignores extra JSON fields when deserializing.
///
/// **Forward compatible:**
///    - Future clients can add more data fields; older clients will simply ignore them.
///
/// **Schema evolution friendly:**
///    - Adding more enum variants to `ChatPayload` allows supporting new chat types (e.g. polls, voice).
///    - Old clients can skip unknown variants by using `#[serde(other)]` (if decide to).
///
/// **Important design note:**
/// If ever need to make large breaking changes (like changing payload semantics or removing a critical field),
/// we could later evolve this into a `VersionedChatContent` struct.
/// For now, since data is client-owned, optional fields & defaults give the needed compatibility.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatContent {
    pub payload: ChatPayload,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ChatPayload {
    Message(TextMessage),
    Reaction(ChatReaction),
    FileAttachment(ChatFile),
    Hyperlink(ChatLink),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextMessage {
    pub text: String,

    #[serde(default)]
    pub style: Option<MessageStyle>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct MessageStyle {
    #[serde(default)]
    pub bold: bool,
    #[serde(default)]
    pub italic: bool,
    #[serde(default)]
    pub underline: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatReaction {
    pub target_message_id: Uuid,
    pub emoji: String,
    pub reactor_id: Uuid,
    #[serde(default)]
    pub created_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatFile {
    pub file_name: String,
    pub download_url: String,
    pub file_size: u64,
    #[serde(default)]
    pub thumbnail_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatLink {
    pub url: String,
    #[serde(default)]
    pub description: Option<String>,
}

#[cfg(test)]
mod tests {
    use crate::domain::models::chat_content::{
        ChatContent, ChatFile, ChatLink, ChatPayload, ChatReaction, TextMessage,
    };
    use uuid::Uuid;

    #[test]
    fn test_chat_content_message() {
        let msg = ChatContent {
            payload: ChatPayload::Message(TextMessage {
                text: "Hello".into(),
                style: None,
            }),
        };
        let json = serde_json::to_string(&msg).unwrap();
        println!("Serialized Message JSON: {json}");
        let deserialized: ChatContent = serde_json::from_str(&json).unwrap();
        if let ChatPayload::Message(m) = deserialized.payload {
            assert_eq!(m.text, "Hello");
        } else {
            panic!("Expected Message payload");
        }
    }

    #[test]
    fn test_chat_payload_message() {
        let msg = ChatPayload::Message(TextMessage {
            text: "Hello".into(),
            style: None,
        });
        let json = serde_json::to_string(&msg).unwrap();
        println!("Serialized Message JSON: {json}");
        let deserialized: ChatPayload = serde_json::from_str(&json).unwrap();
        if let ChatPayload::Message(m) = deserialized {
            assert_eq!(m.text, "Hello");
        } else {
            panic!("Expected Message payload");
        }
    }

    #[test]
    fn test_chat_content_reaction() {
        let msg_id = Uuid::new_v4();
        let user_id = Uuid::new_v4();
        let reaction = ChatContent {
            payload: ChatPayload::Reaction(ChatReaction {
                target_message_id: msg_id,
                emoji: "🔥".into(),
                reactor_id: user_id,
                created_at: None,
            }),
        };

        let json = serde_json::to_string(&reaction).unwrap();
        println!("Serialized Reaction JSON: {json}");

        let deserialized: ChatContent = serde_json::from_str(&json).unwrap();
        if let ChatPayload::Reaction(r) = deserialized.payload {
            assert_eq!(r.target_message_id, msg_id);
            assert_eq!(r.emoji, "🔥");
            assert_eq!(r.reactor_id, user_id);
        } else {
            panic!("Expected Reaction payload");
        }
    }

    #[test]
    fn test_chat_content_file() {
        let file = ChatContent {
            payload: ChatPayload::FileAttachment(ChatFile {
                file_name: "doc.pdf".into(),
                download_url: "https://cdn.example.com/doc.pdf".into(),
                file_size: 5678,
                thumbnail_url: None,
            }),
        };

        let json = serde_json::to_string(&file).unwrap();
        println!("Serialized File JSON: {json}");

        let deserialized: ChatContent = serde_json::from_str(&json).unwrap();
        if let ChatPayload::FileAttachment(f) = deserialized.payload {
            assert_eq!(f.file_name, "doc.pdf");
            assert_eq!(f.file_size, 5678);
        } else {
            panic!("Expected FileAttachment payload");
        }
    }

    #[test]
    fn test_chat_content_link() {
        let link = ChatContent {
            payload: ChatPayload::Hyperlink(ChatLink {
                url: "https://rust-lang.org".into(),
                description: Some("Rust Lang".into()),
            }),
        };

        let json = serde_json::to_string(&link).unwrap();
        println!("Serialized Link JSON: {json}");
        let deserialized: ChatContent = serde_json::from_str(&json).unwrap();
        if let ChatPayload::Hyperlink(l) = deserialized.payload {
            assert_eq!(l.url, "https://rust-lang.org");
            assert_eq!(l.description, Some("Rust Lang".into()));
        } else {
            panic!("Expected Hyperlink payload");
        }
    }
}
