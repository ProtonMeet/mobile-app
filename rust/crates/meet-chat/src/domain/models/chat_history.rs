use chrono::{DateTime, Utc};
use uuid::Uuid;

use crate::domain::models::{
    chat_content::{ChatContent, ChatReaction},
    chat_content_enc::EncryptedChatContent,
};

#[derive(Debug, Clone)]
pub struct ChatHistory {
    pub room_id: Uuid,
    pub messages: Vec<ChatHistoryEntry>,
}

/// A chat history entry keeps encrypted, and optionally decrypted content
#[derive(Debug, Clone)]
pub struct ChatHistoryEntry {
    pub id: Uuid,
    pub sender_id: Uuid,
    pub timestamp: DateTime<Utc>,
    pub encryption_epoch: u32,
    pub encrypted: EncryptedChatContent,
    pub decrypted: Option<ChatContent>,
    pub reactions: Vec<ChatReaction>,
}

impl ChatHistoryEntry {
    pub fn new(
        id: Uuid,
        sender_id: Uuid,
        timestamp: DateTime<Utc>,
        encryption_epoch: u32,
        encrypted: EncryptedChatContent,
    ) -> Self {
        Self {
            id,
            sender_id,
            timestamp,
            encryption_epoch,
            encrypted,
            decrypted: None,
            reactions: vec![],
        }
    }

    pub fn has_decrypted(&self) -> bool {
        self.decrypted.is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::models::chat_content::{ChatPayload, TextMessage};
    use chrono::Utc;
    use uuid::Uuid;

    fn create_test_encrypted_content() -> EncryptedChatContent {
        EncryptedChatContent::new(0, vec![1, 2, 3, 4, 5])
    }

    fn create_test_chat_content() -> ChatContent {
        ChatContent {
            payload: ChatPayload::Message(TextMessage {
                text: "Test message".to_string(),
                style: None,
            }),
        }
    }

    #[test]
    fn test_chat_history_new() {
        let room_id = Uuid::new_v4();
        let history = ChatHistory {
            room_id,
            messages: vec![],
        };

        assert_eq!(history.room_id, room_id);
        assert_eq!(history.messages.len(), 0);
    }

    #[test]
    fn test_chat_history_entry_new() {
        let id = Uuid::new_v4();
        let sender_id = Uuid::new_v4();
        let timestamp = Utc::now();
        let encryption_epoch = 42;
        let encrypted = create_test_encrypted_content();

        let entry = ChatHistoryEntry::new(
            id,
            sender_id,
            timestamp,
            encryption_epoch,
            encrypted.clone(),
        );

        assert_eq!(entry.id, id);
        assert_eq!(entry.sender_id, sender_id);
        assert_eq!(entry.timestamp, timestamp);
        assert_eq!(entry.encryption_epoch, encryption_epoch);
        assert_eq!(entry.encrypted.key_index, encrypted.key_index);
        assert_eq!(entry.encrypted.ciphertext, encrypted.ciphertext);
        assert!(entry.decrypted.is_none());
        assert_eq!(entry.reactions.len(), 0);
    }

    #[test]
    fn test_has_decrypted_false() {
        let entry = ChatHistoryEntry::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Utc::now(),
            0,
            create_test_encrypted_content(),
        );

        assert!(!entry.has_decrypted());
    }

    #[test]
    fn test_has_decrypted_true() {
        let mut entry = ChatHistoryEntry::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Utc::now(),
            0,
            create_test_encrypted_content(),
        );

        entry.decrypted = Some(create_test_chat_content());

