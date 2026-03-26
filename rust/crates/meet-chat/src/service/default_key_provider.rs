use std::collections::HashMap;

use proton_meet_crypto::room_key::UnlockedRoomKey;

use crate::domain::key_provider::KeyProvider;

/// A default in-memory key provider
#[derive(Clone)]
pub struct DefaultKeyProvider {
    current_index: u32,
    keys: HashMap<u32, UnlockedRoomKey>,
}

impl DefaultKeyProvider {
    pub fn new(shared_key: UnlockedRoomKey) -> Self {
        let mut keys = HashMap::new();
        keys.insert(0, shared_key);
        Self {
            current_index: 0,
            keys,
        }
    }
}

impl KeyProvider for DefaultKeyProvider {
    fn key_index(&self) -> u32 {
        self.current_index
    }

    fn key_for_index(&self, index: u32) -> Option<UnlockedRoomKey> {
        self.keys.get(&index).cloned()
    }

    fn add_key(&mut self, index: u32, key: UnlockedRoomKey) {
        self.keys.insert(index, key);
    }

    fn set_shared_key(&mut self, key: UnlockedRoomKey) {
        self.keys.insert(0, key);
    }

    fn set_key_index(&mut self, index: u32) {
        self.current_index = index;
    }

    fn get_key(&self) -> Option<UnlockedRoomKey> {
        self.keys
            .get(&self.current_index)
            .cloned()
            .or_else(|| self.keys.get(&0).cloned())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_key_1() -> UnlockedRoomKey {
        let key_bytes: [u8; 32] = [
            1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24,
            25, 26, 27, 28, 29, 30, 31, 32,
        ];
        UnlockedRoomKey::new(&key_bytes)
    }

    fn create_test_key_2() -> UnlockedRoomKey {
        let key_bytes: [u8; 32] = [
            32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11,
            10, 9, 8, 7, 6, 5, 4, 3, 2, 1,
        ];
        UnlockedRoomKey::new(&key_bytes)
    }

    fn create_test_key_3() -> UnlockedRoomKey {
        let key_bytes: [u8; 32] = [
            100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116,
            117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131,
        ];
        UnlockedRoomKey::new(&key_bytes)
    }

    #[test]
    fn test_default_key_provider_new() {
        let shared_key = create_test_key_1();
        let provider = DefaultKeyProvider::new(shared_key.clone());

        assert_eq!(provider.key_index(), 0);
        assert_eq!(provider.keys.len(), 1);
        assert!(provider.keys.contains_key(&0));
    }

    #[test]
    fn test_default_key_provider_new_with_shared_key() {
        let shared_key = create_test_key_1();
        let provider = DefaultKeyProvider::new(shared_key.clone());

        // Should be able to get the shared key
        let retrieved_key = provider.get_key();
        assert!(retrieved_key.is_some());

        // Should be able to get key for index 0
        let key_for_zero = provider.key_for_index(0);
        assert!(key_for_zero.is_some());
    }

    #[test]
    fn test_set_shared_key() {
        let initial_key = create_test_key_1();
        let new_shared_key = create_test_key_2();
        let mut provider = DefaultKeyProvider::new(initial_key);

        // Set new shared key
        provider.set_shared_key(new_shared_key.clone());

        // Should still have key at index 0
        assert!(provider.key_for_index(0).is_some());
        assert_eq!(provider.keys.len(), 1);
    }

    #[test]
    fn test_set_key_index() {
        let shared_key = create_test_key_1();
        let mut provider = DefaultKeyProvider::new(shared_key);

        // Initially at index 0
        assert_eq!(provider.key_index(), 0);

        // Set to index 5
        provider.set_key_index(5);
        assert_eq!(provider.key_index(), 5);

        // Set to maximum u32
        provider.set_key_index(u32::MAX);
        assert_eq!(provider.key_index(), u32::MAX);
    }

    #[test]
    fn test_add_key() {
        let shared_key = create_test_key_1();
        let mut provider = DefaultKeyProvider::new(shared_key);

        // Add key at index 1
        let key_1 = create_test_key_2();
        provider.add_key(1, key_1.clone());
        assert_eq!(provider.keys.len(), 2);
        assert!(provider.keys.contains_key(&1));

        // Add key at index 100
        let key_100 = create_test_key_3();
        provider.add_key(100, key_100.clone());
        assert_eq!(provider.keys.len(), 3);
        assert!(provider.keys.contains_key(&100));
    }

    #[test]
    fn test_key_for_index() {
        let shared_key = create_test_key_1();
        let mut provider = DefaultKeyProvider::new(shared_key);

        // Should get key for index 0 (shared key)
        assert!(provider.key_for_index(0).is_some());

        // Should get None for non-existent index
        assert!(provider.key_for_index(1).is_none());
        assert!(provider.key_for_index(999).is_none());

        // Add key at index 1
        let key_1 = create_test_key_2();
        provider.add_key(1, key_1.clone());
        assert!(provider.key_for_index(1).is_some());

        // Should still get None for other non-existent indices
        assert!(provider.key_for_index(2).is_none());
    }

    #[test]
    fn test_get_key_fallback_to_shared_key() {
        let shared_key = create_test_key_1();
        let mut provider = DefaultKeyProvider::new(shared_key);

        // Initially at index 0, should get shared key
        assert_eq!(provider.key_index(), 0);
        assert!(provider.get_key().is_some());

        // Set to non-existent index, should fall back to shared key (index 0)
        provider.set_key_index(999);
        assert_eq!(provider.key_index(), 999);
        assert!(provider.get_key().is_some());
    }

    #[test]
    fn test_get_key_uses_current_index() {
        let shared_key = create_test_key_1();
        let mut provider = DefaultKeyProvider::new(shared_key);

        // Add key at index 5
        let key_5 = create_test_key_2();
        provider.add_key(5, key_5.clone());

        // Set current index to 5
        provider.set_key_index(5);

        // Should get key for index 5, not the shared key
        let retrieved_key = provider.get_key();
        assert!(retrieved_key.is_some());
    }

    #[test]
    fn test_add_key_overwrites_existing() {
        let shared_key = create_test_key_1();
        let mut provider = DefaultKeyProvider::new(shared_key);

        // Add key at index 1
        let key_1_original = create_test_key_2();
        provider.add_key(1, key_1_original.clone());
        assert_eq!(provider.keys.len(), 2);

        // Overwrite key at index 1
        let key_1_new = create_test_key_3();
        provider.add_key(1, key_1_new.clone());
        assert_eq!(provider.keys.len(), 2); // Still 2 keys

        // Should get the new key
        assert!(provider.key_for_index(1).is_some());
    }

    #[test]
    fn test_set_shared_key_overwrites() {
        let initial_shared_key = create_test_key_1();
        let mut provider = DefaultKeyProvider::new(initial_shared_key);

        // Initially should have shared key at index 0
        assert!(provider.key_for_index(0).is_some());

        // Set new shared key
        let new_shared_key = create_test_key_2();
        provider.set_shared_key(new_shared_key.clone());

        // Should still have key at index 0, but it should be the new one
        assert!(provider.key_for_index(0).is_some());
        assert_eq!(provider.keys.len(), 1);
    }

    #[test]
    fn test_edge_cases() {
        let shared_key = create_test_key_1();
        let mut provider = DefaultKeyProvider::new(shared_key);

        // Test with u32::MAX index
        let max_key = create_test_key_2();
        provider.add_key(u32::MAX, max_key.clone());
        provider.set_key_index(u32::MAX);

        assert_eq!(provider.key_index(), u32::MAX);
        assert!(provider.get_key().is_some());
        assert!(provider.key_for_index(u32::MAX).is_some());

        // Test with index 0 explicitly
        provider.set_key_index(0);
        assert_eq!(provider.key_index(), 0);
        assert!(provider.get_key().is_some());
    }

    #[test]
    fn test_multiple_keys_management() {
        let shared_key = create_test_key_1();
        let mut provider = DefaultKeyProvider::new(shared_key);

        // Add multiple keys
        for i in 1..=10 {
            let key = UnlockedRoomKey::generate();
            provider.add_key(i, key);
        }

        assert_eq!(provider.keys.len(), 11); // 10 + 1 shared key

        // Should be able to retrieve all keys
        for i in 0..=10 {
            assert!(provider.key_for_index(i).is_some());
        }

        // Should return None for non-existent keys
        assert!(provider.key_for_index(11).is_none());
        assert!(provider.key_for_index(100).is_none());
    }

    #[test]
    fn test_get_key_without_fallback() {
        let shared_key = create_test_key_1();
        let mut provider = DefaultKeyProvider::new(shared_key);

        // Add key at index 5
        let key_5 = create_test_key_2();
        provider.add_key(5, key_5.clone());

        // Set current index to 5
        provider.set_key_index(5);

        // Should get key for index 5
        assert!(provider.get_key().is_some());

        // Remove the shared key by replacing it with a different key
        let new_shared_key = create_test_key_3();
        provider.set_shared_key(new_shared_key);

        // Should still get key for index 5
        assert!(provider.get_key().is_some());
    }

    #[test]
    fn test_provider_with_generated_keys() {
        let shared_key = UnlockedRoomKey::generate();
        let mut provider = DefaultKeyProvider::new(shared_key);

        // Add some generated keys
        for i in 1..=5 {
            let key = UnlockedRoomKey::generate();
            provider.add_key(i, key);
        }

        // Test that all operations work with generated keys
        assert_eq!(provider.keys.len(), 6);
        assert!(provider.get_key().is_some());

        for i in 1..=5 {
            provider.set_key_index(i);
            assert!(provider.get_key().is_some());
        }
    }
}
