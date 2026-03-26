#[cfg(not(target_family = "wasm"))]
use proton_crypto_account::{
    keys::{AddressKeys, KeyId, LockedKey, UserKeys},
    salts::KeySecret,
};

/// Test user 1 key secret (password: "test_password_1")
#[cfg(not(target_family = "wasm"))]
pub fn get_test_user_1_locked_user_key_secret() -> KeySecret {
    KeySecret::new(b"test_password_1".to_vec())
}

/// Test user 2 key secret (password: "test_password_2")
#[cfg(not(target_family = "wasm"))]
pub fn get_test_user_2_locked_user_key_secret() -> KeySecret {
    KeySecret::new(b"test_password_2".to_vec())
}

/// Creates a test locked user key for user 1
/// This key can be unlocked with "test_password_1"
#[cfg(not(target_family = "wasm"))]
pub fn get_test_user_1_locked_user_key() -> UserKeys {
    use proton_crypto::{crypto::KeyGeneratorAlgorithm, new_pgp_provider};
    use proton_crypto_account::keys::LocalUserKey;

    let provider = new_pgp_provider();
    let key_secret = get_test_user_1_locked_user_key_secret();

    // Generate a test key
    let user_key = LocalUserKey::generate(&provider, KeyGeneratorAlgorithm::ECC, &key_secret)
        .expect("Failed to generate test user 1 key");

    // Create LockedKey directly - use a test key ID
    // The actual key ID will be determined when unlocked, but for testing we use a fixed ID
    let locked_key = LockedKey {
        id: KeyId::from("test_user_1_key_id"),
        version: 0,
        private_key: user_key.private_key.clone(),
        token: None,
        signature: None,
        activation: None,
        primary: true,
        active: true,
        flags: None,
        recovery_secret: None,
        recovery_secret_signature: None,
        address_forwarding_id: None,
    };

    UserKeys::new(vec![locked_key])
}

/// Creates a test locked user key for user 2
/// This key can be unlocked with "test_password_2"
#[cfg(not(target_family = "wasm"))]
pub fn get_test_user_2_locked_user_key() -> UserKeys {
    use proton_crypto::{crypto::KeyGeneratorAlgorithm, new_pgp_provider};
    use proton_crypto_account::keys::LocalUserKey;

    let provider = new_pgp_provider();
    let key_secret = get_test_user_2_locked_user_key_secret();

    let user_key = LocalUserKey::generate(&provider, KeyGeneratorAlgorithm::ECC, &key_secret)
        .expect("Failed to generate test user 2 key");

    let locked_key = LockedKey {
        id: KeyId::from("test_user_2_key_id"),
        version: 0,
        private_key: user_key.private_key.clone(),
        token: None,
        signature: None,
        activation: None,
        primary: true,
        active: true,
        flags: None,
        recovery_secret: None,
        recovery_secret_signature: None,
        address_forwarding_id: None,
    };

    UserKeys::new(vec![locked_key])
}

/// Creates multiple test locked user keys for user 2
#[cfg(not(target_family = "wasm"))]
pub fn get_test_user_2_locked_user_keys() -> UserKeys {
    use proton_crypto::{crypto::KeyGeneratorAlgorithm, new_pgp_provider};
    use proton_crypto_account::keys::LocalUserKey;

    let provider = new_pgp_provider();
    let key_secret = get_test_user_2_locked_user_key_secret();

    // Generate 2 keys
    let key1 = LocalUserKey::generate(&provider, KeyGeneratorAlgorithm::ECC, &key_secret)
        .expect("Failed to generate test user 2 key 1");

    let key2 = LocalUserKey::generate(&provider, KeyGeneratorAlgorithm::ECC, &key_secret)
        .expect("Failed to generate test user 2 key 2");

    let locked_key1 = LockedKey {
        id: KeyId::from("test_user_2_key_1_id"),
        version: 0,
        private_key: key1.private_key.clone(),
        token: None,
        signature: None,
        activation: None,
        primary: true,
        active: true,
        flags: None,
        recovery_secret: None,
        recovery_secret_signature: None,
        address_forwarding_id: None,
    };

    let locked_key2 = LockedKey {
        id: KeyId::from("test_user_2_key_2_id"),
        version: 0,
        private_key: key2.private_key.clone(),
        token: None,
        signature: None,
        activation: None,
        primary: false,
        active: true,
        flags: None,
        recovery_secret: None,
        recovery_secret_signature: None,
        address_forwarding_id: None,
    };

    UserKeys::new(vec![locked_key1, locked_key2])
}

/// Creates a test locked address key for user 2
/// This key can be unlocked with user 2's keys and "test_password_2"
#[cfg(not(target_family = "wasm"))]
pub fn get_test_user_2_locked_address_key() -> AddressKeys {
    use proton_crypto::{crypto::KeyGeneratorAlgorithm, new_pgp_provider};
    use proton_crypto_account::keys::LocalUserKey;

    let provider = new_pgp_provider();
    let key_secret = get_test_user_2_locked_user_key_secret();

    // Generate an address key (similar to user key but for address)
    let address_key = LocalUserKey::generate(&provider, KeyGeneratorAlgorithm::ECC, &key_secret)
        .expect("Failed to generate test address key");

    let locked_key = LockedKey {
        id: KeyId::from("test_address_key_id"),
        version: 0,
        private_key: address_key.private_key.clone(),
        token: None,
        signature: None,
        activation: None,
        primary: false,
        active: true,
        flags: None,
        recovery_secret: None,
        recovery_secret_signature: None,
        address_forwarding_id: None,
    };

    AddressKeys::new(vec![locked_key])
}
