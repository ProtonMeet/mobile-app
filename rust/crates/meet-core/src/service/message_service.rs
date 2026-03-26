use std::collections::VecDeque;

use proton_meet_chat::{
    domain::models::{
        chat_content::{ChatContent, ChatPayload},
        chat_content_enc::EncryptedChatContent,
    },
    service::{
        default_chat_service::{ChatService, DefaultChatService},
        default_key_provider::DefaultKeyProvider,
    },
};
use proton_meet_crypto::room_key::UnlockedRoomKey;

#[derive(Clone)]
pub struct MessageService {
    pub room_id: String,
    chat_service: DefaultChatService<DefaultKeyProvider>,
    chat_history: VecDeque<ChatContent>,
}

impl MessageService {
    pub fn new(room_id: &str, _shared_key: &str) -> Self {
        let key_provider = DefaultKeyProvider::new(UnlockedRoomKey::generate());
        let chat_service = DefaultChatService::new(key_provider);
        Self {
            room_id: room_id.to_string(),
            chat_service,
            chat_history: VecDeque::new(),
        }
    }

    pub fn add_key(&mut self, index: u32, key: UnlockedRoomKey) {
        self.chat_service.key_provider().add_key(index, key);
    }

    pub fn send_message(&mut self, payload: ChatPayload) -> Result<EncryptedChatContent, String> {
        let encrypted = self
            .chat_service
            .encrypt_message(payload.clone())
            .map_err(|e| format!("Encryption failed: {e:?}"))?;
        // Add plaintext to history
        // self.chat_history.push_back(ChatContent { payload });
        Ok(encrypted)
    }

    pub fn receive_message(&mut self, encrypted: EncryptedChatContent) -> Option<ChatContent> {
        match self.chat_service.decrypt_message(&encrypted).unwrap() {
            Some(content) => {
                // self.chat_history.push_back(content.clone());
                Some(content)
            }
            None => {
                println!("Failed to decrypt message, will try later if key updates.");
                None
            }
        }
    }

    pub fn reprocess_history(&mut self) {
        // for content in self.chat_history.iter_mut() {
        //     if content.is_decrypted() {
        //         continue;
        //     }
        //     // try to decrypt if possible
        // }
    }

    pub fn close(self) {
        println!("Closing room: {}", self.room_id);
    }

    pub fn history(&self) -> &VecDeque<ChatContent> {
        &self.chat_history
    }
}
