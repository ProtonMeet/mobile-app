//! Shared harness code for the stateful MLS fuzz targets.
//!
//! `env` builds real, initialized MLS clients (via the light vendored crates —
//! no `meet-core`, no network/openssl), drives create/join/add/update/remove/
//! encrypt/deliver operations against them, and hosts the oracles
//! (`assert_all_converged` for totally-ordered agreement, `check_sender_integrity`
//! for leaf-reuse aliasing, and the per-member reload invariant). `ops` is the
//! `arbitrary`-derived operation model libFuzzer mutates.
pub mod env;
pub mod ops;
