#[cfg(all(test, not(target_family = "wasm")))]
mod tests {
    use crate::infra::storage::entities::user::UserEntity;
    use crate::infra::storage::error::StorageError;
    use crate::infra::storage::sqlite::Db;
    use proton_meet_common::models::ProtonUser;
    use rusqlite::OptionalExtension;

    fn create_test_db() -> Db {
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

        UserEntity::init_sqlite_tables(&db_tx)?;

        // Verify table exists
        let table_exists = db_tx
            .query_row(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
                [],
                |row| row.get::<_, String>(0),
            )
            .optional()?;
        assert!(table_exists.is_some(), "users table should exist");

        db_tx.commit()?;
        Ok(())
    }

    #[test]
    fn test_init_sqlite_tables_schema_v1_structure() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        // Run only v1 migration
        Db::migrate_schema(&db_tx, UserEntity::SCHEME_NAME, &[&UserEntity::schema_v1()])?;

        // Get table info using PRAGMA
        let mut stmt = db_tx.prepare("PRAGMA table_info(users)")?;
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
        drop(stmt);

        // Verify v1 columns exist
        let column_names: Vec<String> = columns
            .iter()
            .map(|(name, _, _, _, _)| name.clone())
            .collect();
        assert!(
            column_names.contains(&"id".to_string()),
            "Should have id column"
        );
        assert!(
            column_names.contains(&"name".to_string()),
            "Should have name column"
        );
        assert!(
            column_names.contains(&"email".to_string()),
            "Should have email column"
        );

        // Verify v1 column types and constraints
        for (name, col_type, not_null, _, is_pk) in &columns {
            match name.as_str() {
                "id" => {
                    assert_eq!(col_type, "TEXT", "id should be TEXT");
                    assert!(*is_pk, "id should be primary key");
                }
                "name" => {
                    assert_eq!(col_type, "TEXT", "name should be TEXT");
                    assert!(*not_null, "name should be NOT NULL");
                }
                "email" => {
                    assert_eq!(col_type, "TEXT", "email should be TEXT");
                    assert!(*not_null, "email should be NOT NULL");
                }
                _ => {}
            }
        }

        // Verify schema version
        let version = Db::schema_version(&db_tx, UserEntity::SCHEME_NAME)?;
        assert_eq!(
            version,
            Some(0),
            "Schema version should be 0 after v1 migration"
        );

