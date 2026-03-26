use anyhow;
use std::ops::Deref;
use web_sys;

use super::persister::Database;
use crate::infra::storage::error::StorageError;
use idb::{Database as IndexedDB, DatabaseEvent, Factory, IndexParams, KeyPath};
use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_wasm_bindgen::Serializer;

pub struct Db(IndexedDB);

impl Db {
    const CURRENT_VERSION: u32 = 1;
    const MIGRATION_VERSIONS: [u32; 1] = [1];
}

impl Deref for Db {
    type Target = IndexedDB;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl Database for Db {
    async fn open(path: &str) -> Result<Self, StorageError> {
        let factory = match Factory::new() {
            Ok(f) => f,
            Err(e) => return Err(StorageError::Db { source: e }),
        };

        let mut open_request = match factory.open(path, Some(Self::CURRENT_VERSION)) {
            Ok(req) => req,
            Err(e) => return Err(StorageError::Db { source: e }),
        };

        open_request.on_upgrade_needed(|event| {
            let db = match event.database() {
                Ok(db) => db,
                Err(e) => {
                    web_sys::console::error_1(&format!("Failed to get database: {:?}", e).into());
                    return;
                }
            };

            // Get version info but ignore since we don't actually need it
            let _old_version = event.old_version().unwrap_or(0) as usize;

            // Check if the database is being deleted
            let Some(new_version) = event.new_version().unwrap_or(None).map(|v| v as usize) else {
                return;
            };

            for migration_version in &Self::MIGRATION_VERSIONS.to_vec()[_old_version..new_version] {
                match migration_version {
                    1 => {
                        if let Err(e) = Self::migrate_v1(&db) {
                            // We can't propagate the error through this callback
                            // but we can log it or handle it as needed
                            web_sys::console::error_1(&format!("Migration error: {:?}", e).into());
                        }
                    }
                    _ => {
                        web_sys::console::error_1(
                            &format!("Unsupported migration version: {}", migration_version).into(),
                        );
                    }
                }
            }
        });

        let db = match open_request.await {
            Ok(db) => db,
            Err(e) => return Err(StorageError::Db { source: e }),
        };

        Ok(Db(db))
    }

    fn init_tables(&mut self) -> Result<(), StorageError> {
        // For IndexedDB, tables (object stores) are created during the onupgradeneeded event
        // which happens in the open method, so there's nothing to do here.
        Ok(())
    }
}

impl Db {
    const JSON_SERIALIZER: Serializer = Serializer::json_compatible();

    pub async fn save<S: Serialize>(
        &self,
        table: &str,
        id: &str,
        value: S,
    ) -> Result<String, StorageError> {
        let jsvalue_id = id.serialize(&Self::JSON_SERIALIZER)?;
        let jsvalue = serde_wasm_bindgen::to_value(&value)?;
        let tr = self.transaction(&[table], idb::TransactionMode::ReadWrite)?;
        let store = tr.object_store(table)?;
        let new_key = store.put(&jsvalue, Some(&jsvalue_id))?.await?;
        debug_assert_eq!(new_key, jsvalue_id);
        Ok(id.to_owned())
    }

    pub async fn get<D: DeserializeOwned>(
        &self,
        table: &str,
        id: &str,
    ) -> Result<Option<D>, StorageError> {
        let id = id.serialize(&Self::JSON_SERIALIZER)?;
        let tr = self.transaction(&[table], idb::TransactionMode::ReadOnly)?;
        let store = tr.object_store(table)?;
        let jsvalue = store.get(id)?.await?;
        if let Some(jsvalue) = jsvalue {
            let value = serde_wasm_bindgen::from_value(jsvalue)?;
            Ok(Some(value))
        } else {
            Ok(None)
        }
    }

    pub async fn delete(&self, table: &str, id: &str) -> Result<usize, StorageError> {
        let id = id.serialize(&Self::JSON_SERIALIZER)?;
        let tr = self.transaction(&[table], idb::TransactionMode::ReadWrite)?;
        let store = tr.object_store(table)?;
        store.delete(id)?.await?;
        Ok(0)
    }

    pub async fn get_all_by_index<D: DeserializeOwned>(
        &self,
        table: &str,
        index_name: &str,
        query_value: &str,
    ) -> Result<Vec<D>, StorageError> {
        let query = query_value.serialize(&Self::JSON_SERIALIZER)?;
        let tr = self.transaction(&[table], idb::TransactionMode::ReadOnly)?;
        let store = tr.object_store(table)?;
        let index = store.index(index_name)?;
        let jsvalues = index.get_all(Some(idb::Query::Key(query)), None)?.await?;

        let mut results = Vec::new();
        for jsvalue in jsvalues {
            let value: D = serde_wasm_bindgen::from_value(jsvalue)?;
            results.push(value);
        }

        Ok(results)
    }

    fn migrate_v1(db: &IndexedDB) -> Result<(), anyhow::Error> {
        // Create users object store
        let user_store = match db.create_object_store("users", Default::default()) {
            Ok(store) => store,
            Err(e) => return Err(anyhow::anyhow!("Failed to create object store: {}", e)),
        };

        let user_column_names = [("id", true), ("name", false), ("email", false)];
        for (name, unique) in user_column_names {
            let mut index_params = IndexParams::new();
            index_params.unique(unique);

            if let Err(e) =
                user_store.create_index(name, KeyPath::new_single(name), Some(index_params))
            {
                return Err(anyhow::anyhow!("Failed to create index {}: {}", name, e));
            }
        }

        // Create user_keys object store
        let user_keys_store = match db.create_object_store("user_keys", Default::default()) {
            Ok(store) => store,
            Err(e) => {
                return Err(anyhow::anyhow!(
                    "Failed to create user_keys object store: {}",
                    e
                ))
            }
        };

        let user_keys_column_names = [
            ("id", false),
            ("user_id", false),
            ("private_key", false),
            ("token", false),
            ("signature", false),
            ("is_primary", false),
            ("active", false),
        ];
        for (name, unique) in user_keys_column_names {
            let mut index_params = IndexParams::new();
            index_params.unique(unique);

            if let Err(e) =
                user_keys_store.create_index(name, KeyPath::new_single(name), Some(index_params))
            {
                return Err(anyhow::anyhow!("Failed to create index {}: {}", name, e));
            }
        }

        Ok(())
    }
}
