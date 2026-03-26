use std::collections::HashMap;
use std::ops::Deref;

use rusqlite::types::Value as SqlValue;
use rusqlite::{named_params, Connection, OptionalExtension, Row, Transaction};
use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::{Number, Value};

use super::{error::StorageError, persister::Database};

pub struct Db(Connection);

impl Deref for Db {
    type Target = Connection;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl Database for Db {
    async fn open(path: &str) -> Result<Self, StorageError> {
        let conn =
            rusqlite::Connection::open(path).map_err(|error| StorageError::Db { source: error })?;
        Ok(Self(conn))
    }

    fn init_tables(&mut self) -> Result<(), StorageError> {
        let db_tx = self
            .0
            .transaction()
            .map_err(|error| StorageError::Db { source: error })?;
        Self::init_schemas_table(&db_tx)?;
        Ok(())
    }
}

/// Table name for schemas.
pub const SCHEMAS_TABLE_NAME: &str = "meet_schemas";

impl Db {
    pub fn get_transaction(&mut self) -> Result<Transaction, StorageError> {
        self.0
            .transaction()
            .map_err(|error| StorageError::Db { source: error })
    }

    pub fn migrate_schema(
        db_tx: &Transaction,
        schema_name: &str,
        versioned_scripts: &[&str],
    ) -> Result<(), StorageError> {
        Self::init_schemas_table(db_tx)?;
        let current_version = Self::schema_version(db_tx, schema_name)?;
        let exec_from = current_version.map_or(0_usize, |v| v as usize + 1);
        let scripts_to_exec = versioned_scripts.iter().enumerate().skip(exec_from);
        for (version, script) in scripts_to_exec {
            Self::set_schema_version(db_tx, schema_name, version as u32)?;
            db_tx.execute_batch(script)?;
        }
        Ok(())
    }

    pub fn init_schemas_table(db_tx: &Transaction) -> Result<(), StorageError> {
        let sql = format!(
            "CREATE TABLE IF NOT EXISTS {SCHEMAS_TABLE_NAME}( name TEXT PRIMARY KEY NOT NULL, version INTEGER NOT NULL ) STRICT"
        );
        println!("sql: {sql}");
        db_tx
            .execute(&sql, ())
            .map_err(|error| StorageError::Db { source: error })?;
        Ok(())
    }

    /// Get schema version of `schema_name`.
    pub fn schema_version(db_tx: &Transaction, schema_name: &str) -> rusqlite::Result<Option<u32>> {
        let sql = format!("SELECT version FROM {SCHEMAS_TABLE_NAME} WHERE name=:name");
        db_tx
            .query_row(&sql, named_params! { ":name": schema_name }, |row| {
                row.get::<_, u32>("version")
            })
            .optional()
    }

    /// Set the `schema_version` of `schema_name`.
    pub fn set_schema_version(
        db_tx: &Transaction,
        schema_name: &str,
        schema_version: u32,
    ) -> rusqlite::Result<()> {
        let sql =
            format!("REPLACE INTO {SCHEMAS_TABLE_NAME}(name, version) VALUES(:name, :version)");
        db_tx.execute(
            &sql,
            named_params! { ":name": schema_name, ":version": schema_version },
        )?;
        Ok(())
    }

    pub fn save<S: Serialize>(&self, table_name: &str, value: S) -> Result<(), StorageError> {
        let (query_str, values) = Self::build_replace_statement(table_name, value)?;
        tracing::debug!("{}", Self::format_query(&query_str, &values));
        let mut stmt = self.0.prepare(&query_str)?;
        stmt.execute(rusqlite::params_from_iter(values))?;
        Ok(())
    }

    pub fn save_tx<S: Serialize>(
        db_tx: &Transaction,
        table_name: &str,
        value: S,
    ) -> Result<(), StorageError> {
        let (query_str, values) = Self::build_replace_statement(table_name, value)?;
        tracing::debug!("{}", Self::format_query(&query_str, &values));
        let mut stmt = db_tx.prepare(&query_str)?;
        stmt.execute(rusqlite::params_from_iter(values))?;
        Ok(())
    }

    pub fn get<S: DeserializeOwned>(
        &self,
        table_name: &str,
        id: &str,
    ) -> Result<Option<S>, StorageError> {
        let query_str = format!("SELECT * FROM {table_name} WHERE id = ?");
        let value = [id];
        tracing::debug!("db> {query_str}\nvalues: {value:?}");
        let mut stmt = self.0.prepare(&query_str)?;
        let mut rows = stmt.query(value)?;
        let row_result = rows.next()?.ok_or_else(|| StorageError::NotFound {
            table: table_name.to_owned(),
            key: id.to_owned(),
        });
        let row = match row_result {
            Ok(row) => row,
            Err(_) => return Ok(None),
        };
        let raw_row = Self::parse_row(row)?;
        let json_value = serde_json::to_string(&raw_row)?;
        let value = serde_json::from_str::<S>(&json_value)?;
        Ok(Some(value))
    }

