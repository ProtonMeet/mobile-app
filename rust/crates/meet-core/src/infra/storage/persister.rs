use super::entities::user::UserEntity;
use cfg_if::cfg_if;
use proton_meet_common::models::{ProtonUser, ProtonUserKey};
use proton_meet_macro::async_trait;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, RwLock},
};

cfg_if! {
    if #[cfg(target_family = "wasm")] {
        use idb::Factory;
        pub type DbConnection = Factory;
        pub type Db = crate::infra::storage::idb::Db;
    } else {
        use super::sqlite;
        use rusqlite::Connection;
        pub type DbConnection = Connection;
        pub type Db = sqlite::Db;
    }
}
use super::entities::user_key::UserKeyEntity;
use crate::{
    domain::user::ports::UserRepository,
    infra::{ports::DbClient, storage::error::StorageError},
};
use futures::Future;

pub trait Database: Sized {
    fn open(path: &str) -> impl Future<Output = Result<Self, StorageError>>;
    fn init_tables(&mut self) -> Result<(), StorageError>;
}

#[derive(Clone)]
pub struct Persister {
    db_cache: Arc<RwLock<HashMap<String, Arc<Mutex<Db>>>>>,
    #[allow(dead_code)]
    db_path: String,
}

impl Persister {
    pub async fn new(db_path: String) -> Result<Self, StorageError> {
        let cache = RwLock::new(HashMap::with_capacity(1));
        Ok(Self {
            db_cache: Arc::new(cache),
            db_path,
        })
    }

    /// Sanitizes a filename to prevent path traversal attacks and other security issues.
    /// Removes or replaces dangerous characters that could be used to escape the database directory.
    fn sanitize_filename(name: &str) -> Result<String, StorageError> {
        if name.is_empty() {
            return Err(StorageError::DatabaseNameEmpty);
        }

        // Remove path separators and traversal sequences
        let mut sanitized = name
            .chars()
            .filter_map(|c| match c {
                // Remove path separators
                '/' | '\\' => None,
                // Remove null bytes
                '\0' => None,
                // Replace other dangerous characters with underscore
                '<' | '>' | ':' | '"' | '|' | '?' | '*' => Some('_'),
                // Keep safe characters
                _ => Some(c),
            })
            .collect::<String>();

        // Check Windows reserved names
        // Reference: https://docs.microsoft.com/en-us/windows/win32/fileio/naming-a-file
        let upper = sanitized.to_uppercase();
        let reserved = [
            "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7",
            "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
        ];
        if reserved.contains(&upper.as_str()) {
            sanitized = format!("_{sanitized}");
        }

        // Remove leading dots to prevent hidden files (but allow single dots in the middle)
        let sanitized = sanitized.trim_start_matches('.');

        // Remove any remaining ".." sequences
        let sanitized = sanitized.replace("..", "");

        if sanitized.is_empty() {
            return Err(StorageError::DatabaseNameInvalidCharacters);
        }

        // Limit filename length to prevent issues with filesystem
        let sanitized = if sanitized.len() > 255 {
            sanitized.chars().take(255).collect::<String>()
        } else {
            sanitized
        };

        Ok(sanitized)
    }

    #[cfg(not(target_family = "wasm"))]
    pub async fn connect(&self, name: &str) -> Result<(), StorageError> {
        // Sanitize the filename to prevent path traversal attacks
        let safe_name = Self::sanitize_filename(name)?;
        let path = format!("{}/{}.sqlite", self.db_path, safe_name);
        let mut db = Db::open(&path).await?;
        db.init_tables()?;
        {
            let mut guard = self.db_cache.write()?;
            guard.insert(name.to_string(), Arc::new(Mutex::new(db)));
        }
        Ok(())
    }

    #[cfg(target_family = "wasm")]
    pub async fn connect(&self, name: &str) -> Result<(), StorageError> {
        // Sanitize the filename to prevent security issues (IndexedDB also has naming restrictions)
        let safe_name = Self::sanitize_filename(name)?;
        let mut db = Db::open(&safe_name).await?;
        db.init_tables()?;
        {
            let mut guard = self
                .db_cache
                .write()
                .map_err(|_| anyhow::anyhow!("Failed to lock db cache"))?;
            guard.insert(name.to_string(), Arc::new(Mutex::new(db)));
        }
        Ok(())
    }

