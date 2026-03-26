use crate::CryptoError;
use crate::Result;
use aes_gcm::{
    aead::{Aead, KeyInit},
    AeadCore, Aes256Gcm, Key, Nonce,
};
use base64::{prelude::BASE64_STANDARD, Engine};

// UnlockedRoomKey represents a key that can be used to encrypt and decrypt data.
// Wrapped in a tuple struct, it hides its internal representation while still allowing
// certain operations.
#[derive(Clone)]
pub struct UnlockedRoomKey(pub(crate) Key<Aes256Gcm>);

impl UnlockedRoomKey {
    pub fn new(bytes: &[u8]) -> Self {
        let key: Key<Aes256Gcm> = *Key::<Aes256Gcm>::from_slice(bytes);
        UnlockedRoomKey(key)
    }

    // restore room key from encode base64 string
    pub fn from_base64(key_base64: &str) -> Result<UnlockedRoomKey> {
        let key_bytes = BASE64_STANDARD.decode(key_base64)?;
        // Check if the decoded key length is correct (32 bytes for AES-256-GCM).
        if key_bytes.len() != 32 {
            // The key is not of the correct length. Return an error
            return Err(CryptoError::AesGcmInvalidKeyLength);
        }
        Ok(UnlockedRoomKey::new(&key_bytes))
    }

    // generate a random room key 256 bits
    pub fn generate() -> UnlockedRoomKey {
        let key: Key<Aes256Gcm> = Aes256Gcm::generate_key(rand::rngs::OsRng);
        UnlockedRoomKey(key)
    }

    // Converts the key to a Base64 encoded string.
    pub fn to_base64(&self) -> String {
        BASE64_STANDARD.encode(self.0)
    }

    // Returns the key as a vector of bytes.
    pub fn to_entropy(&self) -> Vec<u8> {
        self.as_bytes().to_vec()
    }

    fn as_bytes(&self) -> &[u8] {
        self.0.as_slice()
    }

    // Initializes the AES-GCM cipher with the secret key.
    fn get_cipher(&self) -> Aes256Gcm {
        Aes256Gcm::new(&self.0)
    }
}

impl UnlockedRoomKey {
    /// Decrypts the provided encrypted data using AES-GCM with the unlocked room key.
    ///
    /// This function takes in a byte slice that represents encrypted data,
    /// decrypts it using the AES-GCM algorithm, and returns the original plaintext.
    /// The encrypted data must include a 12-byte IV (Initialization Vector) followed by the ciphertext.
    ///
    /// # How it Works
    /// - First, we check that the input data is large enough to contain the necessary IV.
    /// - Then, we extract the IV from the first 12 bytes—think of it as the "key" that unlocks the rest.
    /// - The rest of the input data is the actual ciphertext that needs to be decrypted.
    /// - We initialize the AES-GCM cipher with the secret key, use the IV, and finally decrypt the ciphertext.
    ///
    /// # Errors
    /// - Returns [`CryptoError::AesGcmInvalidDataSize`] if the input is too short to contain an IV.
    /// - Returns [`CryptoError::AesGcm`] if the decryption process fails, which might happen if the ciphertext is corrupted or the key/IV is incorrect.
    ///
    /// # Parameters
    /// - `encrypted_bytes`: A byte slice containing the encrypted data, structured as `12-byte IV | ciphertext`.
    ///
    /// # Returns
    /// - `Ok(Vec<u8>)`: On success, returns the original plaintext as a vector of bytes.
    /// - `Err(CryptoError)`: On failure, returns an error indicating what went wrong during decryption.
    ///
    pub fn decrypt(&self, encrypted_bytes: &[u8]) -> Result<Vec<u8>> {
        // Ensure the encrypted data is large enough to contain an IV (12 bytes).
        if encrypted_bytes.len() < 12 {
            // The encrypted data is too small. Something's fishy!
            return Err(CryptoError::AesGcmInvalidDataSize);
        }

        // Extract the IV (first 12 bytes)
        let iv = Nonce::from_slice(&encrypted_bytes[0..12]);

        // Extract the ciphertext (bytes between the IV and MAC)
        let ciphertext = &encrypted_bytes[12..];

        // Initialize the AES-GCM cipher with the secret key
        let cipher = self.get_cipher();

        let decrypted_bytes = cipher.decrypt(iv, ciphertext.as_ref())?;
        Ok(decrypted_bytes)
    }

