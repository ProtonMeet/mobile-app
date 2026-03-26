use crate::{
    binary::Binary,
    message::{EncryptedMessage, Message},
};

pub struct ChatMessage(Vec<u8>);
impl Binary for ChatMessage {
    fn new(data: Vec<u8>) -> Self {
        Self(data)
    }

    fn as_bytes(&self) -> &[u8] {
        &self.0
    }
}
impl Message for ChatMessage {}
pub type EncryptedChatMessage = EncryptedMessage<ChatMessage>;