    pub fn get(&self, name: &str) -> Result<Arc<Mutex<Db>>, StorageError> {
        let guard = self.db_cache.read()?;
        Ok(guard
            .get(name)
            .ok_or(StorageError::DbNotFound {
                name: name.to_string(),
            })?
            .clone())
    }

    pub async fn safe_get(&self, name: &str) -> Result<Arc<Mutex<Db>>, StorageError> {
        // Try to get from cache first
        match self.get(name) {
            Ok(db) => Ok(db),
            Err(_) => {
                // Database not found, try to initialize
                self.init_tables(name).await?;
                Ok(self.get(name)?)
            }
        }
    }

    pub async fn close(&self, name: &str) -> Result<(), StorageError> {
        {
            let mut guard = self
                .db_cache
                .write()
                .map_err(|_| StorageError::FailedToLockDbCache)?;
            guard.remove(name);
        }
        Ok(())
    }
}

#[async_trait]
impl DbClient for Persister {
    async fn init_db_tables(&self, name: &str) -> Result<(), StorageError> {
        self.connect(name).await?;

        #[cfg(not(target_family = "wasm"))]
        {
            let db = self.get(name)?;
            let mut guard = db.lock()?;
            let db_tx = guard.get_transaction()?;
            UserEntity::init_sqlite_tables(&db_tx)?;
            UserKeyEntity::init_sqlite_tables(&db_tx)?;
            db_tx.commit()?;
        }
        // For WASM, idb migration is handled in idb.rs during connect()
        Ok(())
    }
}

#[async_trait]
impl UserRepository for Persister {
    async fn init_tables(&self, user_id: &str) -> Result<(), StorageError> {
        self.init_db_tables(user_id).await?;
        Ok(())
    }

    async fn get_user(&self, user_id: &str) -> Result<Option<ProtonUser>, StorageError> {
        let db = self.safe_get(user_id).await?;
        let guard = db.lock()?;

        #[cfg(not(target_family = "wasm"))]
        {
            let Some(entity) = guard.get::<UserEntity>(UserEntity::TABLE_NAME, user_id)? else {
                return Ok(None);
            };
            Ok(Some(entity.into()))
        }

        #[cfg(target_family = "wasm")]
        {
            let user = guard.get(UserEntity::TABLE_NAME, user_id).await?;
            Ok(user)
        }
    }

    async fn save_user(&self, user: &ProtonUser) -> Result<(), StorageError> {
        let db = self.safe_get(&user.id).await?;
        let guard = db.lock()?;

        #[cfg(not(target_family = "wasm"))]
        {
            let user_entity: UserEntity = user.clone().into();
            guard.save(UserEntity::TABLE_NAME, user_entity)?;
        }

        #[cfg(target_family = "wasm")]
        {
            guard
                .save(UserEntity::TABLE_NAME, user.id.as_str(), user)
                .await?;
        }

        Ok(())
    }

    async fn delete_user(&self, user_id: &str) -> Result<usize, StorageError> {
        let db = self.get(user_id)?;
        let guard = db.lock()?;

        #[cfg(not(target_family = "wasm"))]
        {
            guard.delete(UserEntity::TABLE_NAME, user_id)
        }

        #[cfg(target_family = "wasm")]
        {
            guard.delete(UserEntity::TABLE_NAME, user_id).await?;
            Ok(0)
        }
    }

    async fn get_user_keys(&self, user_id: &str) -> Result<Vec<ProtonUserKey>, StorageError> {
        let db = match self.get(user_id) {
            Ok(db) => db,
            Err(_) => return Ok(Vec::new()),
        };
        let guard = db.lock()?;

        #[cfg(not(target_family = "wasm"))]
        {
            use proton_meet_common::models::ProtonUserKey;

            let query_str = "SELECT * FROM user_keys WHERE user_id = ?";
            let mut stmt = guard.prepare(query_str)?;
            let rows = stmt.query_map([user_id], |row| {
                Ok(UserKeyEntity {
                    id: row.get("id")?,
                    user_id: row.get("user_id")?,
                    private_key: row.get("private_key")?,
                    token: row.get("token")?,
                    signature: row.get("signature")?,
                    primary: row.get("is_primary")?,
                    active: row.get("active")?,
                })
            })?;

            let keys: Result<Vec<ProtonUserKey>, _> =
                rows.map(|row| row.map(|entity| entity.into())).collect();
            Ok(keys?)
        }

        #[cfg(target_family = "wasm")]
        {
            let entities: Vec<UserKeyEntity> = guard
                .get_all_by_index(UserKeyEntity::TABLE_NAME, "user_id", user_id)
                .await
                .map_err(|e| anyhow::anyhow!("Failed to query user keys: {}", e))?;

            let keys: Vec<ProtonUserKey> =
                entities.into_iter().map(|entity| entity.into()).collect();
            Ok(keys)
        }
    }

