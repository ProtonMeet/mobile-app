use proton_meet_crypto::room_key::UnlockedRoomKey;

/// Trait for looking up encryption keys by index
pub trait KeyProvider {
    // set the shared key index 0
    fn set_shared_key(&mut self, key: UnlockedRoomKey);
    // set the key index after set the key of the index will be used. if can't find the index, the default key will be used.
    fn set_key_index(&mut self, index: u32);
    // add the key for a given index to cache, if the index is already in the cache, the key will be updated
    fn add_key(&mut self, index: u32, key: UnlockedRoomKey);
    // get the key index
    fn key_index(&self) -> u32;
    // auto pick the key for the current index or the shared key
    fn get_key(&self) -> Option<UnlockedRoomKey>;
    // get the key for a given index
    fn key_for_index(&self, index: u32) -> Option<UnlockedRoomKey>;
}
