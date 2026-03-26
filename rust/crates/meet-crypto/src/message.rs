use super::{
    binary::{Binary, EncryptedBinary},
    room_key::UnlockedRoomKey,
    Result,
};

pub trait Message: Binary {
    /// Pre-implemented
    /// Encrypts the chat message using the provided `UnlockedRoomKey`.
    ///
    /// The message is encrypted using AES-GCM encryption algorithm
    ///
    /// # Parameters
    /// - `key`: A reference to an `UnlockedRoomKey` that will be used to encrypt the message.
    ///
    /// # Returns
    /// - `Ok(EncryptedMessage<Self>)`: On success, returns an encrypted version of the message.
    /// - `Err(CryptoError)`: On failure, returns an error describing what went wrong during encryption.
    fn encrypt_with(&self, key: &UnlockedRoomKey) -> Result<EncryptedMessage<Self>>
    where
        Self: Sized,
    {
        key.encrypt(self.as_bytes()).map(EncryptedMessage::new)
    }
}

/// Type safe EncryptedMessage
/// The message can be of any type that implements the `Message` trait, such as ChatMessage, ChatReaction, or ChatFile.
pub struct EncryptedMessage<T>(Vec<u8>, std::marker::PhantomData<T>);
impl<T> EncryptedBinary for EncryptedMessage<T>
where
    T: Message,
{
    /// Creates a new `EncryptedMessage` with the provided encrypted data.
    fn new(data: Vec<u8>) -> Self {
        Self(data, std::marker::PhantomData)
    }

    fn as_bytes(&self) -> &[u8] {
        &self.0
    }
}

impl<T> EncryptedMessage<T>
where
    T: Message,
{
    /// Decrypts the encrypted message using the provided `UnlockedRoomKey`.
    ///
    /// The decrypted data is returned as an instance of the generic type `T` (e.g., `ChatMessage`, `ChatReaction`, `ChatFile`).
    ///
    /// # Parameters
    /// - `key`: A reference to an `UnlockedRoomKey` that will be used to decrypt the message.
    ///
    /// # Returns
    /// - `Ok(T)`: On success, returns the decrypted message of type `T`.
    /// - `Err(CryptoError)`: On failure, returns an error describing what went wrong during decryption.
    pub fn decrypt_with(&self, key: &UnlockedRoomKey) -> Result<T> {
        key.decrypt(&self.0).map(T::new)
    }
}
