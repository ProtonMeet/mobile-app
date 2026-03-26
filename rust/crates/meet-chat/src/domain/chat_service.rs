use chrono::Utc;
use proton_meet_crypto::{
    binary::{Binary, EncryptedBinary},
    chat_message::{ChatMessage, EncryptedChatMessage},
    message::Message,
};
use uuid::Uuid;

use crate::{
    domain::{
        key_provider::KeyProvider,
        models::{
            chat_content::{ChatContent, ChatPayload},
            chat_content_enc::EncryptedChatContent,
            chat_history::ChatHistoryEntry,
        },
    },
    error::ChatError,
    Result,
};

pub trait ChatService {
    /// Get the underlying key provider (might rotate or update keys)
    fn key_provider(&mut self) -> &mut dyn KeyProvider;

    /// Encrypt a new message (handles selecting key_index, building EncryptedChatContent)
    fn encrypt_message(&self, payload: ChatPayload) -> Result<EncryptedChatContent>;

    /// Try to decrypt a single message
    fn decrypt_message(&self, encrypted: &EncryptedChatContent) -> Result<Option<ChatContent>>;

    /// Access the full history
    fn history(&self) -> &Vec<ChatHistoryEntry>;

    /// Try to decrypt all messages in history that are still not decrypted
    fn refresh_history(&mut self) -> Result<()>;
}

#[derive(Debug, Clone)]
pub struct BasicChatService<P: KeyProvider> {
    key_provider: P,
    history: Vec<ChatHistoryEntry>,
}

impl<P: KeyProvider> BasicChatService<P> {
    pub fn new(key_provider: P) -> Self {
        Self {
            key_provider,
            history: vec![],
        }
    }
}

impl<P: KeyProvider> ChatService for BasicChatService<P> {
    fn key_provider(&mut self) -> &mut dyn KeyProvider {
        &mut self.key_provider
    }

    fn encrypt_message(&self, payload: ChatPayload) -> Result<EncryptedChatContent> {
        let content = ChatContent { payload };
        let key_index = self.key_provider.key_index();
        let key = self.key_provider.get_key().ok_or(ChatError::NoCurrentKey)?;
        let data = serde_json::to_vec(&content)?;
        let encrypted_body = ChatMessage::new(data).encrypt_with(&key)?;
        Ok(EncryptedChatContent::new(
            key_index,
            encrypted_body.as_bytes().to_vec(),
        ))
    }

    fn decrypt_message(&self, encrypted: &EncryptedChatContent) -> Result<Option<ChatContent>> {
        let key_index = encrypted.key_index;
        let key = self
            .key_provider
            .key_for_index(key_index)
            .ok_or(ChatError::KeyNotFound(key_index))?;
        let encrypted_body = EncryptedChatMessage::new(encrypted.ciphertext.clone());
        let decrypted_body = encrypted_body.decrypt_with(&key)?;
        // Parse it into ChatContent using serde
        let content = serde_json::from_slice(decrypted_body.as_bytes())?;
        Ok(Some(content))
    }

    fn history(&self) -> &Vec<ChatHistoryEntry> {
        &self.history
    }

    fn refresh_history(&mut self) -> Result<()> {
        let mut updated = false;
        let mut to_decrypt = Vec::new();

        // Collect indices of entries that need decryption
        for (i, entry) in self.history.iter().enumerate() {
            if entry.decrypted.is_none() {
                to_decrypt.push((i, entry.encrypted.clone()));
            }
        }

        // Decrypt and update entries
        for (i, encrypted) in to_decrypt {
            if let Some(content) = self.decrypt_message(&encrypted)? {
                self.history[i].decrypted = Some(content);
                updated = true;
            }
        }
        if updated {
            // self.notify_listeners();
        }
        Ok(())
    }
}

impl<P: KeyProvider> BasicChatService<P> {
    /// Adds a new message to history by providing clear content.
    /// It encrypts and immediately stores the decrypted version.
    pub fn add_clear_message(
        &mut self,
        sender_id: Uuid,
        payload: ChatPayload,
    ) -> Result<ChatHistoryEntry> {
        let encrypted = self.encrypt_message(payload.clone())?;
        let decrypted = Some(ChatContent { payload });

        self.history.push(ChatHistoryEntry {
            id: Uuid::new_v4(),
            sender_id,
            timestamp: Utc::now(),
            encryption_epoch: encrypted.key_index,
            encrypted,
            decrypted,
            reactions: vec![],
        });
        self.history.last().cloned().ok_or(ChatError::EmptyHistory)
    }