    async fn save_user_keys(
        &self,
        user_id: &str,
        keys: &[ProtonUserKey],
    ) -> Result<(), StorageError> {
        #[cfg(not(target_family = "wasm"))]
        {
            let db = self.get(user_id)?;
            let mut guard = db.lock()?;
            let tx = guard.get_transaction()?;

            {
                // First delete existing keys for this user
                let delete_query = "DELETE FROM user_keys WHERE user_id = ?";
                let mut stmt = tx.prepare(delete_query)?;
                stmt.execute([user_id])?;

                // Then insert new keys
                for key in keys {
                    let entity = UserKeyEntity::from_key_with_user_id(key.clone(), user_id);
                    Db::save_tx(&tx, UserKeyEntity::TABLE_NAME, entity)?;
                }
            } // All borrows of tx are released here

            tx.commit()?;
            Ok(())
        }

        #[cfg(target_family = "wasm")]
        {
            let db = match self.get(user_id) {
                Ok(db) => db,
                Err(_) => {
                    return Err(StorageError::DbNotFound {
                        name: user_id.to_string(),
                    })
                }
            };

            // First, get all existing keys to know what to delete (without holding the lock)
            let existing_keys = self.get_user_keys(user_id).await.unwrap_or_default();

            // Now acquire the lock for the delete and save operations
            let guard = db
                .lock()
                .map_err(|_| anyhow::anyhow!("Failed to lock db"))?;

            // Delete all existing keys using their actual IDs
            for existing_key in existing_keys {
                let key_id = format!("{}_{}", user_id, existing_key.id);
                let _ = guard.delete(UserKeyEntity::TABLE_NAME, &key_id).await; // Ignore errors
            }

            // Save new keys
            for key in keys {
                let entity = UserKeyEntity::from_key_with_user_id(key.clone(), user_id);
                let key_id = format!("{}_{}", user_id, key.id);
                guard
                    .save(UserKeyEntity::TABLE_NAME, &key_id, &entity)
                    .await?;
            }

            Ok(())
        }
    }

    async fn delete_user_keys(&self, user_id: &str) -> Result<(), StorageError> {
        #[cfg(not(target_family = "wasm"))]
        {
            let db = self.get(user_id)?;
            let guard = db.lock()?;

            let delete_query = "DELETE FROM user_keys WHERE user_id = ?";
            let mut stmt = guard.prepare(delete_query)?;
            stmt.execute([user_id])?;

            Ok(())
        }

        #[cfg(target_family = "wasm")]
        {
            let db = match self.get(user_id) {
                Ok(db) => db,
                Err(_) => {
                    return Err(StorageError::DbNotFound {
                        name: user_id.to_string(),
                    })
                }
            };

            // First, get all existing keys to know what to delete (without holding the lock)
            let existing_keys = self.get_user_keys(user_id).await.unwrap_or_default();

            // Now acquire the lock for the delete operations
            let guard = db.lock()?;

            // Delete all existing keys using their actual IDs
            for existing_key in existing_keys {
                let key_id = format!("{}_{}", user_id, existing_key.id);
                let _ = guard.delete(UserKeyEntity::TABLE_NAME, &key_id).await; // Ignore errors
            }

            Ok(())
        }
    }
}

#[cfg(all(test, not(target_family = "wasm")))]
mod tests {
    use proton_meet_common::models::ProtonUserKey;

    use super::*;

