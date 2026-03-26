use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

use meet_identifiers::GroupId;
use mls_trait::{Entity, InsertOutput, KvError, KvExt, MlsEntity, MlsGroupEntity};

type Table = HashMap<String, serde_json::Value>;

#[derive(Debug, Clone)]
pub struct MemKv(Arc<Mutex<HashMap<&'static str, Table>>>);

impl Default for MemKv {
    fn default() -> Self {
        Self::new()
    }
}

impl MemKv {
    pub fn new() -> Self {
        Self(Arc::new(Mutex::new(HashMap::new())))
    }

    pub async fn group(&self, id: &GroupId) -> Result<String, KvError> {
        let g = self
            .maybe_get::<MlsGroupEntity>(id)
            .await
            .map_err(|e| KvError::NotFound(e.to_string()))?
            .ok_or(KvError::NotFound(id.to_string()))?;

        serde_json::to_string_pretty(&g).map_err(|e| KvError::SerializationError(e.to_string()))
    }
}

unsafe impl Send for MemKv {}
unsafe impl Sync for MemKv {}

impl KvExt for MemKv {
    async fn maybe_get<V: MlsEntity>(&self, key: &<V as Entity>::Id) -> Result<Option<V>, KvError> {
        let mut db = self
            .0
            .lock()
            .map_err(|e| KvError::NotFound(e.to_string()))?;
        let table = db.entry(V::TABLE_NAME).or_default();
        let value = table.get(&key.to_string());
        let value = value
            .map(|v| serde_json::from_value(v.clone()))
            .transpose()
            .map_err(|e| KvError::SerializationError(e.to_string()))?;
        Ok(value)
    }

    async fn insert<V: MlsEntity>(&self, value: &V) -> Result<InsertOutput, KvError> {
        let mut db = self
            .0
            .lock()
            .map_err(|e| KvError::NotFound(e.to_string()))?;
        let table = db.entry(V::TABLE_NAME).or_default();

        let key = value.id().to_string();
        if table.contains_key(&key) {
            return Ok(InsertOutput::AlreadyExists);
        }

        let value =
            serde_json::to_value(value).map_err(|e| KvError::SerializationError(e.to_string()))?;
        table.insert(key, value);
        Ok(InsertOutput::Inserted)
    }

    async fn set<V: MlsEntity>(&self, value: &V) -> Result<(), KvError> {
        let mut db = self
            .0
            .lock()
            .map_err(|e| KvError::NotFound(e.to_string()))?;
        let table = db.entry(V::TABLE_NAME).or_default();

        let key = value.id().to_string();
        let value =
            serde_json::to_value(value).map_err(|e| KvError::SerializationError(e.to_string()))?;
        table.insert(key, value);
        Ok(())
    }

    async fn set_all<V: MlsEntity>(&self, values: Vec<V>) -> Result<(), KvError> {
        let mut db = self
            .0
            .lock()
            .map_err(|e| KvError::NotFound(e.to_string()))?;
        let table = db.entry(V::TABLE_NAME).or_default();

        for value in values {
            let key = value.id().to_string();
            let value = serde_json::to_value(&value)
                .map_err(|e| KvError::SerializationError(e.to_string()))?;
            table.insert(key, value);
        }
        Ok(())
    }

    async fn remove<V: MlsEntity>(&self, key: &<V as Entity>::Id) -> Result<(), KvError> {
        let mut db = self
            .0
            .lock()
            .map_err(|e| KvError::NotFound(e.to_string()))?;
        let table = db.entry(V::TABLE_NAME).or_default();

        let key = key.to_string();
        match table.remove(&key) {
            Some(_) => Ok(()),
            None => Err(KvError::NotFound(key)),
        }
    }

    async fn remove_all<V: MlsEntity>(
        &self,
        keys: impl ExactSizeIterator<Item = <V as Entity>::Id> + Send,
    ) -> Result<(), KvError> {
        let mut db = self
            .0
            .lock()
            .map_err(|e| KvError::NotFound(e.to_string()))?;
        let table = db.entry(V::TABLE_NAME).or_default();

        for key in keys {
            table.remove(&key.to_string());
        }
        Ok(())
    }

    async fn get_all<V: MlsEntity>(&self) -> Result<Vec<V>, KvError> {
        let mut db = self
            .0
            .lock()
            .map_err(|e| KvError::NotFound(e.to_string()))?;
        let table = db.entry(V::TABLE_NAME).or_default();

        table
            .values()
            .map(|v| {
                serde_json::from_value(v.clone())
                    .map_err(|e| KvError::DeserializationError(e.to_string()))
            })
            .collect::<Result<Vec<V>, KvError>>()
    }

    async fn count<V: MlsEntity>(&self) -> Result<u32, KvError> {
        let mut db = self
            .0
            .lock()
            .map_err(|e| KvError::NotFound(e.to_string()))?;
        let table = db.entry(V::TABLE_NAME).or_default();
        Ok(table.len() as u32)
    }
}
