#[cfg(test)]
mod tests {
    use crate::infra::storage::sqlite::{Db, SCHEMAS_TABLE_NAME};
    use crate::infra::storage::{error::StorageError, persister::Database};
    use futures::executor::block_on;
    use rusqlite::types::Value as SqlValue;
    use rusqlite::Connection;
    use rusqlite::OptionalExtension;
    use serde::{Deserialize, Serialize};
    use serde_json::{Number, Value};

    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    struct TestEntity {
        id: String,
        name: String,
        value: i32,
        optional: Option<String>,
    }

    fn create_test_db() -> Db {
        let conn = Connection::open_in_memory().expect("Failed to create in-memory database");
        Db::from_connection(conn)
    }

    fn setup_test_table(db: &Db) -> Result<(), StorageError> {
        db.execute(
            "CREATE TABLE IF NOT EXISTS test_table (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                value INTEGER NOT NULL,
                optional TEXT
            )",
            [],
        )
        .map_err(|e| StorageError::Db { source: e })?;
        Ok(())
    }

    #[test]
    fn test_save_and_get() -> Result<(), StorageError> {
        let db = create_test_db();
        setup_test_table(&db)?;

        let entity = TestEntity {
            id: "test-1".to_string(),
            name: "Test Name".to_string(),
            value: 42,
            optional: Some("optional_value".to_string()),
        };

        db.save("test_table", &entity)?;

        let retrieved: Option<TestEntity> = db.get("test_table", "test-1")?;
        let retrieved = retrieved.expect("Expected entity to be retrieved from database");
        assert_eq!(retrieved, entity);

        Ok(())
    }

    #[test]
    fn test_save_overwrites_existing() -> Result<(), StorageError> {
        let db = create_test_db();
        setup_test_table(&db)?;

        let entity1 = TestEntity {
            id: "test-1".to_string(),
            name: "Original".to_string(),
            value: 10,
            optional: None,
        };

        let entity2 = TestEntity {
            id: "test-1".to_string(),
            name: "Updated".to_string(),
            value: 20,
            optional: Some("new_value".to_string()),
        };

        db.save("test_table", &entity1)?;
        db.save("test_table", &entity2)?;

        let retrieved: Option<TestEntity> = db.get("test_table", "test-1")?;
        let retrieved =
            retrieved.expect("Expected entity2 to be retrieved from database after save");
        assert_eq!(retrieved, entity2);

        Ok(())
    }

    #[test]
    fn test_get_nonexistent() -> Result<(), StorageError> {
        let db = create_test_db();
        setup_test_table(&db)?;

        let retrieved: Option<TestEntity> = db.get("test_table", "nonexistent")?;
        assert!(retrieved.is_none());

        Ok(())
    }

    #[test]
    fn test_delete() -> Result<(), StorageError> {
        let db = create_test_db();
        setup_test_table(&db)?;

        let entity = TestEntity {
            id: "test-1".to_string(),
            name: "Test".to_string(),
            value: 42,
            optional: None,
        };

        db.save("test_table", &entity)?;
        let rows_deleted = db.delete("test_table", "test-1")?;
        assert_eq!(rows_deleted, 1);

        let retrieved: Option<TestEntity> = db.get("test_table", "test-1")?;
        assert!(retrieved.is_none());

        Ok(())
    }

    #[test]
    fn test_delete_nonexistent() -> Result<(), StorageError> {
        let db = create_test_db();
        setup_test_table(&db)?;

        let rows_deleted = db.delete("test_table", "nonexistent")?;
        assert_eq!(rows_deleted, 0);

        Ok(())
    }

    #[test]
    fn test_reset_table() -> Result<(), StorageError> {
        let db = create_test_db();
        setup_test_table(&db)?;

        // Insert multiple rows
        for i in 0..5 {
            let entity = TestEntity {
                id: format!("test-{i}"),
                name: format!("Name {i}"),
                value: i,
                optional: None,
            };
            db.save("test_table", &entity)?;
        }

        // Reset table
        let rows_deleted = db.reset_table("test_table")?;
        assert_eq!(rows_deleted, 5);

        // Verify all rows are gone
        let retrieved: Option<TestEntity> = db.get("test_table", "test-0")?;
        assert!(retrieved.is_none());

        Ok(())
    }

    #[test]
    fn test_reset_empty_table() -> Result<(), StorageError> {
        let db = create_test_db();
        setup_test_table(&db)?;

        let rows_deleted = db.reset_table("test_table")?;
        assert_eq!(rows_deleted, 0);

        Ok(())
    }

    #[test]
    fn test_drop_table() -> Result<(), StorageError> {
        let db = create_test_db();
        setup_test_table(&db)?;

        let entity = TestEntity {
            id: "test-1".to_string(),
            name: "Test".to_string(),
            value: 42,
            optional: None,
        };

        db.save("test_table", &entity)?;
        db.drop_table("test_table")?;

        // Table should not exist, so query should fail
        let result: Result<Option<TestEntity>, StorageError> = db.get("test_table", "test-1");
        assert!(result.is_err());

        Ok(())
    }

    #[test]
    fn test_drop_nonexistent_table() -> Result<(), StorageError> {
        let db = create_test_db();

        // Should not error when dropping non-existent table
        db.drop_table("nonexistent_table")?;

        Ok(())
    }

    #[test]
    fn test_schema_versioning() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        // Initialize schemas table
        Db::init_schemas_table(&db_tx)?;

        // Check initial version (should be None)
        let version = Db::schema_version(&db_tx, "TestSchema")?;
        assert!(version.is_none());

        // Set version
        Db::set_schema_version(&db_tx, "TestSchema", 1)?;
        let version = Db::schema_version(&db_tx, "TestSchema")?;
        assert_eq!(version, Some(1));

        // Update version
        Db::set_schema_version(&db_tx, "TestSchema", 2)?;
        let version = Db::schema_version(&db_tx, "TestSchema")?;
        assert_eq!(version, Some(2));

        db_tx.commit()?;
        Ok(())
    }

    #[test]
    fn test_migrate_schema() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;

        let schema_v1 = "CREATE TABLE IF NOT EXISTS test_migration (id TEXT PRIMARY KEY)";
        let schema_v2 = "ALTER TABLE test_migration ADD COLUMN name TEXT";

        // First migration
        Db::migrate_schema(&db_tx, "TestMigration", &[schema_v1])?;
        let version = Db::schema_version(&db_tx, "TestMigration")?;
        assert_eq!(version, Some(0));

        // Verify table exists
        let table_exists = db_tx
            .query_row(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='test_migration'",
                [],
                |row| row.get::<_, String>(0),
            )
            .optional()?;
        assert!(table_exists.is_some());

        db_tx.commit()?;

        // Second migration
        let db_tx2 = db.get_transaction()?;
        Db::migrate_schema(&db_tx2, "TestMigration", &[schema_v1, schema_v2])?;
        let version = Db::schema_version(&db_tx2, "TestMigration")?;
        assert_eq!(version, Some(1));

        // Verify column was added
        let columns: Vec<String> = db_tx2
            .prepare("PRAGMA table_info(test_migration)")?
            .query_map([], |row| row.get::<_, String>(1))?
            .collect::<Result<_, _>>()?;
        assert!(columns.contains(&"name".to_string()));

        db_tx2.commit()?;
        Ok(())
    }

    #[test]
    fn test_reset_table_and_schema() -> Result<(), StorageError> {
        let mut db = create_test_db();
        setup_test_table(&db)?;

        // Set up schema version
        let db_tx = db.get_transaction()?;
        Db::init_schemas_table(&db_tx)?;
        Db::set_schema_version(&db_tx, "TestSchema", 2)?;
        db_tx.commit()?;

        // Insert data
        let entity = TestEntity {
            id: "test-1".to_string(),
            name: "Test".to_string(),
            value: 42,
            optional: None,
        };
        db.save("test_table", &entity)?;

        // Reset table and schema
        db.reset_table_and_schema("test_table", "TestSchema")?;

        // Verify table is gone
        let result: Result<Option<TestEntity>, StorageError> = db.get("test_table", "test-1");
        assert!(result.is_err());

        // Verify schema version is reset
        let db_tx2 = db.get_transaction()?;
        let version = Db::schema_version(&db_tx2, "TestSchema")?;
        assert!(version.is_none());
        db_tx2.commit()?;

        Ok(())
    }

    #[test]
    fn test_save_tx_and_reset_table_tx() -> Result<(), StorageError> {
        let mut db = create_test_db();
        setup_test_table(&db)?;

        let db_tx = db.get_transaction()?;

        // Save within transaction
        let entity = TestEntity {
            id: "test-1".to_string(),
            name: "Test".to_string(),
            value: 42,
            optional: None,
        };
        Db::save_tx(&db_tx, "test_table", &entity)?;

        // Reset within same transaction
        let rows_deleted = Db::reset_table_tx(&db_tx, "test_table")?;
        assert_eq!(rows_deleted, 1);

        db_tx.commit()?;

        // Verify table is empty
        let retrieved: Option<TestEntity> = db.get("test_table", "test-1")?;
        assert!(retrieved.is_none());

        Ok(())
    }

    #[test]
    fn test_json_value_to_sql() -> Result<(), StorageError> {
        // Test Null
        let sql_value = Db::json_value_to_sql(Value::Null)?;
        assert_eq!(sql_value, SqlValue::Null);

        // Test Bool
        let sql_value = Db::json_value_to_sql(Value::Bool(true))?;
        assert_eq!(sql_value, SqlValue::Integer(1));

        // Test Integer
        let sql_value = Db::json_value_to_sql(Value::Number(Number::from(42)))?;
        assert_eq!(sql_value, SqlValue::Integer(42));

        // Test Real
        let test_real = 2.5;
        let sql_value = Db::json_value_to_sql(Value::Number(Number::from_f64(test_real).unwrap()))?;
        match sql_value {
            SqlValue::Real(f) => assert!((f - test_real).abs() < 0.001),
            _ => panic!("Expected Real value"),
        }

        // Test String
        let sql_value = Db::json_value_to_sql(Value::String("test".to_string()))?;
        assert_eq!(sql_value, SqlValue::Text("test".to_string()));

        // Test Array (should be blob)
        let sql_value = Db::json_value_to_sql(Value::Array(vec![Value::Number(Number::from(1))]))?;
        match sql_value {
            SqlValue::Blob(_) => {}
            _ => panic!("Expected Blob for array"),
        }

        // Test Object (should be blob)
        let mut obj = serde_json::Map::new();
        obj.insert("key".to_string(), Value::String("value".to_string()));
        let sql_value = Db::json_value_to_sql(Value::Object(obj))?;
        match sql_value {
            SqlValue::Blob(_) => {}
            _ => panic!("Expected Blob for object"),
        }

        Ok(())
    }

    #[test]
    fn test_parse_row() -> Result<(), StorageError> {
        let db = create_test_db();
        setup_test_table(&db)?;

        // Insert test data
        let entity = TestEntity {
            id: "test-1".to_string(),
            name: "Test Name".to_string(),
            value: 42,
            optional: Some("optional".to_string()),
        };
        db.save("test_table", &entity)?;

        // Query and parse row
        let mut stmt = db.prepare("SELECT * FROM test_table WHERE id = ?")?;
        let mut rows = stmt.query(["test-1"])?;
        let row = rows.next()?.unwrap();

        let parsed = Db::parse_row(row)?;

        assert_eq!(parsed.get("id"), Some(&Value::String("test-1".to_string())));
        assert_eq!(
            parsed.get("name"),
            Some(&Value::String("Test Name".to_string()))
        );
        assert_eq!(parsed.get("value"), Some(&Value::Number(Number::from(42))));
        assert_eq!(
            parsed.get("optional"),
            Some(&Value::String("optional".to_string()))
        );

        Ok(())
    }

    #[test]
    fn test_parse_row_with_null() -> Result<(), StorageError> {
        let db = create_test_db();
        setup_test_table(&db)?;

        // Insert test data with null optional
        let entity = TestEntity {
            id: "test-1".to_string(),
            name: "Test Name".to_string(),
            value: 42,
            optional: None,
        };
        db.save("test_table", &entity)?;

        // Query and parse row
        let mut stmt = db.prepare("SELECT * FROM test_table WHERE id = ?")?;
        let mut rows = stmt.query(["test-1"])?;
        let row = rows.next()?.unwrap();

        let parsed = Db::parse_row(row)?;

        assert_eq!(parsed.get("optional"), Some(&Value::Null));

        Ok(())
    }

    #[test]
    fn test_reset_table_and_schema_tx() -> Result<(), StorageError> {
        let mut db = create_test_db();
        setup_test_table(&db)?;

        // Set up schema version
        let db_tx = db.get_transaction()?;
        Db::init_schemas_table(&db_tx)?;
        Db::set_schema_version(&db_tx, "TestSchema", 2)?;
        db_tx.commit()?;

        // Insert data
        let entity = TestEntity {
            id: "test-1".to_string(),
            name: "Test".to_string(),
            value: 42,
            optional: None,
        };
        db.save("test_table", &entity)?;

        // Reset table and schema within transaction
        let db_tx2 = db.get_transaction()?;
        Db::reset_table_and_schema_tx(&db_tx2, "test_table", "TestSchema")?;
        db_tx2.commit()?;

        // Verify table is gone
        let result: Result<Option<TestEntity>, StorageError> = db.get("test_table", "test-1");
        assert!(result.is_err());

        // Verify schema version is reset
        let db_tx3 = db.get_transaction()?;
        let version = Db::schema_version(&db_tx3, "TestSchema")?;
        assert!(version.is_none());
        db_tx3.commit()?;

        Ok(())
    }

    #[test]
    fn test_format_query() {
        use rusqlite::types::Value as SqlValue;

        let query = "SELECT * FROM test";
        let values = vec![
            SqlValue::Integer(42),
            SqlValue::Text("test".to_string()),
            SqlValue::Blob(vec![1, 2, 3, 4]),
        ];

        let formatted = Db::format_query(query, &values);
        assert!(formatted.contains("db> SELECT * FROM test"));
        assert!(formatted.contains("Integer(42)"));
        assert!(formatted.contains("Text(len=4)"));
        assert!(formatted.contains("Blob(4)"));
    }

    #[test]
    fn test_parse_row_with_real() -> Result<(), StorageError> {
        let db = create_test_db();
        db.execute(
            "CREATE TABLE IF NOT EXISTS test_real (id TEXT PRIMARY KEY, value REAL)",
            [],
        )?;

        // Insert with proper REAL value
        db.execute(
            "INSERT INTO test_real (id, value) VALUES (?, ?)",
            rusqlite::params!["test-1", 2.5f64],
        )?;

        let mut stmt = db.prepare("SELECT * FROM test_real WHERE id = ?")?;
        let mut rows = stmt.query(["test-1"])?;
        let row = rows.next()?.unwrap();

        let parsed = Db::parse_row(row)?;
        assert!(parsed.contains_key("value"));
        // Value should be a Number
        match parsed.get("value") {
            Some(Value::Number(n)) => {
                // Verify it's approximately 2.5
                if let Some(f) = n.as_f64() {
                    assert!((f - 2.5).abs() < 0.001);
                } else {
                    panic!("Expected f64 number");
                }
            }
            _ => panic!("Expected Number for REAL value"),
        }

        Ok(())
    }

    #[test]
    fn test_parse_row_with_blob() -> Result<(), StorageError> {
        let db = create_test_db();
        db.execute(
            "CREATE TABLE IF NOT EXISTS test_blob (id TEXT PRIMARY KEY, data BLOB)",
            [],
        )?;

        // Insert a JSON blob
        let json_data = serde_json::json!({"key": "value"});
        let blob_bytes = serde_json::to_vec(&json_data)?;
        db.execute(
            "INSERT INTO test_blob (id, data) VALUES (?, ?)",
            rusqlite::params!["test-1", blob_bytes.as_slice()],
        )?;

        let mut stmt = db.prepare("SELECT * FROM test_blob WHERE id = ?")?;
        let mut rows = stmt.query(["test-1"])?;
        let row = rows.next()?.unwrap();

        let parsed = Db::parse_row(row)?;
        assert!(parsed.contains_key("data"));
        // Value should be an Object (deserialized from blob)
        match parsed.get("data") {
            Some(Value::Object(obj)) => {
                assert_eq!(obj.get("key"), Some(&Value::String("value".to_string())));
            }
            _ => panic!("Expected Object for BLOB value"),
        }

        Ok(())
    }

    #[test]
    fn test_build_replace_statement_with_non_object() {
        // Test error case: value that's not an object
        let array_value = vec![1, 2, 3];
        let result = Db::build_replace_statement("test_table", &array_value);
        assert!(result.is_err());
        match result.unwrap_err() {
            StorageError::Serde(msg) => {
                assert!(msg.contains("Failed to convert value to map"));
            }
            _ => panic!("Expected Serde error"),
        }
    }

    #[test]
    fn test_delete_error_path() -> Result<(), StorageError> {
        let db = create_test_db();
        // Don't create table - this should cause an error when trying to delete
        let result = db.delete("nonexistent_table", "test-1");
        assert!(result.is_err());

        Ok(())
    }

    #[test]
    fn test_json_value_to_sql_array() -> Result<(), StorageError> {
        let array = Value::Array(vec![Value::Number(Number::from(1))]);
        let sql_value = Db::json_value_to_sql(array)?;
        match sql_value {
            SqlValue::Blob(bytes) => {
                // Verify it's valid JSON
                let parsed: Value = serde_json::from_slice(&bytes)?;
                assert!(parsed.is_array());
            }
            _ => panic!("Expected Blob for array"),
        }
        Ok(())
    }

    #[test]
    fn test_json_value_to_sql_object() -> Result<(), StorageError> {
        let mut obj = serde_json::Map::new();
        obj.insert("key".to_string(), Value::String("value".to_string()));
        let object = Value::Object(obj);
        let sql_value = Db::json_value_to_sql(object)?;
        match sql_value {
            SqlValue::Blob(bytes) => {
                // Verify it's valid JSON
                let parsed: Value = serde_json::from_slice(&bytes)?;
                assert!(parsed.is_object());
            }
            _ => panic!("Expected Blob for object"),
        }
        Ok(())
    }

    #[test]
    fn test_database_open_and_init_tables() -> Result<(), StorageError> {
        let dir = tempfile::tempdir()?;
        let path = dir.path().join("meet_open.sqlite");
        let path_str = path.to_str().expect("utf-8 path");

        let mut db = block_on(Db::open(path_str))?;
        db.init_tables()?;

        let count: i64 = db.query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?",
            [SCHEMAS_TABLE_NAME],
            |row| row.get(0),
        )?;
        assert_eq!(count, 1);

        Ok(())
    }

    #[test]
    fn test_migrate_schema_empty_script_list() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let db_tx = db.get_transaction()?;
        Db::migrate_schema(&db_tx, "NoScripts", &[])?;
        assert_eq!(Db::schema_version(&db_tx, "NoScripts")?, None);
        db_tx.commit()?;
        Ok(())
    }

    #[test]
    fn test_migrate_schema_second_run_is_noop() -> Result<(), StorageError> {
        let mut db = create_test_db();
        let s1 = "CREATE TABLE IF NOT EXISTS t_mig (id TEXT PRIMARY KEY)";
        let s2 = "ALTER TABLE t_mig ADD COLUMN x INTEGER";

        let db_tx = db.get_transaction()?;
        Db::migrate_schema(&db_tx, "M", &[s1, s2])?;
        assert_eq!(Db::schema_version(&db_tx, "M")?, Some(1));
        db_tx.commit()?;

        let db_tx2 = db.get_transaction()?;
        Db::migrate_schema(&db_tx2, "M", &[s1, s2])?;
        assert_eq!(Db::schema_version(&db_tx2, "M")?, Some(1));
        db_tx2.commit()?;

        Ok(())
    }

    #[test]
    fn test_drop_table_tx_committed() -> Result<(), StorageError> {
        let mut db = create_test_db();
        setup_test_table(&db)?;

        let db_tx = db.get_transaction()?;
        Db::drop_table_tx(&db_tx, "test_table")?;
        db_tx.commit()?;

        let err = db.get::<TestEntity>("test_table", "any");
        assert!(err.is_err());
        Ok(())
    }

    #[test]
    fn test_save_tx_rollback_leaves_table_empty() -> Result<(), StorageError> {
        let mut db = create_test_db();
        setup_test_table(&db)?;

        let entity = TestEntity {
            id: "rolled".to_string(),
            name: "N".to_string(),
            value: 1,
            optional: None,
        };

        {
            let db_tx = db.get_transaction()?;
            Db::save_tx(&db_tx, "test_table", &entity)?;
            // Drop without commit → rollback
        }

        let retrieved: Option<TestEntity> = db.get("test_table", "rolled")?;
        assert!(retrieved.is_none());
        Ok(())
    }

    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    struct EntityWithJson {
        id: String,
        tags: Value,
    }

    #[test]
    fn test_save_get_roundtrip_nested_json_in_value_field() -> Result<(), StorageError> {
        let db = create_test_db();
        db.execute(
            "CREATE TABLE IF NOT EXISTS t_json (id TEXT PRIMARY KEY, tags BLOB)",
            [],
        )?;

        let entity = EntityWithJson {
            id: "e1".to_string(),
            tags: serde_json::json!([1, {"nested": true}, null]),
        };

        db.save("t_json", &entity)?;
        let got: Option<EntityWithJson> = db.get("t_json", "e1")?;
        assert_eq!(got.as_ref(), Some(&entity));
        Ok(())
    }

    #[test]
    fn test_parse_row_blob_invalid_json_errors() -> Result<(), StorageError> {
        let db = create_test_db();
        db.execute(
            "CREATE TABLE IF NOT EXISTS t_bad (id TEXT PRIMARY KEY, data BLOB)",
            [],
        )?;
        db.execute(
            "INSERT INTO t_bad (id, data) VALUES ('x', ?)",
            [b"{ not json".as_slice()],
        )?;

        let mut stmt = db.prepare("SELECT * FROM t_bad WHERE id = 'x'")?;
        let mut rows = stmt.query([])?;
        let row = rows.next()?.unwrap();

        let err = Db::parse_row(row).unwrap_err();
        match err {
            StorageError::Serde(_) => {}
            other => panic!("expected Serde error, got {other:?}"),
        }
        Ok(())
    }

    #[test]
    fn test_parse_row_real_infinity_errors() -> Result<(), StorageError> {
        let db = create_test_db();
        db.execute(
            "CREATE TABLE IF NOT EXISTS t_inf (id TEXT PRIMARY KEY, v REAL)",
            [],
        )?;
        // Literal overflows IEEE double → SQLite stores +inf; serde_json rejects it as JSON Number.
        db.execute("INSERT INTO t_inf (id, v) VALUES ('i', 1e999)", [])?;

        let mut stmt = db.prepare("SELECT * FROM t_inf WHERE id = 'i'")?;
        let mut rows = stmt.query([])?;
        let row = rows.next()?.unwrap();

        let err = Db::parse_row(row).unwrap_err();
        match err {
            StorageError::Serde(msg) => {
                assert!(msg.contains("invalid number"));
            }
            other => panic!("expected Serde error, got {other:?}"),
        }
        Ok(())
    }

    #[test]
    fn test_json_value_to_sql_bool_false() -> Result<(), StorageError> {
        let sql_value = Db::json_value_to_sql(Value::Bool(false))?;
        assert_eq!(sql_value, SqlValue::Integer(0));
        Ok(())
    }

    #[test]
    fn test_format_query_redacts_long_text() {
        let private_key =
            "-----BEGIN PGP PRIVATE KEY BLOCK-----\nsecret\n-----END PGP PRIVATE KEY BLOCK-----";
        let values = vec![SqlValue::Text(private_key.to_string())];
        let formatted =
            Db::format_query("REPLACE INTO user_keys (private_key) VALUES (?1)", &values);
        assert!(!formatted.contains("BEGIN PGP"));
        assert!(!formatted.contains("secret"));
        assert!(formatted.contains("Text(len="));
        assert!(formatted.contains(&format!("Text(len={})", private_key.len())));
    }

    #[test]
    fn test_format_query_redacts_blob_content() {
        let secret = b"-----BEGIN PGP PRIVATE KEY BLOCK-----";
        let values = vec![SqlValue::Blob(secret.to_vec())];
        let formatted = Db::format_query("REPLACE INTO t (data) VALUES (?1)", &values);
        assert!(!formatted.contains("BEGIN PGP"));
        assert!(formatted.contains(&format!("Blob({})", secret.len())));
    }

    #[test]
    fn test_format_query_user_keys_replace_redacts_all_sensitive_fields() {
        let private_key =
            "-----BEGIN PGP PRIVATE KEY BLOCK-----\nsecret-key-bytes\n-----END PGP PRIVATE KEY BLOCK-----";
        let token = "super-secret-auth-token";
        let signature = "super-secret-signature";
        let values = vec![
            SqlValue::Text("key-id".to_string()),
            SqlValue::Text("user-id".to_string()),
            SqlValue::Text(private_key.to_string()),
            SqlValue::Text(token.to_string()),
            SqlValue::Text(signature.to_string()),
            SqlValue::Integer(1),
            SqlValue::Integer(1),
        ];
        let formatted = Db::format_query(
            "REPLACE INTO user_keys (id, user_id, private_key, token, signature, is_primary, active) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            &values,
        );

        assert!(formatted.contains("REPLACE INTO user_keys"));
        assert!(formatted.contains(&format!("Text(len={})", private_key.len())));
        assert!(formatted.contains(&format!("Text(len={})", token.len())));
        assert!(formatted.contains(&format!("Text(len={})", signature.len())));
        assert!(!formatted.contains("BEGIN PGP"));
        assert!(!formatted.contains("secret-key-bytes"));
        assert!(!formatted.contains(token));
        assert!(!formatted.contains(signature));
    }

    #[test]
    fn test_format_query_includes_null_and_real() {
        let values = vec![
            SqlValue::Null,
            SqlValue::Real(std::f64::consts::PI),
            SqlValue::Blob(vec![]),
        ];
        let s = Db::format_query("REPLACE INTO t (a) VALUES (?1)", &values);
        assert!(s.contains("Null"));
        assert!(s.contains("Real"));
        assert!(s.contains("Blob(0)"));
    }

    fn capture_trace_logs<F: FnOnce()>(f: F) -> String {
        use std::io::Write;
        use std::sync::{Arc, Mutex};
        use tracing_subscriber::fmt::MakeWriter;

        struct BufWriter(Arc<Mutex<Vec<u8>>>);
        impl Write for BufWriter {
            fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
                self.0.lock().unwrap().extend_from_slice(buf);
                Ok(buf.len())
            }
            fn flush(&mut self) -> std::io::Result<()> {
                Ok(())
            }
        }

        struct WriterFactory(Arc<Mutex<Vec<u8>>>);
        impl<'a> MakeWriter<'a> for WriterFactory {
            type Writer = BufWriter;
            fn make_writer(&'a self) -> Self::Writer {
                BufWriter(self.0.clone())
            }
        }

        let buf = Arc::new(Mutex::new(Vec::new()));
        let subscriber = tracing_subscriber::fmt()
            .with_max_level(tracing::Level::TRACE)
            .with_target(true)
            .without_time()
            .with_writer(WriterFactory(buf.clone()))
            .finish();

        tracing::subscriber::with_default(subscriber, f);

        let bytes = buf.lock().unwrap().clone();
        String::from_utf8(bytes).unwrap_or_default()
    }

    fn setup_user_keys_table(db: &mut Db) -> Result<(), StorageError> {
        use crate::infra::storage::entities::user_key::UserKeyEntity;

        let db_tx = db.get_transaction()?;
        Db::init_schemas_table(&db_tx)?;
        db_tx
            .execute(
                "CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, name TEXT, email TEXT)",
                [],
            )
            .map_err(|error| StorageError::Db { source: error })?;
        db_tx
            .execute(
                "INSERT OR IGNORE INTO users (id, name, email) VALUES (?1, ?2, ?3)",
                rusqlite::params!["user-1", "Test User", "user@example.com"],
            )
            .map_err(|error| StorageError::Db { source: error })?;
        UserKeyEntity::init_sqlite_tables(&db_tx)?;
        db_tx
            .commit()
            .map_err(|error| StorageError::Db { source: error })
    }

    #[test]
    fn save_user_key_trace_log_redacts_private_key_material() -> Result<(), StorageError> {
        use crate::infra::storage::entities::user_key::UserKeyEntity;

        let mut db = create_test_db();
        setup_user_keys_table(&mut db)?;

        let private_key = "-----BEGIN PGP PRIVATE KEY BLOCK-----\nTOP_SECRET_KEY_MATERIAL\n-----END PGP PRIVATE KEY BLOCK-----";
        let entity = UserKeyEntity::new(
            "key-1".into(),
            "user-1".into(),
            private_key.into(),
            Some("sensitive-token-value".into()),
            Some("sensitive-signature".into()),
            true,
            true,
        );

        let logs = capture_trace_logs(|| {
            db.save(UserKeyEntity::TABLE_NAME, &entity).unwrap();
        });

        assert!(logs.contains("meet_core::storage::sqlite"));
        assert!(logs.contains("REPLACE INTO user_keys"));
        assert!(logs.contains("Text(len="));
        assert!(!logs.contains("BEGIN PGP"));
        assert!(!logs.contains("TOP_SECRET_KEY_MATERIAL"));
        assert!(!logs.contains("sensitive-token-value"));
        assert!(!logs.contains("sensitive-signature"));

        Ok(())
    }

    #[test]
    fn get_trace_log_redacts_lookup_id() -> Result<(), StorageError> {
        let db = create_test_db();
        setup_test_table(&db)?;

        let entity = TestEntity {
            id: "lookup-id".to_string(),
            name: "Sensitive Name".to_string(),
            value: 99,
            optional: Some("optional-secret".to_string()),
        };
        db.save("test_table", &entity)?;

        let logs = capture_trace_logs(|| {
            let _: Option<TestEntity> = db.get("test_table", "lookup-id").unwrap();
        });

        assert!(logs.contains("SELECT * FROM test_table"));
        assert!(logs.contains("Text(len=9)")); // "lookup-id".len()
        assert!(!logs.contains("optional-secret"));
        assert!(!logs.contains("Sensitive Name"));

        Ok(())
    }
}