    pub fn delete(&self, table_name: &str, id: &str) -> Result<usize, StorageError> {
        let query_str = format!("DELETE FROM {table_name} WHERE id = ?");
        let value = [id];
        tracing::debug!("db> {query_str}\nvalues: {value:?}");
        let mut stmt = self.0.prepare(&query_str)?;
        let result = stmt.execute(value);
        match result {
            Ok(rows_affected) => Ok(rows_affected),
            Err(e) => {
                // tracing::error!("Failed to delete row: {e}");
                println!("Failed to delete row: {e:?}");
                Err(StorageError::Db { source: e })
            }
        }
    }

    /// Resets a table by deleting all rows.
    ///
    /// This function removes all data from the specified table but keeps the table structure intact.
    /// Returns the number of rows deleted.
    pub fn reset_table(&self, table_name: &str) -> Result<usize, StorageError> {
        let query_str = format!("DELETE FROM {table_name}");
        tracing::debug!("db> {query_str}");
        let mut stmt = self.0.prepare(&query_str)?;
        let rows_affected = stmt
            .execute([])
            .map_err(|error| StorageError::Db { source: error })?;
        Ok(rows_affected)
    }

    /// Resets a table by deleting all rows within a transaction.
    ///
    /// This function removes all data from the specified table but keeps the table structure intact.
    /// Returns the number of rows deleted.
    pub fn reset_table_tx(db_tx: &Transaction, table_name: &str) -> Result<usize, StorageError> {
        let query_str = format!("DELETE FROM {table_name}");
        tracing::debug!("db> {query_str}");
        let mut stmt = db_tx.prepare(&query_str)?;
        let rows_affected = stmt
            .execute([])
            .map_err(|error| StorageError::Db { source: error })?;
        Ok(rows_affected)
    }

    /// Drops a table completely, removing both data and schema.
    ///
    /// This function permanently removes the table from the database.
    /// Use with caution as this operation cannot be undone.
    pub fn drop_table(&self, table_name: &str) -> Result<(), StorageError> {
        let query_str = format!("DROP TABLE IF EXISTS {table_name}");
        tracing::debug!("db> {query_str}");
        self.0
            .execute(&query_str, [])
            .map_err(|error| StorageError::Db { source: error })?;
        Ok(())
    }

    /// Drops a table completely within a transaction, removing both data and schema.
    ///
    /// This function permanently removes the table from the database.
    /// Use with caution as this operation cannot be undone.
    pub fn drop_table_tx(db_tx: &Transaction, table_name: &str) -> Result<(), StorageError> {
        let query_str = format!("DROP TABLE IF EXISTS {table_name}");
        tracing::debug!("db> {query_str}");
        db_tx
            .execute(&query_str, [])
            .map_err(|error| StorageError::Db { source: error })?;
        Ok(())
    }

    /// Resets a table and its schema by dropping the table and resetting the schema version.
    ///
    /// This function:
    /// 1. Drops the table completely (removes data and schema)
    /// 2. Resets the schema version for the given schema name
    ///
    /// After calling this function, you can recreate the table by running migrations again.
    /// The schema_name should match the SCHEME_NAME constant from the entity (e.g., "User").
    pub fn reset_table_and_schema(
        &mut self,
        table_name: &str,
        schema_name: &str,
    ) -> Result<(), StorageError> {
        let db_tx = self.get_transaction()?;
        Self::drop_table_tx(&db_tx, table_name)?;

        Self::delete_schema_version_tx(&db_tx, schema_name)?;

        db_tx
            .commit()
            .map_err(|error| StorageError::Db { source: error })?;
        Ok(())
    }

    /// Resets a table and its schema within a transaction by dropping the table and resetting the schema version.
    ///
    /// This function:
    /// 1. Drops the table completely (removes data and schema)
    /// 2. Resets the schema version for the given schema name
    ///
    /// After calling this function, you can recreate the table by running migrations again.
    /// The schema_name should match the SCHEME_NAME constant from the entity (e.g., "User").
    pub fn reset_table_and_schema_tx(
        db_tx: &Transaction,
        table_name: &str,
        schema_name: &str,
    ) -> Result<(), StorageError> {
        Self::drop_table_tx(db_tx, table_name)?;

        Self::delete_schema_version_tx(db_tx, schema_name)?;

        Ok(())
    }

    /// Converts a JSON value to its corresponding SQL representation,
    /// handling arrays and maps by converting them to blobs.
    pub(crate) fn json_value_to_sql(value: Value) -> Result<SqlValue, StorageError> {
        let sql = match value {
            Value::Null => SqlValue::Null,
            Value::Bool(b) => SqlValue::Integer(b as i64),
            Value::Number(n) => {
                if let Some(v) = n.as_i64() {
                    SqlValue::Integer(v)
                } else if let Some(v) = n.as_f64() {
                    SqlValue::Real(v)
                } else {
                    return Err(StorageError::Serde(format!(
                        "{n:?} has no valid SQL representation"
                    )));
                }
            }
            Value::String(s) => SqlValue::Text(s),
            Value::Array(_) | Value::Object(_) => {
                // Serialize the array or object to json bytes
                let bytes =
                    serde_json::to_vec(&value).map_err(|e| StorageError::Serde(e.to_string()))?;
                SqlValue::Blob(bytes)
            }
        };
        Ok(sql)
    }