    #[test]
    fn test_sanitize_filename() {
        // Test path traversal attempts
        assert_eq!(
            Persister::sanitize_filename("../../../etc/passwd").unwrap(),
            "etcpasswd"
        );
        assert_eq!(
            Persister::sanitize_filename("..\\..\\..\\windows\\system32").unwrap(),
            "windowssystem32"
        );
        assert_eq!(
            Persister::sanitize_filename("user/../../etc/passwd").unwrap(),
            "useretcpasswd"
        );

        // Test dangerous characters
        assert_eq!(
            Persister::sanitize_filename("user<name>").unwrap(),
            "user_name_"
        );
        assert_eq!(
            Persister::sanitize_filename("user:name").unwrap(),
            "user_name"
        );
        assert_eq!(
            Persister::sanitize_filename("user\"name\"").unwrap(),
            "user_name_"
        );
        assert_eq!(
            Persister::sanitize_filename("user|name").unwrap(),
            "user_name"
        );
        assert_eq!(
            Persister::sanitize_filename("user?name").unwrap(),
            "user_name"
        );
        assert_eq!(
            Persister::sanitize_filename("user*name").unwrap(),
            "user_name"
        );

        // Test leading dots
        assert_eq!(Persister::sanitize_filename("...user").unwrap(), "user");
        assert_eq!(Persister::sanitize_filename(".user").unwrap(), "user");

        // Test normal names should pass through (with minimal changes)
        assert_eq!(
            Persister::sanitize_filename("normal_user_id").unwrap(),
            "normal_user_id"
        );
        assert_eq!(Persister::sanitize_filename("user123").unwrap(), "user123");
        assert_eq!(
            Persister::sanitize_filename("user-name").unwrap(),
            "user-name"
        );

        // Test empty and invalid names
        assert!(Persister::sanitize_filename("").is_err());
        assert!(Persister::sanitize_filename("/").is_err());
        assert!(Persister::sanitize_filename("\\").is_err());
        assert!(Persister::sanitize_filename("../").is_err());
        assert!(Persister::sanitize_filename("...").is_err());

        // Test null bytes
        assert_eq!(
            Persister::sanitize_filename("user\0name").unwrap(),
            "username"
        );

        // Test very long names are truncated
        let long_name = "a".repeat(300);
        let sanitized = Persister::sanitize_filename(&long_name).unwrap();
        assert_eq!(sanitized.len(), 255);

        // Test Windows reserved names (should be prefixed with underscore)
        assert_eq!(Persister::sanitize_filename("CON").unwrap(), "_CON");
        assert_eq!(Persister::sanitize_filename("con").unwrap(), "_con");
        assert_eq!(Persister::sanitize_filename("Con").unwrap(), "_Con");
        assert_eq!(Persister::sanitize_filename("PRN").unwrap(), "_PRN");
        assert_eq!(Persister::sanitize_filename("prn").unwrap(), "_prn");
        assert_eq!(Persister::sanitize_filename("AUX").unwrap(), "_AUX");
        assert_eq!(Persister::sanitize_filename("aux").unwrap(), "_aux");
        assert_eq!(Persister::sanitize_filename("NUL").unwrap(), "_NUL");
        assert_eq!(Persister::sanitize_filename("nul").unwrap(), "_nul");

        // Test COM reserved names
        assert_eq!(Persister::sanitize_filename("COM1").unwrap(), "_COM1");
        assert_eq!(Persister::sanitize_filename("com1").unwrap(), "_com1");
        assert_eq!(Persister::sanitize_filename("COM2").unwrap(), "_COM2");
        assert_eq!(Persister::sanitize_filename("COM9").unwrap(), "_COM9");
        assert_eq!(Persister::sanitize_filename("com9").unwrap(), "_com9");

        // Test LPT reserved names
        assert_eq!(Persister::sanitize_filename("LPT1").unwrap(), "_LPT1");
        assert_eq!(Persister::sanitize_filename("lpt1").unwrap(), "_lpt1");
        assert_eq!(Persister::sanitize_filename("LPT2").unwrap(), "_LPT2");
        assert_eq!(Persister::sanitize_filename("LPT9").unwrap(), "_LPT9");
        assert_eq!(Persister::sanitize_filename("lpt9").unwrap(), "_lpt9");

        // Test that names containing reserved names but not exactly matching are not prefixed
        assert_eq!(Persister::sanitize_filename("CONFIG").unwrap(), "CONFIG");
        assert_eq!(Persister::sanitize_filename("PRINT").unwrap(), "PRINT");
        assert_eq!(
            Persister::sanitize_filename("AUXILIARY").unwrap(),
            "AUXILIARY"
        );
        assert_eq!(Persister::sanitize_filename("NULLIFY").unwrap(), "NULLIFY");
        assert_eq!(Persister::sanitize_filename("COM10").unwrap(), "COM10");
        assert_eq!(Persister::sanitize_filename("COM0").unwrap(), "COM0");
        assert_eq!(Persister::sanitize_filename("LPT10").unwrap(), "LPT10");
        assert_eq!(Persister::sanitize_filename("LPT0").unwrap(), "LPT0");
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn test_path_traversal_prevention() -> Result<(), StorageError> {
        // Test that path traversal attempts are blocked
        let dir = tempfile::tempdir()?;
        let db_path = dir.path().to_str().unwrap_or_default().to_string();
        let persister = Persister::new(db_path.clone()).await?;

        // These should all fail or be sanitized
        let malicious_ids = vec![
            "../../../etc/passwd",
            "..\\..\\..\\windows\\system32",
            "user/../../../etc/passwd",
        ];

        for malicious_id in malicious_ids {
            // The connect should succeed but use sanitized name
            let result = persister.connect(malicious_id).await;
            // It should either succeed with sanitized name or fail with error
            // Either way, no file should be created outside db_path
            if result.is_ok() {
                // Verify no file was created outside the db_path
                let sanitized = Persister::sanitize_filename(malicious_id)?;
                let expected_path = format!("{db_path}/{sanitized}.sqlite");
                assert!(
                    std::path::Path::new(&expected_path).exists(),
                    "File should only exist in db_path directory"
                );
            }
        }

        Ok(())
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn test_persister() -> Result<(), StorageError> {
        // Setup
        let dir = tempfile::tempdir()?;
        let db_path = dir.path().to_str().unwrap_or_default().to_string();
        println!("db_path: {db_path}");
        let persister = Persister::new(db_path.clone()).await?;
        let db_name = "test_id";
        persister.init_tables(db_name).await?;

        // Test user creation and retrieval
        let user = ProtonUser {
            id: "test_id".to_string(),
            name: "Test User".to_string(),
            email: "test@example.com".to_string(),
            ..Default::default()
        };
        persister.save_user(&user).await?;

        let user_fetched =
            persister
                .get_user(&user.id)
                .await?
                .ok_or_else(|| StorageError::NotFound {
                    table: UserEntity::TABLE_NAME.to_string(),
                    key: user.id.to_string(),
                })?;
        assert_eq!(user_fetched, user, "Fetched user should match saved user");

        // Test database persistence
        persister.close(db_name).await?;
        let persister = Persister::new(db_path.clone()).await?;
        persister.init_tables(db_name).await?;
        let user_fetched_after_reopen =
            persister
                .get_user(&user.id)
                .await?
                .ok_or_else(|| StorageError::NotFound {
                    table: UserEntity::TABLE_NAME.to_string(),
                    key: user.id.to_string(),
                })?;
        assert_eq!(
            user_fetched_after_reopen, user,
            "User should persist after reopening database"
        );

        // Test non-existent user
        let non_existent_id = "non_existent".to_string();
        let non_existent_user = persister.get_user(&non_existent_id).await?;
        assert!(
            non_existent_user.is_none(),
            "Non-existent user should return None"
        );

        // Test user deletion
        persister.delete_user(&user.id).await?;
        // get_user will init db if not exist
        let deleted_user = persister.get_user(&user.id).await?;
        assert!(deleted_user.is_none(), "User should be deleted");

        // Test non-existent user deletion
        let delete_result = persister.delete_user(&non_existent_id).await?;
        assert_eq!(delete_result, 0, "Non-existent user should return an error");
        let deleted_non_existent_user = persister.get_user(&non_existent_id).await?;
        assert!(
            deleted_non_existent_user.is_none(),
            "Non-existent user should still return None"
        );

        // ===== USER KEYS TESTS =====

        // Use a different user ID for the key tests to avoid conflicts
        let key_test_user = ProtonUser {
            id: "key_test_user".to_string(),
            name: "Key Test User".to_string(),
            email: "keytest@example.com".to_string(),
            ..Default::default()
        };
        let key_test_db_name = "key_test_user";

        // Initialize a fresh database connection for key tests
        let persister = Persister::new(db_path.clone()).await?;
        persister.init_tables(key_test_db_name).await?;
        persister.save_user(&key_test_user).await?;

        // Test saving and retrieving user keys
        let test_keys = vec![
            ProtonUserKey {
                id: "key1".to_string(),
                version: 0,
                private_key: "private_key_1".to_string(),
                recovery_secret: None,
                recovery_secret_signature: None,
                token: Some("token1".to_string()),
                fingerprint: String::new(),
                signature: Some("signature1".to_string()),
                primary: 1,
                active: 1,
            },
            ProtonUserKey {
                id: "key2".to_string(),
                version: 0,
                private_key: "private_key_2".to_string(),
                recovery_secret: None,
                recovery_secret_signature: None,
                token: None,
                fingerprint: String::new(),
                signature: None,
                primary: 0,
                active: 1,
            },
            ProtonUserKey {
                id: "key3".to_string(),
                version: 0,
                private_key: "private_key_3".to_string(),
                recovery_secret: None,
                recovery_secret_signature: None,
                token: Some("token3".to_string()),
                fingerprint: String::new(),
                signature: None,
                primary: 0,
                active: 0,
            },
        ];

        persister
            .save_user_keys(&key_test_user.id.to_string(), &test_keys)
            .await?;

        let retrieved_keys = persister.get_user_keys(&key_test_user.id).await?;
        assert_eq!(retrieved_keys.len(), 3, "Should retrieve all saved keys");

        // Check that all keys are present (order might be different)
        for expected_key in &test_keys {
            let found = retrieved_keys.iter().find(|k| k.id == expected_key.id);
            assert!(found.is_some(), "Key {} should be found", expected_key.id);
            let found_key = found.ok_or_else(|| anyhow::anyhow!("Key not found"))?;
            assert_eq!(found_key.private_key, expected_key.private_key);
            assert_eq!(found_key.token, expected_key.token);
            assert_eq!(found_key.signature, expected_key.signature);
            assert_eq!(found_key.primary, expected_key.primary);
            assert_eq!(found_key.active, expected_key.active);
        }

        // Test updating user keys (should replace existing)
        let updated_keys = vec![
            ProtonUserKey {
                id: "key1".to_string(),
                version: 0,
                private_key: "updated_private_key_1".to_string(),
                recovery_secret: None,
                recovery_secret_signature: None,
                token: Some("updated_token1".to_string()),
                fingerprint: String::new(),
                signature: Some("updated_signature1".to_string()),
                primary: 1,
                active: 0,
            },
            ProtonUserKey {
                id: "key4".to_string(),
                version: 0,
                private_key: "private_key_4".to_string(),
                recovery_secret: None,
                recovery_secret_signature: None,
                token: Some("token4".to_string()),
                fingerprint: String::new(),
                signature: Some("signature4".to_string()),
                primary: 0,
                active: 1,
            },
        ];

        persister
            .save_user_keys(&key_test_user.id.to_string(), &updated_keys)
            .await?;
        let retrieved_updated_keys = persister.get_user_keys(&key_test_user.id).await?;
        assert_eq!(
            retrieved_updated_keys.len(),
            2,
            "Should have only 2 keys after update"
        );

        // Verify the keys were actually updated
        let key1 = retrieved_updated_keys
            .iter()
            .find(|k| k.id == "key1")
            .ok_or_else(|| anyhow::anyhow!("Key with id 'key1' not found in retrieved keys"))?;
        assert_eq!(key1.private_key, "updated_private_key_1");
        assert_eq!(key1.active, 0);

        let key4 = retrieved_updated_keys.iter().find(|k| k.id == "key4");
        let key4 =
            key4.ok_or_else(|| anyhow::anyhow!("Key with id 'key4' not found in retrieved keys"))?;
        assert_eq!(key4.private_key, "private_key_4");

        // Test key persistence across database reopens
        persister.close(key_test_db_name).await?;
        let persister = Persister::new(db_path.clone()).await?;
        persister.init_tables(key_test_db_name).await?;

        let persistent_keys = persister.get_user_keys(&key_test_user.id).await?;
        assert_eq!(
            persistent_keys.len(),
            2,
            "Keys should persist after reopening database"
        );
        assert!(
            persistent_keys.iter().any(|k| k.id == "key1"),
            "Key1 should persist"
        );
        assert!(
            persistent_keys.iter().any(|k| k.id == "key4"),
            "Key4 should persist"
        );

        // Test getting keys for non-existent user
        let non_existent_keys = persister.get_user_keys(&non_existent_id).await?;
        assert!(
            non_existent_keys.is_empty(),
            "Non-existent user should have no keys"
        );

        // Test deleting user keys
        persister.delete_user_keys(&key_test_user.id).await?;
        let deleted_keys = persister.get_user_keys(&key_test_user.id).await?;
        assert!(deleted_keys.is_empty(), "User keys should be deleted");

        // Test deleting keys for non-existent user (should not error)
        let result = persister.delete_user_keys(&non_existent_id).await;
        assert!(
            result.is_err(),
            "Deleting keys for non-existent user should return an error"
        );

        // Test saving empty keys array
        persister.save_user_keys(&key_test_user.id, &[]).await?;
        let empty_keys = persister.get_user_keys(&key_test_user.id).await?;
        assert!(
            empty_keys.is_empty(),
            "Empty keys array should result in no keys"
        );

        Ok(())
    }
}

#[cfg(all(test, target_family = "wasm"))]
mod wasm_tests {
    use super::*;
    use proton_meet_common::models::ProtonUser;
    use proton_meet_common::models::ProtonUserKey;
    use wasm_bindgen::JsValue;
    use wasm_bindgen_test::*;

    #[wasm_bindgen_test]
    async fn test_persister_wasm() -> Result<(), JsValue> {
        // Setup
        let persister = Persister::new("".to_string())
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        let db_name = "test_id";
        persister
            .init_tables(db_name)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;

        // Test user creation and retrieval
        let user = ProtonUser {
            id: "test_id".to_string(),
            name: "Test User".to_string(),
            email: "test@example.com".to_string(),
            ..Default::default()
        };
        persister
            .save_user(&user)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;

        let user_fetched = persister
            .get_user(&user.id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?
            .ok_or_else(|| JsValue::from_str("User not found"))?;
        assert_eq!(user_fetched, user, "Fetched user should match saved user");

        // Test database persistence
        persister
            .close(db_name)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        let persister = Persister::new("".to_string())
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        persister
            .init_tables(db_name)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        let user_fetched_after_reopen = persister
            .get_user(&user.id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?
            .ok_or_else(|| JsValue::from_str("User not found after reopening database"))?;
        assert_eq!(
            user_fetched_after_reopen, user,
            "User should persist after reopening database"
        );

        // Test non-existent user
        let non_existent_id = "non_existent".to_string();
        let non_existent_user = persister
            .get_user(&non_existent_id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        assert!(
            non_existent_user.is_none(),
            "Non-existent user should return None"
        );

        // Test user deletion
        persister
            .delete_user(&user.id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        let deleted_user = persister
            .get_user(&user.id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        assert!(deleted_user.is_none(), "User should be deleted");

        // Test non-existent user deletion
        let delete_result = persister
            .delete_user(&non_existent_id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        assert_eq!(delete_result, 0, "Non-existent user should return an error");

        let deleted_non_existent_user = persister
            .get_user(&non_existent_id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        assert!(
            deleted_non_existent_user.is_none(),
            "Non-existent user should still return None"
        );

        // ===== USER KEYS TESTS =====

        let user_keys_db_name = "test_id_keys";
        persister
            .init_tables(user_keys_db_name)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        // Recreate user for key tests
        let user = ProtonUser {
            id: user_keys_db_name.to_string(),
            name: "Test User Keys".to_string(),
            email: "test@example.com".to_string(),
            ..Default::default()
        };
        persister
            .save_user(&user)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;

        // Test saving and retrieving user keys
        let test_keys = vec![
            ProtonUserKey {
                id: "key1".to_string(),
                version: 0,
                private_key: "private_key_1".to_string(),
                token: Some("token1".to_string()),
                signature: Some("signature1".to_string()),
                primary: 1,
                active: 1,
                fingerprint: String::new(),
                recovery_secret: None,
                recovery_secret_signature: None,
            },
            ProtonUserKey {
                id: "key2".to_string(),
                version: 0,
                private_key: "private_key_2".to_string(),
                token: None,
                signature: None,
                primary: 0,
                active: 1,
                fingerprint: String::new(),
                recovery_secret: None,
                recovery_secret_signature: None,
            },
            ProtonUserKey {
                id: "key3".to_string(),
                version: 0,
                private_key: "private_key_3".to_string(),
                token: Some("token3".to_string()),
                signature: None,
                primary: 0,
                active: 0,
                fingerprint: String::new(),
                recovery_secret: None,
                recovery_secret_signature: None,
            },
        ];

        persister
            .save_user_keys(&user.id, &test_keys)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;

        let retrieved_keys = persister
            .get_user_keys(&user.id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        assert_eq!(retrieved_keys.len(), 3, "Should retrieve all saved keys");

        // Check that all keys are present (order might be different)
        for expected_key in &test_keys {
            let found = retrieved_keys.iter().find(|k| k.id == expected_key.id);
            assert!(found.is_some(), "Key {} should be found", expected_key.id);
            let found_key = found.ok_or_else(|| JsValue::from_str("Key not found"))?;
            assert_eq!(found_key.private_key, expected_key.private_key);
            assert_eq!(found_key.token, expected_key.token);
            assert_eq!(found_key.signature, expected_key.signature);
            assert_eq!(found_key.primary, expected_key.primary);
            assert_eq!(found_key.active, expected_key.active);
        }

        // Test updating user keys (should replace existing)
        let updated_keys = vec![
            ProtonUserKey {
                id: "key1".to_string(),
                version: 0,
                private_key: "updated_private_key_1".to_string(),
                token: Some("updated_token1".to_string()),
                signature: Some("updated_signature1".to_string()),
                primary: 1,
                active: 0,
                fingerprint: String::new(),
                recovery_secret: None,
                recovery_secret_signature: None,
            },
            ProtonUserKey {
                id: "key4".to_string(),
                version: 0,
                private_key: "private_key_4".to_string(),
                token: Some("token4".to_string()),
                signature: Some("signature4".to_string()),
                primary: 0,
                active: 1,
                fingerprint: String::new(),
                recovery_secret: None,
                recovery_secret_signature: None,
            },
        ];

        persister
            .save_user_keys(&user.id, &updated_keys)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        let retrieved_updated_keys = persister
            .get_user_keys(&user.id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        assert_eq!(
            retrieved_updated_keys.len(),
            2,
            "Should have only 2 keys after update"
        );

        // Verify the keys were actually updated
        let key1 = retrieved_updated_keys
            .iter()
            .find(|k| k.id == "key1")
            .ok_or_else(|| JsValue::from_str("Key with id 'key1' not found in retrieved keys"))?;
        assert_eq!(key1.private_key, "updated_private_key_1");
        assert_eq!(key1.active, 0);

        let key4 = retrieved_updated_keys
            .iter()
            .find(|k| k.id == "key4")
            .ok_or_else(|| JsValue::from_str("Key with id 'key4' not found in retrieved keys"))?;
        assert_eq!(key4.private_key, "private_key_4");

        // Test key persistence across database reopens
        persister
            .close(user_keys_db_name)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        let persister = Persister::new("".to_string())
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        persister
            .init_tables(user_keys_db_name)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;

        let persistent_keys = persister
            .get_user_keys(&user.id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        assert_eq!(
            persistent_keys.len(),
            2,
            "Keys should persist after reopening database"
        );
        assert!(
            persistent_keys.iter().any(|k| k.id == "key1"),
            "Key1 should persist"
        );
        assert!(
            persistent_keys.iter().any(|k| k.id == "key4"),
            "Key4 should persist"
        );

        // Test getting keys for non-existent user
        let non_existent_keys = persister
            .get_user_keys(&non_existent_id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        assert!(
            non_existent_keys.is_empty(),
            "Non-existent user should have no keys"
        );

        // Test deleting user keys
        persister
            .delete_user_keys(&user.id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        let deleted_keys = persister
            .get_user_keys(&user.id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        assert!(deleted_keys.is_empty(), "User keys should be deleted");

        // Test deleting keys for non-existent user
        let result = persister
            .delete_user_keys(&non_existent_id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()));
        assert!(
            result.is_err(),
            "Deleting keys for non-existent user should return an error"
        );

        // Test saving empty keys array
        persister
            .save_user_keys(&user.id, &[])
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        let empty_keys = persister
            .get_user_keys(&user.id)
            .await
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        assert!(
            empty_keys.is_empty(),
            "Empty keys array should result in no keys"
        );

        Ok(())
    }
}
