/*
   Module `ports` specifies the API by which external modules interact with the MLS domain.

   All traits are bounded by `Send + Sync`, since their implementations must be shareable
   between request-handling threads.

   Trait methods are explicitly asynchronous, including `?Send` bounds on WASM targets,
   since the application needs to work in both native and WebAssembly environments.
*/

mod key_package_port;
mod message_cache_port;

// Re-export all traits for convenient access
pub use key_package_port::*;
pub use message_cache_port::*;
