/*
   Module `ports` specifies infrastructure-level interfaces (ports).

   These are infrastructure-internal traits that are NOT domain requirements.
   They define how infrastructure components interact with each other.

   For domain requirements, see `domain/{subdomain}/ports/`.

   All traits are bounded by `Send + Sync + 'static` for thread safety.
*/

mod db_client;
pub mod secure_store;
pub mod user_key_provider;

// Re-export all traits for convenient access
pub use db_client::*;
pub use secure_store::{SecureStore, SecureStoreResult};
pub use user_key_provider::{UserKeyProvider, UserKeyProviderResult};
