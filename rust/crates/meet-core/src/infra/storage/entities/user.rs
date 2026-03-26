#[cfg(not(target_family = "wasm"))]
use crate::infra::storage::error::StorageError;
#[cfg(not(target_family = "wasm"))]
use {crate::infra::storage::persister::Db, rusqlite::Transaction};

use proton_meet_common::models::ProtonUser;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UserEntity {
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) email: String,
    pub(crate) used_space: Option<u64>,
    pub(crate) currency: Option<String>,
    pub(crate) credit: Option<u32>,
    pub(crate) create_time: Option<u64>,
    pub(crate) max_space: Option<u64>,
    pub(crate) max_upload: Option<u64>,
    pub(crate) role: Option<u32>,
    pub(crate) private: Option<u32>,
    pub(crate) subscribed: Option<u32>,
    pub(crate) services: Option<u32>,
    pub(crate) delinquent: Option<u32>,
    pub(crate) organization_private_key: Option<String>,
    pub(crate) display_name: Option<String>,
    pub(crate) mnemonic_status: Option<u32>,
}

impl UserEntity {
    pub const SCHEME_NAME: &str = "User";
    pub const TABLE_NAME: &str = "users";

    pub fn new(id: String, name: String, email: String) -> Self {
        Self {
            id,
            name,
            email,
            used_space: None,
            currency: None,
            credit: None,
            create_time: None,
            max_space: None,
            max_upload: None,
            role: None,
            private: None,
            subscribed: None,
            services: None,
            delinquent: None,
            organization_private_key: None,
            display_name: None,
            mnemonic_status: None,
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn with_proton_user_fields(
        id: String,
        name: String,
        email: String,
        used_space: Option<u64>,
        currency: Option<String>,
        credit: Option<u32>,
        create_time: Option<u64>,
        max_space: Option<u64>,
        max_upload: Option<u64>,
        role: Option<u32>,
        private: Option<u32>,
        subscribed: Option<u32>,
        services: Option<u32>,
        delinquent: Option<u32>,
        organization_private_key: Option<String>,
        display_name: Option<String>,
        mnemonic_status: Option<u32>,
    ) -> Self {
        Self {
            id,
            name,
            email,
            used_space,
            currency,
            credit,
            create_time,
            max_space,
            max_upload,
            role,
            private,
            subscribed,
            services,
            delinquent,
            organization_private_key,
            display_name,
            mnemonic_status,
        }
    }

    #[cfg(not(target_family = "wasm"))]
    pub(crate) fn schema_v1() -> String {
        r#"
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            email TEXT NOT NULL
        )
    "#
        .to_owned()
    }

    #[cfg(not(target_family = "wasm"))]
    pub(crate) fn schema_v2() -> String {
        r#"
        ALTER TABLE users ADD COLUMN used_space INTEGER;
        ALTER TABLE users ADD COLUMN currency TEXT;
        ALTER TABLE users ADD COLUMN credit INTEGER;
        ALTER TABLE users ADD COLUMN create_time INTEGER;
        ALTER TABLE users ADD COLUMN max_space INTEGER;
        ALTER TABLE users ADD COLUMN max_upload INTEGER;
        ALTER TABLE users ADD COLUMN role INTEGER;
        ALTER TABLE users ADD COLUMN private INTEGER;
        ALTER TABLE users ADD COLUMN subscribed INTEGER;
        ALTER TABLE users ADD COLUMN services INTEGER;
        ALTER TABLE users ADD COLUMN delinquent INTEGER;
        ALTER TABLE users ADD COLUMN organization_private_key TEXT;
        ALTER TABLE users ADD COLUMN display_name TEXT;
        ALTER TABLE users ADD COLUMN mnemonic_status INTEGER;
    "#
        .to_owned()
    }

    #[cfg(not(target_family = "wasm"))]
    pub fn init_sqlite_tables(db_tx: &Transaction) -> Result<(), StorageError> {
        Db::migrate_schema(
            db_tx,
            Self::SCHEME_NAME,
            &[&Self::schema_v1(), &Self::schema_v2()],
        )?;
        Ok(())
    }
}

impl From<ProtonUser> for UserEntity {
    fn from(proton_user: ProtonUser) -> Self {
        UserEntity {
            id: proton_user.id,
            name: proton_user.name,
            email: proton_user.email,
            used_space: Some(proton_user.used_space),
            currency: Some(proton_user.currency),
            credit: Some(proton_user.credit),
            create_time: Some(proton_user.create_time),
            max_space: Some(proton_user.max_space),
            max_upload: Some(proton_user.max_upload),
            role: Some(proton_user.role),
            private: Some(proton_user.private),
            subscribed: Some(proton_user.subscribed),
            services: Some(proton_user.services),
            delinquent: Some(proton_user.delinquent),
            organization_private_key: proton_user.organization_private_key,
            display_name: proton_user.display_name,
            mnemonic_status: Some(proton_user.mnemonic_status),
        }
    }
}

impl From<UserEntity> for ProtonUser {
    fn from(entity: UserEntity) -> Self {
        ProtonUser {
            id: entity.id,
            name: entity.name,
            email: entity.email,
            used_space: entity.used_space.unwrap_or(0),
            currency: entity.currency.unwrap_or_default(),
            credit: entity.credit.unwrap_or(0),
            create_time: entity.create_time.unwrap_or(0),
            max_space: entity.max_space.unwrap_or(0),
            max_upload: entity.max_upload.unwrap_or(0),
            role: entity.role.unwrap_or(0),
            private: entity.private.unwrap_or(0),
            subscribed: entity.subscribed.unwrap_or(0),
            services: entity.services.unwrap_or(0),
            delinquent: entity.delinquent.unwrap_or(0),
            organization_private_key: entity.organization_private_key,
            display_name: entity.display_name,
            keys: None,
            mnemonic_status: entity.mnemonic_status.unwrap_or(0),
            flags: None,
        }
    }
}