    /// Encrypts the provided plaintext data using AES-GCM with the unlocked room key.
    ///
    /// This function takes in a byte slice of plaintext, encrypts it using the AES-GCM algorithm,
    /// and returns the encrypted data. A random IV (Initialization Vector) is generated for each encryption
    /// to ensure that even identical plaintexts result in different ciphertexts. The output is a
    /// concatenation of the IV and the ciphertext.
    ///
    /// # How it Works
    /// - First, we generate a random IV using a secure random number generator. This ensures uniqueness for each encryption operation.
    /// - We then initialize the AES-GCM cipher with the secret key and use it to encrypt the plaintext.
    /// - The resulting ciphertext includes a Message Authentication Code (MAC) to ensure the integrity of the data.
    /// - Finally, we concatenate the IV and the ciphertext, and return this secure package as the output.
    ///
    /// # Errors
    /// - Returns [`CryptoError::AesGcm`] if the encryption process fails due to any internal errors within the cryptographic library or invalid input data.
    ///
    /// # Parameters
    /// - `clear_bytes`: A byte slice containing the plaintext data that you want to encrypt.
    ///
    /// # Returns
    /// - `Ok(Vec<u8>)`: On success, returns a vector of bytes containing the concatenated IV and ciphertext.
    /// - `Err(CryptoError)`: On failure, returns an error indicating what went wrong during encryption.
    pub fn encrypt(&self, clear_bytes: &[u8]) -> Result<Vec<u8>> {
        // get the cipher
        let cipher = self.get_cipher();
        // Generate a random nonce (IV)
        let iv = &Aes256Gcm::generate_nonce(&mut rand::rngs::OsRng);
        // Encrypt the plaintext, ciphertext includes the mac(tag)
        let ciphertext = cipher.encrypt(iv, clear_bytes)?;
        // Concatenate IV and ciphertext into a single vector
        let encrypted_data = [iv.as_slice(), ciphertext.as_slice()].concat();
        // Return the combined IV and ciphertext
        Ok(encrypted_data)
    }
}

#[cfg(test)]
mod test {

    use crate::{
        binary::{Binary, EncryptedBinary},
        chat_message::{ChatMessage, EncryptedChatMessage},
        message::Message,
        room_key::UnlockedRoomKey,
        CryptoError,
    };
    use aes_gcm::{aead::Aead, AeadCore, Aes256Gcm};

    #[test]
    fn test_meet_key() {
        let meet_key = UnlockedRoomKey::generate();
        let key_bytes: &[u8] = meet_key.as_bytes();
        let size = meet_key.0.len();
        assert!(key_bytes.len() == size);
        assert!(key_bytes.len() == 32);
        let cipher = meet_key.get_cipher();
        let nonce = Aes256Gcm::generate_nonce(&mut rand::rngs::OsRng);
        let ciphertext = cipher
            .encrypt(&nonce, b"plaintext message".as_ref())
            .unwrap();
        let plaintext = cipher.decrypt(&nonce, ciphertext.as_ref()).unwrap();
        assert_eq!(&plaintext, b"plaintext message");
    }

    #[test]
    fn test_meet_key_restore() {
        let key_bytes: [u8; 32] = [
            109, 28, 56, 47, 162, 59, 15, 201, 117, 153, 43, 109, 252, 24, 218, 93, 13, 147, 235,
            86, 74, 233, 105, 58, 246, 122, 231, 97, 212, 118, 239, 154,
        ];

        let meet_key = UnlockedRoomKey::new(&key_bytes);
        assert_eq!(meet_key.to_entropy(), key_bytes);
        let cipher = meet_key.get_cipher();
        let nonce = Aes256Gcm::generate_nonce(&mut rand::rngs::OsRng);
        let ciphertext = cipher
            .encrypt(&nonce, b"plaintext message".as_ref())
            .unwrap();
        let plaintext = cipher.decrypt(&nonce, ciphertext.as_ref()).unwrap();
        assert_eq!(&plaintext, b"plaintext message");
    }