        db_tx.commit()?;
        Ok(())
    }

    #[test]
    fn test_init_sqlite_tables_schema_v2_adds_columns() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        // Run full migration (v1 + v2)
        UserEntity::init_sqlite_tables(&db_tx)?;

        // Get table info
        let mut stmt = db_tx.prepare("PRAGMA table_info(users)")?;
        let columns: Vec<(String, String, bool, Option<String>, bool)> = stmt
            .query_map([], |row| {
                Ok((
                    row.get::<_, String>(1)?,
                    row.get::<_, String>(2)?,
                    row.get::<_, bool>(3)?,
                    row.get::<_, Option<String>>(4)?,
                    row.get::<_, bool>(5)?,
                ))
            })?
            .collect::<Result<_, _>>()?;
        drop(stmt);

        // Verify all v2 columns exist
        let column_names: Vec<String> = columns
            .iter()
            .map(|(name, _, _, _, _)| name.clone())
            .collect();
        let v2_columns = [
            "used_space",
            "currency",
            "credit",
            "create_time",
            "max_space",
            "max_upload",
            "role",
            "private",
            "subscribed",
            "services",
            "delinquent",
            "organization_private_key",
            "display_name",
            "mnemonic_status",
        ];

        for col_name in &v2_columns {
            assert!(
                column_names.contains(&col_name.to_string()),
                "Should have {col_name} column after v2 migration",
            );
        }

        // Verify v2 column types (all optional, so not_null should be false)
        for (name, col_type, not_null, _, _) in &columns {
            match name.as_str() {
                "used_space" | "credit" | "create_time" | "max_space" | "max_upload" | "role"
                | "private" | "subscribed" | "services" | "delinquent" | "mnemonic_status" => {
                    assert_eq!(col_type, "INTEGER", "{name} should be INTEGER");
                    assert!(!*not_null, "{name} should be nullable");
                }
                "currency" | "organization_private_key" | "display_name" => {
                    assert_eq!(col_type, "TEXT", "{name} should be TEXT");
                    assert!(!*not_null, "{name} should be nullable");
                }
                _ => {}
            }
        }

        // Verify schema version
        let version = Db::schema_version(&db_tx, UserEntity::SCHEME_NAME)?;
        assert_eq!(
            version,
            Some(1),
            "Schema version should be 1 after v2 migration"
        );

        db_tx.commit()?;
        Ok(())
    }

    #[test]
    fn test_init_sqlite_tables_idempotent() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        // Run migration multiple times
        UserEntity::init_sqlite_tables(&db_tx)?;
        UserEntity::init_sqlite_tables(&db_tx)?;
        UserEntity::init_sqlite_tables(&db_tx)?;

        // Verify table still exists
        let table_exists = db_tx
            .query_row(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
                [],
                |row| row.get::<_, String>(0),
            )
            .optional()?;
        assert!(
            table_exists.is_some(),
            "Table should still exist after multiple migrations"
        );

        // Verify schema version is correct
        let version = Db::schema_version(&db_tx, UserEntity::SCHEME_NAME)?;
        assert_eq!(
            version,
            Some(1),
            "Schema version should be 1 after full migration"
        );

        db_tx.commit()?;
        Ok(())
    }

    #[test]
    fn test_migration_preserves_old_data() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        // Run v1 migration and insert old-format data
        Db::migrate_schema(&db_tx, UserEntity::SCHEME_NAME, &[&UserEntity::schema_v1()])?;
        db_tx.execute(
            "INSERT INTO users (id, name, email) VALUES (?1, ?2, ?3)",
            ["user1", "Old User", "old@example.com"],
        )?;
        db_tx.commit()?;

        // Run v2 migration (should preserve existing data)
        let db_tx2 = db.get_transaction()?;
        Db::migrate_schema(
            &db_tx2,
            UserEntity::SCHEME_NAME,
            &[&UserEntity::schema_v1(), &UserEntity::schema_v2()],
        )?;
        db_tx2.commit()?;

        // Verify old data still exists
        let db_tx3 = db.get_transaction()?;
        let (id, name, email): (String, String, String) = db_tx3.query_row(
            "SELECT id, name, email FROM users WHERE id = ?1",
            ["user1"],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )?;
        assert_eq!(id, "user1");
        assert_eq!(name, "Old User");
        assert_eq!(email, "old@example.com");

        // Verify new columns exist and are NULL for old data
        let used_space: Option<i64> = db_tx3.query_row(
            "SELECT used_space FROM users WHERE id = ?1",
            ["user1"],
            |row| row.get::<_, Option<i64>>(0),
        )?;
        assert!(
            used_space.is_none(),
            "Old data should have NULL for new columns"
        );

        db_tx3.commit()?;
        Ok(())
    }

    #[test]
    fn test_can_insert_and_retrieve_old_format_data() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        UserEntity::init_sqlite_tables(&db_tx)?;
        db_tx.commit()?;

        // Insert old-format data (only id, name, email)
        let entity = UserEntity::new(
            "user1".to_string(),
            "Test User".to_string(),
            "test@example.com".to_string(),
        );

        let db_tx2 = db.get_transaction()?;
        db_tx2.execute(
            "INSERT INTO users (id, name, email) VALUES (?1, ?2, ?3)",
            [&entity.id, &entity.name, &entity.email],
        )?;
        db_tx2.commit()?;

        // Retrieve using Db::get (which uses JSON serialization)
        let retrieved: Option<UserEntity> = db.get("users", "user1")?;
        assert!(retrieved.is_some(), "Should retrieve the inserted user");
        let retrieved = retrieved.expect("Expected user to be retrieved from database");
        assert_eq!(retrieved.id, entity.id);
        assert_eq!(retrieved.name, entity.name);
        assert_eq!(retrieved.email, entity.email);
        // All optional fields should be None for old format
        assert_eq!(retrieved.used_space, None);
        assert_eq!(retrieved.currency, None);

        Ok(())
    }

    #[test]
    fn test_can_insert_and_retrieve_new_format_data() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        UserEntity::init_sqlite_tables(&db_tx)?;
        db_tx.commit()?;

        // Insert new-format data with all fields
        let entity = UserEntity::with_proton_user_fields(
            "user2".to_string(),
            "New User".to_string(),
            "new@example.com".to_string(),
            Some(1024),                       // used_space
            Some("USD".to_string()),          // currency
            Some(100),                        // credit
            Some(1234567890),                 // create_time
            Some(2048),                       // max_space
            Some(512),                        // max_upload
            Some(1),                          // role
            Some(0),                          // private
            Some(1),                          // subscribed
            Some(2),                          // services
            Some(0),                          // delinquent
            Some("org_key".to_string()),      // organization_private_key
            Some("Display Name".to_string()), // display_name
            Some(1),                          // mnemonic_status
        );

        // Save using Db::save (which serializes to JSON)
        db.save("users", &entity)?;

        // Retrieve
        let retrieved: Option<UserEntity> = db.get("users", "user2")?;
        assert!(retrieved.is_some(), "Should retrieve the inserted user");
        let retrieved = retrieved.expect("Expected user to be retrieved from database");
        assert_eq!(retrieved.id, entity.id);
        assert_eq!(retrieved.name, entity.name);
        assert_eq!(retrieved.email, entity.email);
        assert_eq!(retrieved.used_space, Some(1024));
        assert_eq!(retrieved.currency, Some("USD".to_string()));
        assert_eq!(retrieved.credit, Some(100));
        assert_eq!(retrieved.display_name, Some("Display Name".to_string()));

        Ok(())
    }

    #[test]
    fn test_migration_from_v1_to_v2() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        // Step 1: Run v1 migration
        Db::migrate_schema(&db_tx, UserEntity::SCHEME_NAME, &[&UserEntity::schema_v1()])?;
        let version_v1 = Db::schema_version(&db_tx, UserEntity::SCHEME_NAME)?;
        assert_eq!(version_v1, Some(0), "Version should be 0 after v1");

        // Insert data with v1 schema
        db_tx.execute(
            "INSERT INTO users (id, name, email) VALUES (?1, ?2, ?3)",
            ["migrated_user", "Migrated User", "migrated@example.com"],
        )?;
        db_tx.commit()?;

        // Step 2: Run v2 migration
        let db_tx2 = db.get_transaction()?;
        Db::migrate_schema(
            &db_tx2,
            UserEntity::SCHEME_NAME,
            &[&UserEntity::schema_v1(), &UserEntity::schema_v2()],
        )?;
        let version_v2 = Db::schema_version(&db_tx2, UserEntity::SCHEME_NAME)?;
        assert_eq!(version_v2, Some(1), "Version should be 1 after v2");

        // Verify data still exists
        let (name, email): (String, String) = db_tx2.query_row(
            "SELECT name, email FROM users WHERE id = ?1",
            ["migrated_user"],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )?;
        assert_eq!(name, "Migrated User");
        assert_eq!(email, "migrated@example.com");

        // Verify new columns exist and can be updated
        db_tx2.execute(
            "UPDATE users SET used_space = ?1, currency = ?2 WHERE id = ?3",
            rusqlite::params![1024i64, "USD", "migrated_user"],
        )?;

        let (used_space, currency): (Option<i64>, Option<String>) = db_tx2.query_row(
            "SELECT used_space, currency FROM users WHERE id = ?1",
            ["migrated_user"],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )?;
        assert_eq!(used_space, Some(1024));
        assert_eq!(currency, Some("USD".to_string()));

        db_tx2.commit()?;
        Ok(())
    }

    #[test]
    fn test_schema_v1_content() {
        let schema = UserEntity::schema_v1();

        assert!(
            schema.contains("CREATE TABLE"),
            "Schema should create table"
        );
        assert!(schema.contains("users"), "Schema should create users table");
        assert!(
            schema.contains("id TEXT"),
            "Schema should have id TEXT column"
        );
        assert!(
            schema.contains("name TEXT"),
            "Schema should have name TEXT column"
        );
        assert!(
            schema.contains("email TEXT"),
            "Schema should have email TEXT column"
        );
        assert!(
            schema.contains("PRIMARY KEY"),
            "Schema should define primary key"
        );
    }

    #[test]
    fn test_schema_v2_content() {
        let schema = UserEntity::schema_v2();

        assert!(schema.contains("ALTER TABLE"), "Schema should alter table");
        assert!(schema.contains("users"), "Schema should alter users table");
        assert!(schema.contains("ADD COLUMN"), "Schema should add columns");
        assert!(
            schema.contains("used_space"),
            "Schema should add used_space column"
        );
        assert!(
            schema.contains("currency"),
            "Schema should add currency column"
        );
        assert!(schema.contains("credit"), "Schema should add credit column");
        assert!(
            schema.contains("display_name"),
            "Schema should add display_name column"
        );
    }

    #[test]
    fn test_from_user_entity_to_user() {
        let entity = UserEntity::new(
            "user1".to_string(),
            "Test".to_string(),
            "test@example.com".to_string(),
        );
        let user = ProtonUser::from(entity);

        assert_eq!(user.id, "user1");
        assert_eq!(user.name, "Test");
        assert_eq!(user.email, "test@example.com");
    }

    #[test]
    fn test_from_user_to_user_entity() {
        let user = ProtonUser {
            id: "user1".to_string(),
            name: "Test".to_string(),
            email: "test@example.com".to_string(),
            used_space: 2220,
            subscribed: 1,
            ..Default::default()
        };
        let entity: UserEntity = user.into();

        assert_eq!(entity.id, "user1");
        assert_eq!(entity.name, "Test");
        assert_eq!(entity.email, "test@example.com");
        // All optional fields should be None
        assert_eq!(entity.used_space, Some(2220));
        assert_eq!(entity.subscribed, Some(1));
    }

    #[test]
    fn test_from_proton_user_to_user_entity() {
        let proton_user = ProtonUser {
            id: "proton_user1".to_string(),
            name: "Proton User".to_string(),
            email: "proton@example.com".to_string(),
            used_space: 2048,
            currency: "EUR".to_string(),
            credit: 200,
            create_time: 1234567890,
            max_space: 4096,
            max_upload: 1024,
            role: 2,
            private: 1,
            subscribed: 1,
            services: 3,
            delinquent: 0,
            organization_private_key: Some("org_key_123".to_string()),
            display_name: Some("Proton Display".to_string()),
            keys: None,
            mnemonic_status: 1,
            flags: None,
        };

        let entity: UserEntity = proton_user.into();

        assert_eq!(entity.id, "proton_user1");
        assert_eq!(entity.name, "Proton User");
        assert_eq!(entity.email, "proton@example.com");
        assert_eq!(entity.used_space, Some(2048));
        assert_eq!(entity.currency, Some("EUR".to_string()));
        assert_eq!(entity.credit, Some(200));
        assert_eq!(entity.display_name, Some("Proton Display".to_string()));
        assert_eq!(
            entity.organization_private_key,
            Some("org_key_123".to_string())
        );
    }
}
