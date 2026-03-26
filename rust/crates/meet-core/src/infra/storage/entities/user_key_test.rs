#[cfg(all(test, not(target_family = "wasm")))]
mod tests {
    use crate::infra::storage::entities::user_key::UserKeyEntity;
    use crate::infra::storage::error::StorageError;
    use crate::infra::storage::sqlite::Db;
    use rusqlite::OptionalExtension;

    fn create_test_db() -> Db {
        // Use Database trait to create Db instance
        use crate::infra::storage::persister::Database;
        let mut db = futures::executor::block_on(Db::open(":memory:")).unwrap();
        let db_tx = db.get_transaction().unwrap();
        Db::init_schemas_table(&db_tx).unwrap();
        db_tx.commit().unwrap();
        db
    }

    #[test]
    fn test_init_sqlite_tables_creates_table() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        // Initialize the table
        UserKeyEntity::init_sqlite_tables(&db_tx)?;

        // Verify table exists
        let table_exists = db_tx
            .query_row(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='user_keys'",
                [],
                |row| row.get::<_, String>(0),
            )
            .optional()?;
        assert!(table_exists.is_some(), "user_keys table should exist");

        db_tx.commit()?;
        Ok(())
    }

    #[test]
    fn test_init_sqlite_tables_schema_structure() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        UserKeyEntity::init_sqlite_tables(&db_tx)?;

        // Get table info using PRAGMA
        // PRAGMA table_info returns: cid, name, type, notnull, dflt_value, pk
        // (6 columns total, indexed 0-5)
        let mut stmt = db_tx.prepare("PRAGMA table_info(user_keys)")?;
        let columns: Vec<(String, String, bool, Option<String>, bool)> = stmt
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(1)?,         // name
                    row.get::<_, String>(2)?,         // type
                    row.get::<_, bool>(3)?,           // notnull
                    row.get::<_, Option<String>>(4)?, // default_value
                    row.get::<_, bool>(5)?,           // pk
                ))
            })?
            .collect::<Result<_, _>>()?;
        drop(stmt); // Drop statement before committing transaction

        // Verify all expected columns exist
        let column_names: Vec<String> = columns
            .iter()
            .map(|(name, _, _, _, _)| name.clone())
            .collect();
        assert!(
            column_names.contains(&"id".to_string()),
            "Should have id column"
        );
        assert!(
            column_names.contains(&"user_id".to_string()),
            "Should have user_id column"
        );
        assert!(
            column_names.contains(&"private_key".to_string()),
            "Should have private_key column"
        );
        assert!(
            column_names.contains(&"token".to_string()),
            "Should have token column"
        );
        assert!(
            column_names.contains(&"signature".to_string()),
            "Should have signature column"
        );
        assert!(
            column_names.contains(&"is_primary".to_string()),
            "Should have is_primary column"
        );
        assert!(
            column_names.contains(&"active".to_string()),
            "Should have active column"
        );

        // Verify column types and constraints
        for (name, col_type, not_null, _, _is_pk) in &columns {
            match name.as_str() {
                "id" => {
                    assert_eq!(col_type, "TEXT", "id should be TEXT");
                    assert!(*not_null, "id should be NOT NULL");
                }
                "user_id" => {
                    assert_eq!(col_type, "TEXT", "user_id should be TEXT");
                    assert!(*not_null, "user_id should be NOT NULL");
                }
                "private_key" => {
                    assert_eq!(col_type, "TEXT", "private_key should be TEXT");
                    assert!(*not_null, "private_key should be NOT NULL");
                }
                "token" => {
                    assert_eq!(col_type, "TEXT", "token should be TEXT");
                    assert!(!*not_null, "token should be nullable");
                }
                "signature" => {
                    assert_eq!(col_type, "TEXT", "signature should be TEXT");
                    assert!(!*not_null, "signature should be nullable");
                }
                "is_primary" => {
                    assert_eq!(col_type, "BOOLEAN", "is_primary should be BOOLEAN");
                    assert!(*not_null, "is_primary should be NOT NULL");
                }
                "active" => {
                    assert_eq!(col_type, "BOOLEAN", "active should be BOOLEAN");
                    assert!(*not_null, "active should be NOT NULL");
                }
                _ => {}
            }
        }

        // Verify primary key constraint (composite key on id and user_id)
        let pk_columns: Vec<String> = columns
            .iter()
            .filter(|(_, _, _, _, is_pk)| *is_pk)
            .map(|(name, _, _, _, _)| name.clone())
            .collect();
        assert!(
            pk_columns.contains(&"id".to_string()),
            "id should be part of primary key"
        );
        assert!(
            pk_columns.contains(&"user_id".to_string()),
            "user_id should be part of primary key"
        );

        db_tx.commit()?;
        Ok(())
    }

    #[test]
    fn test_init_sqlite_tables_idempotent() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        // Run migration multiple times
        UserKeyEntity::init_sqlite_tables(&db_tx)?;
        UserKeyEntity::init_sqlite_tables(&db_tx)?;
        UserKeyEntity::init_sqlite_tables(&db_tx)?;

        // Verify table still exists and is valid
        let table_exists = db_tx
            .query_row(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='user_keys'",
                [],
                |row| row.get::<_, String>(0),
            )
            .optional()?;
        assert!(
            table_exists.is_some(),
            "Table should still exist after multiple migrations"
        );

        // Verify schema version was set correctly
        let version = Db::schema_version(&db_tx, UserKeyEntity::SCHEME_NAME)?;
        assert_eq!(
            version,
            Some(0),
            "Schema version should be 0 after v1 migration"
        );

        db_tx.commit()?;
        Ok(())
    }

    #[test]
    fn test_init_sqlite_tables_foreign_key_constraint() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        // First create users table (required for foreign key)
        db_tx.execute(
            "CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT, email TEXT)",
            [],
        )?;

        // Initialize user_keys table
        UserKeyEntity::init_sqlite_tables(&db_tx)?;

        // Enable foreign key constraints
        db_tx.execute("PRAGMA foreign_keys = ON", [])?;

        // Insert a user
        db_tx.execute(
            "INSERT INTO users (id, name, email) VALUES (?1, ?2, ?3)",
            ["user1", "Test User", "test@example.com"],
        )?;

        // Insert a user key with valid foreign key
        db_tx.execute(
            "INSERT INTO user_keys (id, user_id, private_key, is_primary, active) VALUES (?1, ?2, ?3, ?4, ?5)",
            ["key1", "user1", "private_key_data", "1", "1"],
        )?;

        // Try to insert a user key with invalid foreign key (should fail if foreign keys are enforced)
        // Note: SQLite doesn't enforce foreign keys by default, but the schema defines them
        let result = db_tx.execute(
            "INSERT INTO user_keys (id, user_id, private_key, is_primary, active) VALUES (?1, ?2, ?3, ?4, ?5)",
            ["key2", "nonexistent_user", "private_key_data", "0", "1"],
        );

        // With foreign keys enabled, this should fail
        db_tx.execute("PRAGMA foreign_keys = ON", [])?;
        assert!(
            result.is_err(),
            "Inserting key with nonexistent user_id should fail with foreign key constraint"
        );

        db_tx.commit()?;
        Ok(())
    }

    #[test]
    fn test_init_sqlite_tables_schema_version_tracking() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        // Check initial state - no schema version
        let version_before = Db::schema_version(&db_tx, UserKeyEntity::SCHEME_NAME)?;
        assert!(
            version_before.is_none(),
            "Schema version should be None initially"
        );

        // Run migration
        UserKeyEntity::init_sqlite_tables(&db_tx)?;

        // Check schema version was set
        let version_after = Db::schema_version(&db_tx, UserKeyEntity::SCHEME_NAME)?;
        assert_eq!(
            version_after,
            Some(0),
            "Schema version should be 0 after v1 migration"
        );

        db_tx.commit()?;
        Ok(())
    }

    #[test]
    fn test_schema_v1_content() {
        let schema = UserKeyEntity::schema_v1();

        // Verify schema contains expected elements
        assert!(
            schema.contains("CREATE TABLE"),
            "Schema should create table"
        );
        assert!(
            schema.contains("user_keys"),
            "Schema should create user_keys table"
        );
        assert!(
            schema.contains("id TEXT"),
            "Schema should have id TEXT column"
        );
        assert!(
            schema.contains("user_id TEXT"),
            "Schema should have user_id TEXT column"
        );
        assert!(
            schema.contains("private_key TEXT"),
            "Schema should have private_key TEXT column"
        );
        assert!(
            schema.contains("token TEXT"),
            "Schema should have token TEXT column"
        );
        assert!(
            schema.contains("signature TEXT"),
            "Schema should have signature TEXT column"
        );
        assert!(
            schema.contains("is_primary BOOLEAN"),
            "Schema should have is_primary BOOLEAN column"
        );
        assert!(
            schema.contains("active BOOLEAN"),
            "Schema should have active BOOLEAN column"
        );
        assert!(
            schema.contains("PRIMARY KEY"),
            "Schema should define primary key"
        );
        assert!(
            schema.contains("FOREIGN KEY"),
            "Schema should define foreign key"
        );
        assert!(
            schema.contains("ON DELETE CASCADE"),
            "Schema should have CASCADE delete"
        );
    }

    #[test]
    fn test_can_insert_and_retrieve_user_key() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        // Create users table first
        db_tx.execute(
            "CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT, email TEXT)",
            [],
        )?;
        db_tx.execute(
            "INSERT INTO users (id, name, email) VALUES (?1, ?2, ?3)",
            ["user1", "Test User", "test@example.com"],
        )?;

        // Initialize user_keys table
        UserKeyEntity::init_sqlite_tables(&db_tx)?;
        db_tx.commit()?;

        // Insert a user key
        let entity = UserKeyEntity {
            id: "key1".to_string(),
            user_id: "user1".to_string(),
            private_key: "private_key_data".to_string(),
            token: Some("token_data".to_string()),
            signature: Some("signature_data".to_string()),
            primary: true,
            active: true,
        };

        let db_tx2 = db.get_transaction()?;
        // SQLite stores BOOLEAN as INTEGER (0 or 1)
        db_tx2.execute(
            "INSERT INTO user_keys (id, user_id, private_key, token, signature, is_primary, active) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            rusqlite::params![
                &entity.id,
                &entity.user_id,
                &entity.private_key,
                &entity.token.as_ref().unwrap(),
                &entity.signature.as_ref().unwrap(),
                if entity.primary { 1 } else { 0 },
                if entity.active { 1 } else { 0 },
            ],
        )?;

        // Retrieve the user key
        let retrieved: Option<UserKeyEntity> = db_tx2
            .query_row(
                "SELECT id, user_id, private_key, token, signature, is_primary, active FROM user_keys WHERE id = ?1 AND user_id = ?2",
                [&entity.id, &entity.user_id],
                |row| {
                    Ok(UserKeyEntity {
                        id: row.get(0)?,
                        user_id: row.get(1)?,
                        private_key: row.get(2)?,
                        token: row.get(3)?,
                        signature: row.get(4)?,
                        primary: row.get(5)?,
                        active: row.get(6)?,
                    })
                },
            )
            .optional()?;

        assert!(retrieved.is_some(), "Should retrieve the inserted user key");
        let retrieved = retrieved.expect("Expected user key to be retrieved from database");
        assert_eq!(retrieved.id, entity.id);
        assert_eq!(retrieved.user_id, entity.user_id);
        assert_eq!(retrieved.private_key, entity.private_key);
        assert_eq!(retrieved.token, entity.token);
        assert_eq!(retrieved.signature, entity.signature);
        assert_eq!(retrieved.primary, entity.primary);
        assert_eq!(retrieved.active, entity.active);

        db_tx2.commit()?;
        Ok(())
    }
}
