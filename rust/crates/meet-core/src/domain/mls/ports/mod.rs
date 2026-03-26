/*
   Module `ports` specifies the API by which external modules interact with the MLS domain.

   All traits are bounded by `Send + Sync`, since their implementations must be shareable
   between request-handling threads.

   Trait methods are explicitly asynchronous, including `?Send` bounds on WASM targets,
   since the application needs to work in both native and WebAssembly environments.
*/

mod message_cache_port;
mod mls_store_port;
mod state_repository_port;

// Re-export all traits for convenient access
pub use message_cache_port::*;
pub use mls_store_port::*;
pub use state_repository_port::*;
