pub mod domain;
pub mod error;
pub mod service;

type Result<T, E = error::ChatError> = std::result::Result<T, E>;