    #[test]
    fn test_meet_key_restore_base64() {
        let meet_key =
            UnlockedRoomKey::from_base64("MmI0OGRmZjQ2YzNhN2YyYmQ2NjFlNWEzNzljYTQwZGQ=").unwrap();
        let cipher = meet_key.get_cipher();
        let nonce = Aes256Gcm::generate_nonce(&mut rand::rngs::OsRng);
        let ciphertext = cipher
            .encrypt(&nonce, b"plaintext message".as_ref())
            .unwrap();
        let plaintext = cipher.decrypt(&nonce, ciphertext.as_ref()).unwrap();
        assert_eq!(&plaintext, b"plaintext message");
    }

    #[test]
    fn test_decryption() {
        let plain_text: &str = "Hello AES-256-GCM";
        let encrypt_text = "dTb2Z1bsWkpo2TTCWOK09tanO3n5Ipepbj5WlCRZSuvlkEAxfePeUBCu4Qo6";
        let meet_key =
            UnlockedRoomKey::from_base64("MmI0OGRmZjQ2YzNhN2YyYmQ2NjFlNWEzNzljYTQwZGQ=").unwrap();
        let encrypted_body = EncryptedChatMessage::new_from_base64(encrypt_text).unwrap();
        let clean_text = encrypted_body.decrypt_with(&meet_key).unwrap();
        assert_eq!(clean_text.as_utf8_string().unwrap(), plain_text);
        let bad_byte_key = [
            239, 203, 93, 93, 253, 145, 0, 82, 0, 145, 154, 177, 206, 86, 83, 32, 251, 160, 160,
            29, 164, 144, 177, 0, 205, 128, 0, 38, 59, 33, 146, 218,
        ];
        let meet_key = UnlockedRoomKey::new(&bad_byte_key);
        let error = encrypted_body.decrypt_with(&meet_key).err();
        assert!(error.is_some());
        match error {
            Some(CryptoError::AesGcm(msg)) => {
                assert!(!msg.is_empty());
            }
            _ => panic!("Expected CryptoError::AesGcm variant"),
        }
        let bad_encrypted_data = [239, 203, 93, 93, 253, 145, 0];
        let encrypted_body = EncryptedChatMessage::new(bad_encrypted_data.to_vec());
        let error = encrypted_body.decrypt_with(&meet_key).err();
        assert!(error.is_some());
        match error {
            Some(CryptoError::AesGcmInvalidDataSize) => {}
            _ => panic!("Expected (CryptoError::AesGcmInvalidDataSize"),
        }
    }

    #[test]
    fn test_generate_and_restore_meet_key() {
        let meet_key = UnlockedRoomKey::generate();
        let encoded_entropy = meet_key.to_base64();
        let plain_text = "Hello world";
        let plant_body = ChatMessage::new_from_str(plain_text);
        let encrypted_body = plant_body.encrypt_with(&meet_key).unwrap();
        let check_meet_key = UnlockedRoomKey::from_base64(&encoded_entropy).unwrap();
        let decrypted_body = encrypted_body.decrypt_with(&check_meet_key).unwrap();
        assert_eq!(decrypted_body.as_utf8_string().unwrap(), plain_text);
    }

    #[test]
    fn test_restore_meet_key_and_encrypt() {
        let plaintext = "benefit indoor helmet wine exist height grain spot rely half beef nothing";
        let byte_key = [
            239, 203, 93, 93, 253, 145, 50, 82, 227, 145, 154, 177, 206, 86, 83, 32, 251, 160, 160,
            29, 164, 144, 177, 101, 205, 128, 169, 38, 59, 33, 146, 218,
        ];
        let meet_key = UnlockedRoomKey::new(&byte_key);

        let plant_body = ChatMessage::new_from_str(plaintext);
        let encrypted_body = plant_body.encrypt_with(&meet_key).unwrap();

        let clear_text_boidy = encrypted_body.decrypt_with(&meet_key).unwrap();
        assert!(clear_text_boidy.as_utf8_string().unwrap() == plaintext);
    }
}
