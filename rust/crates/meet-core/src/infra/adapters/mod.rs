/*
   Module `adapters` contains implementations of infrastructure ports.
   
   Adapters implement ports defined in `infra/ports/` and adapt
   them to concrete infrastructure implementations (e.g., Dart callbacks,
   flutter_secure_storage, etc.).
   
   Adapters are thin wrappers that bridge infrastructure ports to
   concrete implementations.
*/

pub mod mls;
pub mod storage;