    /// Parses a given `Row` to a type agnostic blob map
    pub fn parse_row(row: &Row) -> Result<HashMap<String, Value>, StorageError> {
        let count = row.as_ref().column_count();
        let mut raw_blob = HashMap::<String, Value>::with_capacity(count);
        for i in 0..count {
            let col = row.as_ref().column_name(i)?;
            let sql_value = row.get_ref(i)?.into();
            let value = match sql_value {
                SqlValue::Null => Value::Null,
                SqlValue::Integer(i) => Value::Number(Number::from(i)),
                SqlValue::Real(f) => Value::Number(
                    Number::from_f64(f)
                        .ok_or(StorageError::Serde(format!("`{f}` is an invalid number")))?,
                ),
                SqlValue::Text(s) => Value::String(s),
                SqlValue::Blob(bytes) => serde_json::from_slice(&bytes)?,
            };
            raw_blob.insert(col.to_owned(), value);
        }
        Ok(raw_blob)
    }

    fn build_replace_statement<S: Serialize>(
        table_name: &str,
        value: S,
    ) -> Result<(String, Vec<SqlValue>), StorageError> {
        let Some(raw_map) = serde_json::to_value(value)?.as_object().cloned() else {
            return Err(StorageError::Serde("Failed to convert value to map".into()));
        };

        let mut fields = Vec::with_capacity(raw_map.len());
        let mut placeholders = Vec::with_capacity(raw_map.len());
        let mut sql_values = Vec::with_capacity(raw_map.len());

        for (index, (field, json_value)) in raw_map.into_iter().enumerate() {
            fields.push(field);
            placeholders.push(format!("?{}", index + 1));
            sql_values.push(Self::json_value_to_sql(json_value)?);
        }

        let query_str = format!(
            "REPLACE INTO {table_name} ({}) VALUES ({})",
            fields.join(", "),
            placeholders.join(", ")
        );

        Ok((query_str, sql_values))
    }

    pub(crate) fn format_query(query: &str, values: &[SqlValue]) -> String {
        format!(
            "db> {query}\nvalues: [{}]",
            values
                .iter()
                .map(|v| match v {
                    SqlValue::Blob(bytes) => format!("Blob({})", bytes.len()),
                    other => format!("{other:?}"),
                })
                .collect::<Vec<_>>()
                .join(",")
        )
    }

    fn delete_schema_version_tx(
        db_tx: &Transaction,
        schema_name: &str,
    ) -> Result<(), StorageError> {
        let delete_schema_sql = format!("DELETE FROM {SCHEMAS_TABLE_NAME} WHERE name = ?");
        db_tx
            .execute(&delete_schema_sql, [schema_name])
            .map_err(|error| StorageError::Db { source: error })?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rusqlite::Connection;
    use serde::{Deserialize, Serialize};

    #[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
    struct TestEntity {
        id: String,
        name: String,
        value: i32,
        optional: Option<String>,
    }

    fn create_test_db() -> Db {
        let conn = Connection::open_in_memory().expect("Failed to create in-memory database");
        Db(conn)
    }

    fn setup_test_table(db: &Db) -> Result<(), StorageError> {
        db.0.execute(
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
        let mut stmt = db.0.prepare("SELECT * FROM test_table WHERE id = ?")?;
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
        let mut stmt = db.0.prepare("SELECT * FROM test_table WHERE id = ?")?;
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
        assert!(formatted.contains("Text(\"test\")"));
        assert!(formatted.contains("Blob(4)"));
    }

    #[test]
    fn test_parse_row_with_real() -> Result<(), StorageError> {
        let db = create_test_db();
        db.0.execute(
            "CREATE TABLE IF NOT EXISTS test_real (id TEXT PRIMARY KEY, value REAL)",
            [],
        )?;

        // Insert with proper REAL value
        db.0.execute(
            "INSERT INTO test_real (id, value) VALUES (?, ?)",
            rusqlite::params!["test-1", 2.5f64],
        )?;

        let mut stmt = db.0.prepare("SELECT * FROM test_real WHERE id = ?")?;
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
        db.0.execute(
            "CREATE TABLE IF NOT EXISTS test_blob (id TEXT PRIMARY KEY, data BLOB)",
            [],
        )?;

        // Insert a JSON blob
        let json_data = serde_json::json!({"key": "value"});
        let blob_bytes = serde_json::to_vec(&json_data)?;
        db.0.execute(
            "INSERT INTO test_blob (id, data) VALUES (?, ?)",
            rusqlite::params!["test-1", blob_bytes.as_slice()],
        )?;

        let mut stmt = db.0.prepare("SELECT * FROM test_blob WHERE id = ?")?;
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
}
