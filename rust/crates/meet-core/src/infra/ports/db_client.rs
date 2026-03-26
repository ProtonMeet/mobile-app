use proton_meet_macro::async_trait_with_mock;

use crate::infra::storage::error::StorageError;

/// Port for database client operations
///
/// This is an infrastructure port (not a domain requirement).
/// It defines how infrastructure components interact with the database,
/// allowing different storage implementations (SQLite, IndexedDB, etc.)
/// to be used interchangeably.
///
/// # Examples
///
/// '''rust,no_run
/// use crate::infra::ports::DbClient;
///
/// async fn example(client: &dyn DbClient) {
///     client.init_tables("my_database").await?;
/// }
/// '''
#[async_trait_with_mock]
pub trait DbClient {
    /// Initialize database tables for the given database name.
    ///
    /// This method should create all necessary tables and run migrations
    /// for the specified database.
    async fn init_db_tables(&self, name: &str) -> Result<(), StorageError>;
}
