use proton_meet_common::models::ProtonUserKey;
use serde::{Deserialize, Serialize};

#[cfg(not(target_family = "wasm"))]
use crate::infra::storage::{error::StorageError, persister::Db};
#[cfg(not(target_family = "wasm"))]
use rusqlite::Transaction;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UserKeyEntity {
    pub id: String,
    pub user_id: String,
    pub private_key: String,
    pub token: Option<String>,
    pub signature: Option<String>,
    #[serde(rename = "is_primary")]
    pub primary: bool,
    pub active: bool,
}

impl UserKeyEntity {
    pub const SCHEME_NAME: &str = "UserKey";
    pub const TABLE_NAME: &str = "user_keys";

    pub fn new(
        id: String,
        user_id: String,
        private_key: String,
        token: Option<String>,
        signature: Option<String>,
        primary: bool,
        active: bool,
    ) -> Self {
        Self {
            id,
            user_id,
            private_key,
            token,
            signature,
            primary,
            active,
        }
    }

    #[cfg(not(target_family = "wasm"))]
    pub(crate) fn schema_v1() -> String {
        r#"
        CREATE TABLE IF NOT EXISTS user_keys (
            id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            private_key TEXT NOT NULL,
            token TEXT,
            signature TEXT,
            is_primary BOOLEAN NOT NULL,
            active BOOLEAN NOT NULL,
            PRIMARY KEY (id, user_id),
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
    "#
        .to_owned()
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn init_sqlite_tables(db_tx: &Transaction) -> Result<(), StorageError> {
        Db::migrate_schema(db_tx, Self::SCHEME_NAME, &[&Self::schema_v1()])?;
        Ok(())
    }
}

impl From<UserKeyEntity> for ProtonUserKey {
    fn from(entity: UserKeyEntity) -> Self {
        ProtonUserKey {
            id: entity.id,
            version: 0,
            private_key: entity.private_key,
            recovery_secret: None,
            recovery_secret_signature: None,
            token: entity.token,
            fingerprint: String::new(),
            signature: entity.signature,
            primary: if entity.primary { 1 } else { 0 },
            active: if entity.active { 1 } else { 0 },
        }
    }
}

// impl From<ProtonUserKey> for UserKeyEntity {
//     fn from(key: ProtonUserKey) -> Self {
//         Self {
//             id: key.id,
//             user_id: String::new(), // This will be set when saving
//             private_key: key.private_key,
//             token: key.token,
//             signature: key.signature,
//             primary: key.primary == 1,
//             active: key.active == 1,
//         }
//     }
// }

impl UserKeyEntity {
    pub fn from_key_with_user_id(key: ProtonUserKey, user_id: &str) -> Self {
        Self {
            id: key.id,
            user_id: user_id.to_string(),
            private_key: key.private_key,
            token: key.token,
            signature: key.signature,
            primary: key.primary == 1,
            active: key.active == 1,
        }
    }
}