        assert!(entry.has_decrypted());
    }

    #[test]
    fn test_chat_history_with_entries() {
        let room_id = Uuid::new_v4();
        let entry1 = ChatHistoryEntry::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Utc::now(),
            0,
            create_test_encrypted_content(),
        );
        let entry2 = ChatHistoryEntry::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Utc::now(),
            1,
            create_test_encrypted_content(),
        );

        let history = ChatHistory {
            room_id,
            messages: vec![entry1.clone(), entry2.clone()],
        };

        assert_eq!(history.room_id, room_id);
        assert_eq!(history.messages.len(), 2);
        assert_eq!(history.messages[0].id, entry1.id);
        assert_eq!(history.messages[1].id, entry2.id);
    }

    #[test]
    fn test_chat_history_entry_with_reactions() {
        let mut entry = ChatHistoryEntry::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Utc::now(),
            0,
            create_test_encrypted_content(),
        );

        let reaction = ChatReaction {
            target_message_id: entry.id,
            emoji: "👍".to_string(),
            reactor_id: Uuid::new_v4(),
            created_at: Some(Utc::now()),
        };

        entry.reactions.push(reaction.clone());

        assert_eq!(entry.reactions.len(), 1);
        assert_eq!(entry.reactions[0].emoji, reaction.emoji);
        assert_eq!(
            entry.reactions[0].target_message_id,
            reaction.target_message_id
        );
        assert_eq!(entry.reactions[0].reactor_id, reaction.reactor_id);
    }

    #[test]
    fn test_chat_history_entry_encryption_epochs() {
        let entry1 = ChatHistoryEntry::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Utc::now(),
            0,
            create_test_encrypted_content(),
        );

        let entry2 = ChatHistoryEntry::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Utc::now(),
            u32::MAX,
            create_test_encrypted_content(),
        );

        assert_eq!(entry1.encryption_epoch, 0);
        assert_eq!(entry2.encryption_epoch, u32::MAX);
    }

    #[test]
    fn test_chat_history_entry_decryption_workflow() {
        let mut entry = ChatHistoryEntry::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Utc::now(),
            0,
            create_test_encrypted_content(),
        );

        // Initially no decrypted content
        assert!(!entry.has_decrypted());
        assert!(entry.decrypted.is_none());

        // Add decrypted content
        entry.decrypted = Some(create_test_chat_content());

        // Now has decrypted content
        assert!(entry.has_decrypted());
        assert!(entry.decrypted.is_some());

        // Verify decrypted content
        if let Some(ChatContent {
            payload: ChatPayload::Message(msg),
        }) = &entry.decrypted
        {
            assert_eq!(msg.text, "Test message");
        } else {
            panic!("Expected decrypted message content");
        }
    }

    #[test]
    fn test_chat_history_multiple_senders() {
        let room_id = Uuid::new_v4();
        let sender1 = Uuid::new_v4();
        let sender2 = Uuid::new_v4();
        let sender3 = Uuid::new_v4();

        let entry1 = ChatHistoryEntry::new(
            Uuid::new_v4(),
            sender1,
            Utc::now(),
            0,
            create_test_encrypted_content(),
        );
        let entry2 = ChatHistoryEntry::new(
            Uuid::new_v4(),
            sender2,
            Utc::now(),
            0,
            create_test_encrypted_content(),
        );
        let entry3 = ChatHistoryEntry::new(
            Uuid::new_v4(),
            sender3,
            Utc::now(),
            0,
            create_test_encrypted_content(),
        );

        let history = ChatHistory {
            room_id,
            messages: vec![entry1, entry2, entry3],
        };

        assert_eq!(history.messages.len(), 3);
        assert_eq!(history.messages[0].sender_id, sender1);
        assert_eq!(history.messages[1].sender_id, sender2);
        assert_eq!(history.messages[2].sender_id, sender3);

        // Verify all messages belong to same room
        assert_eq!(history.room_id, room_id);
    }

    #[test]
    fn test_chat_history_entry_clone() {
        let entry = ChatHistoryEntry::new(
            Uuid::new_v4(),
            Uuid::new_v4(),
            Utc::now(),
            123,
            create_test_encrypted_content(),
        );

        let cloned = entry.clone();

        assert_eq!(entry.id, cloned.id);
        assert_eq!(entry.sender_id, cloned.sender_id);
        assert_eq!(entry.timestamp, cloned.timestamp);
        assert_eq!(entry.encryption_epoch, cloned.encryption_epoch);
        assert_eq!(entry.encrypted.key_index, cloned.encrypted.key_index);
        assert_eq!(entry.encrypted.ciphertext, cloned.encrypted.ciphertext);
        assert_eq!(entry.decrypted.is_none(), cloned.decrypted.is_none());
        assert_eq!(entry.reactions.len(), cloned.reactions.len());
    }
}
