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
        db_tx
            .commit()
            .map_err(|error| StorageError::Db { source: error })?;
        Ok(())
    }
}

/// Table name for schemas.
pub const SCHEMAS_TABLE_NAME: &str = "meet_schemas";

impl Db {
    #[cfg(test)]
    pub(crate) fn from_connection(conn: Connection) -> Self {
        Self(conn)
    }

    pub fn get_transaction(&mut self) -> Result<Transaction<'_>, StorageError> {
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
        Self::log_query(&query_str, &values);
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
        Self::log_query(&query_str, &values);
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
        Self::log_query(&query_str, &[SqlValue::Text(id.to_string())]);
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
        Self::log_query(&query_str, &[SqlValue::Text(id.to_string())]);
        let mut stmt = self.0.prepare(&query_str)?;
        let result = stmt.execute(value);
        match result {
            Ok(rows_affected) => Ok(rows_affected),
            Err(e) => {
                tracing::warn!(target: "meet_core::storage::sqlite", error = %e, "delete row failed");
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
            let sql_value = SqlValue::try_from(row.get_ref(i)?).map_err(rusqlite::Error::from)?;
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

    pub(crate) fn build_replace_statement<S: Serialize>(
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

    /// Formats a query for debug logging. Never includes raw text parameter values.
    pub(crate) fn format_query(query: &str, values: &[SqlValue]) -> String {
        format!(
            "db> {query}\nvalues: [{}]",
            values
                .iter()
                .map(Self::format_sql_value_for_log)
                .collect::<Vec<_>>()
                .join(",")
        )
    }

    fn format_sql_value_for_log(value: &SqlValue) -> String {
        match value {
            SqlValue::Blob(bytes) => format!("Blob({})", bytes.len()),
            SqlValue::Text(text) => format!("Text(len={})", text.len()),
            other => format!("{other:?}"),
        }
    }

    /// Logs SQL with redacted bound values (`format_query` never prints text/blob contents).
    fn log_query(query: &str, values: &[SqlValue]) {
        tracing::trace!(
            target: "meet_core::storage::sqlite",
            "{}",
            Self::format_query(query, values)
        );
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
