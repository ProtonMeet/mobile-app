use crate::error::ChatError;
use base64::{prelude::BASE64_STANDARD, Engine};

/// The encrypted payload
#[derive(Debug, Clone)]
pub struct EncryptedChatContent {
    pub key_index: u32,
    pub ciphertext: Vec<u8>,
}

impl EncryptedChatContent {
    /// Construct with key index + ciphertext
    pub fn new(key_index: u32, encrypted_data: Vec<u8>) -> Self {
        Self {
            key_index,
            ciphertext: encrypted_data,
        }
    }

    /// Parse from combined data: [key_index(4 bytes) | ciphertext]
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, ChatError> {
        if bytes.len() < 4 {
            return Err(ChatError::InvalidDataFormat(
                "Need at least 4 bytes for u32 key index".to_string(),
            ));
        }
        let key_index = u32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]);
        let ciphertext = bytes[4..].to_vec();
        Ok(Self {
            key_index,
            ciphertext,
        })
    }

    /// Parse from base64
    pub fn new_from_base64(b64: &str) -> Result<Self, ChatError> {
        let bytes = BASE64_STANDARD
            .decode(b64)
            .map_err(|e| ChatError::InvalidDataFormat(format!("Invalid base64: {e}")))?;
        Self::from_bytes(&bytes)
    }

    /// Serialize to [key_index(4 bytes) | ciphertext] bytes
    pub fn to_bytes(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(4 + self.ciphertext.len());
        out.extend_from_slice(&self.key_index.to_le_bytes());
        out.extend_from_slice(&self.ciphertext);
        out
    }

    /// Serialize to base64
    pub fn to_base64(&self) -> String {
        BASE64_STANDARD.encode(self.to_bytes())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_creates_correct_structure() {
        let key_index = 42;
        let ciphertext = vec![1, 2, 3, 4, 5];

        let encrypted = EncryptedChatContent::new(key_index, ciphertext.clone());

        assert_eq!(encrypted.key_index, key_index);
        assert_eq!(encrypted.ciphertext, ciphertext);
    }

    #[test]
    fn test_to_bytes_serialization() {
        let key_index = 0x12345678u32; // Test with a specific value
        let ciphertext = vec![0xAB, 0xCD, 0xEF, 0x01, 0x23];

        let encrypted = EncryptedChatContent::new(key_index, ciphertext.clone());
        let bytes = encrypted.to_bytes();

        // Should be 4 bytes for key_index + ciphertext length
        assert_eq!(bytes.len(), 4 + ciphertext.len());

        // First 4 bytes should be key_index in little-endian
        assert_eq!(&bytes[0..4], &key_index.to_le_bytes());

        // Remaining bytes should be ciphertext
        assert_eq!(&bytes[4..], &ciphertext);
    }

    #[test]
    fn test_from_bytes_deserialization() {
        let key_index = 0x87654321u32;
        let ciphertext = vec![0xFF, 0x00, 0x42, 0x13, 0x37];

        let mut bytes = Vec::new();
        bytes.extend_from_slice(&key_index.to_le_bytes());
        bytes.extend_from_slice(&ciphertext);

        let encrypted = EncryptedChatContent::from_bytes(&bytes).unwrap();

        assert_eq!(encrypted.key_index, key_index);
        assert_eq!(encrypted.ciphertext, ciphertext);
    }

    #[test]
    fn test_round_trip_bytes() {
        let key_index = 999;
        let ciphertext = vec![0x11, 0x22, 0x33, 0x44, 0x55, 0x66];

        let original = EncryptedChatContent::new(key_index, ciphertext.clone());
        let bytes = original.to_bytes();
        let deserialized = EncryptedChatContent::from_bytes(&bytes).unwrap();

        assert_eq!(original.key_index, deserialized.key_index);
        assert_eq!(original.ciphertext, deserialized.ciphertext);
    }

    #[test]
    fn test_base64_round_trip() {
        let key_index = 12345;
        let ciphertext = vec![0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE];

        let original = EncryptedChatContent::new(key_index, ciphertext.clone());
        let base64 = original.to_base64();
        let deserialized = EncryptedChatContent::new_from_base64(&base64).unwrap();

        assert_eq!(original.key_index, deserialized.key_index);
        assert_eq!(original.ciphertext, deserialized.ciphertext);
    }

    #[test]
    fn test_from_bytes_error_too_short() {
        let bytes = vec![1, 2, 3]; // Only 3 bytes, need at least 4

        let result = EncryptedChatContent::from_bytes(&bytes);

        assert!(result.is_err());
        if let Err(ChatError::InvalidDataFormat(msg)) = result {
            assert!(msg.contains("Need at least 4 bytes"));
        } else {
            panic!("Expected InvalidDataFormat error");
        }
    }

    #[test]
    fn test_from_bytes_error_empty() {
        let bytes = vec![];

        let result = EncryptedChatContent::from_bytes(&bytes);

        assert!(result.is_err());
        if let Err(ChatError::InvalidDataFormat(msg)) = result {
            assert!(msg.contains("Need at least 4 bytes"));
        } else {
            panic!("Expected InvalidDataFormat error");
        }
    }

    #[test]
    fn test_from_bytes_exactly_four_bytes() {
        let key_index = 0x01020304u32;
        let bytes = key_index.to_le_bytes().to_vec();

        let encrypted = EncryptedChatContent::from_bytes(&bytes).unwrap();

        assert_eq!(encrypted.key_index, key_index);
        assert_eq!(encrypted.ciphertext, Vec::<u8>::new());
    }

    #[test]
    fn test_new_from_base64_error_invalid_base64() {
        let invalid_base64 = "This is not valid base64!@#$%";

        let result = EncryptedChatContent::new_from_base64(invalid_base64);

        assert!(result.is_err());
        if let Err(ChatError::InvalidDataFormat(msg)) = result {
            assert!(msg.contains("Invalid base64"));
        } else {
            panic!("Expected InvalidDataFormat error");
        }
    }

    #[test]
    fn test_new_from_base64_error_too_short() {
        // Valid base64 but decodes to less than 4 bytes
        let short_base64 = BASE64_STANDARD.encode(vec![1, 2]); // Only 2 bytes

        let result = EncryptedChatContent::new_from_base64(&short_base64);

        assert!(result.is_err());
        if let Err(ChatError::InvalidDataFormat(msg)) = result {
            assert!(msg.contains("Need at least 4 bytes"));
        } else {
            panic!("Expected InvalidDataFormat error");
        }
    }

    #[test]
    fn test_edge_cases() {
        // Test with key_index = 0
        let encrypted_zero = EncryptedChatContent::new(0, vec![0x99]);
        assert_eq!(encrypted_zero.key_index, 0);
        assert_eq!(encrypted_zero.ciphertext, vec![0x99]);

        // Test with maximum u32 key_index
        let max_key = u32::MAX;
        let encrypted_max = EncryptedChatContent::new(max_key, vec![0x88, 0x77]);
        assert_eq!(encrypted_max.key_index, max_key);
        assert_eq!(encrypted_max.ciphertext, vec![0x88, 0x77]);

        // Test round-trip with maximum key_index
        let bytes = encrypted_max.to_bytes();
        let deserialized_max = EncryptedChatContent::from_bytes(&bytes).unwrap();
        assert_eq!(encrypted_max.key_index, deserialized_max.key_index);
        assert_eq!(encrypted_max.ciphertext, deserialized_max.ciphertext);
    }

    #[test]
    fn test_large_ciphertext() {
        let key_index = 123;
        let large_ciphertext = vec![0x42; 10000]; // 10KB of data

        let encrypted = EncryptedChatContent::new(key_index, large_ciphertext.clone());
        let bytes = encrypted.to_bytes();
        let deserialized = EncryptedChatContent::from_bytes(&bytes).unwrap();

        assert_eq!(encrypted.key_index, deserialized.key_index);
        assert_eq!(encrypted.ciphertext, deserialized.ciphertext);
        assert_eq!(deserialized.ciphertext.len(), 10000);
    }
}
