//! Muon 4.x glue for Meet: types, environment parsing, platform transport, client builder.
//!
//! ```text
//! types (MeetClient, MeetPersistence, …)
//!   └── env      — prod / atlas / scientist / custom URL parsing
//!   └── os_native — hyper + tokio (native)
//!   └── os_wasm   — reqwest + gloo timers (WASM)
//!   └── client     — build_meet_client, SDK header helpers
//!   └── client_ext — MeetClientExt (default session)
//!   └── tests     — unified native + WASM tests (see `test_support`)
//! ```

mod client;
mod client_ext;
mod env;

#[cfg(not(target_arch = "wasm32"))]
mod os_native;
#[cfg(target_arch = "wasm32")]
mod os_wasm;

#[cfg(test)]
pub(crate) mod test_support;
#[cfg(test)]
mod tests;

pub use client::{build_meet_client, meet_sdk_from_app};
pub use client_ext::MeetClientExt;
#[cfg(all(feature = "allow-dangerous-env", not(target_arch = "wasm32")))]
pub(crate) use env::MeetCustomEnv;
pub use env::{environment_from_str, is_prod_environment, parse_environment};

#[cfg(not(target_arch = "wasm32"))]
pub use os_native::{MeetOs, TokioExecutor};

#[cfg(target_arch = "wasm32")]
pub use os_wasm::WasmSleeper;

use muon::cookie_store::NoOpCookieStore;
use muon::{Client, NoInfo, Session, common::GenericContext};

#[cfg(not(target_arch = "wasm32"))]
use super::auth_store::AuthStore;

/// Session key used for the primary Meet muon session.
pub const MUON_DEFAULT_SESSION_KEY: () = ();

// ---------------------------------------------------------------------------
// Client type aliases (persistence + transport differ by target)
// ---------------------------------------------------------------------------

/// Native: [`AuthStore`] (`Store`); WASM: [`muon::store::WithoutPersistence`].
#[cfg(not(target_arch = "wasm32"))]
pub type MeetPersistence = AuthStore;
#[cfg(target_arch = "wasm32")]
pub type MeetPersistence = muon::store::WithoutPersistence<()>;

/// Hyper + tokio executor on native; reqwest on WASM.
#[cfg(not(target_arch = "wasm32"))]
pub type MeetTransportConnector = muon::transport::http::hyper::connector::HyperConnector<
    MeetOs,
    muon::rt::SendExecutor<TokioExecutor>,
>;
#[cfg(target_arch = "wasm32")]
pub type MeetTransportConnector = muon::transport::http::reqwest::ReqwestConnector<WasmSleeper>;

pub type MeetContext =
    GenericContext<MeetTransportConnector, MeetPersistence, NoInfo, NoOpCookieStore>;
pub type MeetClient = Client<MeetContext>;
pub type MeetSession = Session<MeetContext>;