    /// Adds a message from existing encrypted data, tries to decrypt it right away.
    /// Useful if you downloaded it from the network or restored from local DB.
    pub fn add_encrypted_message(
        &mut self,
        sender_id: Uuid,
        encrypted: EncryptedChatContent,
    ) -> Result<ChatHistoryEntry, ChatError> {
        let decrypted = self.decrypt_message(&encrypted)?;
        self.history.push(ChatHistoryEntry {
            id: Uuid::new_v4(),
            sender_id,
            timestamp: Utc::now(),
            encryption_epoch: encrypted.key_index,
            encrypted,
            decrypted,
            reactions: vec![],
        });
        self.history.last().cloned().ok_or(ChatError::EmptyHistory)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::models::chat_content::{ChatPayload, TextMessage};
    use crate::service::default_key_provider::DefaultKeyProvider;
    use proton_meet_crypto::room_key::UnlockedRoomKey;
    use uuid::Uuid;

    fn create_test_key_provider() -> DefaultKeyProvider {
        let key_bytes: [u8; 32] = [
            73, 2, 54, 248, 237, 254, 146, 107, 87, 176, 43, 255, 194, 149, 4, 76, 225, 146, 166,
            250, 185, 207, 119, 138, 32, 221, 121, 174, 94, 92, 141, 183,
        ];
        let shared_key = UnlockedRoomKey::new(&key_bytes);
        DefaultKeyProvider::new(shared_key)
    }

    fn create_test_text_payload() -> ChatPayload {
        ChatPayload::Message(TextMessage {
            text: "Hello, world!".to_string(),
            style: None,
        })
    }

    fn create_test_text_payload_2() -> ChatPayload {
        ChatPayload::Message(TextMessage {
            text: "Another test message".to_string(),
            style: None,
        })
    }

    #[test]
    fn test_basic_chat_service_new() {
        let key_provider = create_test_key_provider();
        let mut service = BasicChatService::new(key_provider);

        assert_eq!(service.history().len(), 0);
        assert_eq!(service.key_provider().key_index(), 0);
        assert!(service.key_provider().get_key().is_some());
    }

    #[test]
    fn test_encrypt_decrypt_round_trip() {
        let key_provider = create_test_key_provider();
        let service = BasicChatService::new(key_provider);
        let payload = create_test_text_payload();

        // Encrypt
        let encrypted = service.encrypt_message(payload.clone()).unwrap();
        assert_eq!(encrypted.key_index, 0);
        assert!(!encrypted.ciphertext.is_empty());

        // Decrypt
        let decrypted = service.decrypt_message(&encrypted).unwrap();
        assert!(decrypted.is_some());

        let content = decrypted.unwrap();
        if let (ChatPayload::Message(original), ChatPayload::Message(decrypted_msg)) =
            (payload, content.payload)
        {
            assert_eq!(original.text, decrypted_msg.text);
        } else {
            panic!("Expected text messages");
        }
    }

    #[test]
    fn test_add_clear_message() {
        let key_provider = create_test_key_provider();
        let mut service = BasicChatService::new(key_provider);
        let sender_id = Uuid::new_v4();
        let payload = create_test_text_payload();

        let result = service.add_clear_message(sender_id, payload);
        assert!(result.is_ok());

        let entry = result.unwrap();
        assert_eq!(entry.sender_id, sender_id);
        assert_eq!(entry.encryption_epoch, 0);
        assert!(entry.decrypted.is_some());
        assert_eq!(entry.reactions.len(), 0);
        assert_eq!(service.history().len(), 1);

        // Verify the message content
        if let Some(ChatContent {
            payload: ChatPayload::Message(msg),
        }) = &entry.decrypted
        {
            assert_eq!(msg.text, "Hello, world!");
        } else {
            panic!("Expected decrypted text message");
        }
    }

    #[test]
    fn test_add_encrypted_message() {
        let key_provider = create_test_key_provider();
        let service = BasicChatService::new(key_provider);
        let sender_id = Uuid::new_v4();
        let payload = create_test_text_payload();

        // Create encrypted content
        let encrypted = service.encrypt_message(payload).unwrap();

        // Add it to another service instance
        let mut service2 = BasicChatService::new(create_test_key_provider());
        let result = service2.add_encrypted_message(sender_id, encrypted);
        assert!(result.is_ok());

        let entry = result.unwrap();
        assert_eq!(entry.sender_id, sender_id);
        assert!(entry.decrypted.is_some());
        assert_eq!(service2.history().len(), 1);

        // Verify the message content
        if let Some(ChatContent {
            payload: ChatPayload::Message(msg),
        }) = &entry.decrypted
        {
            assert_eq!(msg.text, "Hello, world!");
        } else {
            panic!("Expected decrypted text message");
        }
    }

    #[test]
    fn test_history_management() {
        let key_provider = create_test_key_provider();
        let mut service = BasicChatService::new(key_provider);

        // Add multiple messages
        let sender1 = Uuid::new_v4();
        let sender2 = Uuid::new_v4();
        let payload1 = create_test_text_payload();
        let payload2 = create_test_text_payload_2();

        let entry1 = service.add_clear_message(sender1, payload1).unwrap();
        let entry2 = service.add_clear_message(sender2, payload2).unwrap();

        // Verify unique IDs
        assert_ne!(entry1.id, entry2.id);

        // Verify history contains both messages
        assert_eq!(service.history().len(), 2);
        assert_eq!(service.history()[0].sender_id, sender1);
        assert_eq!(service.history()[1].sender_id, sender2);
    }

    #[test]
    fn test_refresh_history() {
        let key_provider = create_test_key_provider();
        let mut service = BasicChatService::new(key_provider);

        // Add a message
        let sender_id = Uuid::new_v4();
        let payload = create_test_text_payload();
        service.add_clear_message(sender_id, payload).unwrap();

        // Call refresh_history
        let result = service.refresh_history();
        assert!(result.is_ok());

        // Should still have the message
        assert_eq!(service.history().len(), 1);
    }

    #[test]
    fn test_multiple_key_indices() {
        let key_provider = create_test_key_provider();
        let mut service = BasicChatService::new(key_provider);

        // Test with key index 1
        let key_bytes: [u8; 32] = [2; 32];
        let key1 = UnlockedRoomKey::new(&key_bytes);
        service.key_provider.add_key(1, key1);
        service.key_provider.set_key_index(1);

        // Add message with key index 1
        let sender_id = Uuid::new_v4();
        let payload = create_test_text_payload();
        let entry = service.add_clear_message(sender_id, payload).unwrap();

        // Verify encryption epoch matches key index
        assert_eq!(entry.encryption_epoch, 1);
        assert_eq!(entry.encrypted.key_index, 1);

        // Should be able to decrypt
        let decrypted = service.decrypt_message(&entry.encrypted).unwrap();
        assert!(decrypted.is_some());
    }

    #[test]
    fn test_service_with_generated_keys() {
        // Test with randomly generated keys
        let shared_key = UnlockedRoomKey::generate();
        let key_provider = DefaultKeyProvider::new(shared_key);
        let mut service = BasicChatService::new(key_provider);

        // Should work with generated keys
        let sender_id = Uuid::new_v4();
        let payload = create_test_text_payload();
        let result = service.add_clear_message(sender_id, payload);
        assert!(result.is_ok());

        let entry = result.unwrap();
        assert!(entry.decrypted.is_some());
        assert_eq!(service.history().len(), 1);
    }

    #[test]
    fn test_large_message_content() {
        let key_provider = create_test_key_provider();
        let mut service = BasicChatService::new(key_provider);

        // Create a large message
        let large_text = "A".repeat(10000); // 10KB message
        let payload = ChatPayload::Message(TextMessage {
            text: large_text.clone(),
            style: None,
        });

        let sender_id = Uuid::new_v4();
        let result = service.add_clear_message(sender_id, payload);
        assert!(result.is_ok());

        let entry = result.unwrap();
        if let Some(ChatContent {
            payload: ChatPayload::Message(msg),
        }) = &entry.decrypted
        {
            assert_eq!(msg.text, large_text);
            assert_eq!(msg.text.len(), 10000);
        } else {
            panic!("Expected decrypted text message");
        }
    }
}
