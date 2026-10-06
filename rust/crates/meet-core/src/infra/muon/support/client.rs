//! Muon client construction and SDK header helpers.

use muon::app::SemVer;
use muon::common::sdk::Sdk;
use muon::{App, Client, Environment};

use super::MeetClient;
use crate::infra::http_client::ProxyConfig;

#[cfg(target_arch = "wasm32")]
use super::WasmSleeper;
#[cfg(not(target_arch = "wasm32"))]
use super::{MeetOs, TokioExecutor};

// Workspace pins `rand` 0.8 (WASM); muon 4.x's client builder takes `rand` 0.10 RNGs.
// `rand_v10` is a Cargo alias so both versions can coexist in meet-core.
fn meet_prng() -> rand_v10::rngs::ThreadRng {
    rand_v10::rng()
}

/// Strip pre-release/build metadata from a muon [`SemVer`] so it satisfies
/// [`Sdk`] version rules (numeric MAJOR.MINOR.PATCH[.BUILD] only).
fn sdk_version_from_semver(version: &SemVer) -> Option<String> {
    let rendered = version.to_string();
    let without_build_meta = rendered.split('+').next()?;
    let numeric_core = without_build_meta.split('-').next()?;
    // Validate against muon's SDK version parser before returning.
    Sdk::new("meet", numeric_core).ok()?;
    Some(numeric_core.to_string())
}

/// SDK identity for `x-pm-sdk-versions` / `x-pm-origin-sdk` (muon 4.x).
pub fn meet_sdk_from_app(app: &App) -> Option<Sdk> {
    let app_version = app.app_version();
    let name = app_version.name()?;
    let version = app_version.version()?;
    let sdk_version = sdk_version_from_semver(version)?;
    Sdk::new(&name.to_string(), &sdk_version).ok()
}

/// Build a muon client with [`MeetPersistence`][super::MeetPersistence] = [`AuthStore`][super::AuthStore] (native only).
#[cfg(not(target_arch = "wasm32"))]
pub fn build_meet_client(
    app: App,
    environment: Environment,
    persistence: super::MeetPersistence,
    proxy: Option<&ProxyConfig>,
) -> muon::Result<MeetClient> {
    use muon::common::{OwnedProxy, Proxy};

    let mut prng = meet_prng();
    let meet_sdk = meet_sdk_from_app(&app);
    let mut builder = Client::builder(app, environment)
        .with_operating_system(MeetOs::default(), &mut prng)
        .with_multi_thread_executor(TokioExecutor);

    #[cfg(feature = "allow-dangerous-env")]
    if let Some(proxy_config) = proxy {
        builder = builder.proxy(Proxy::from(
            OwnedProxy::all(format!(
                "http://{}:{}",
                proxy_config.host, proxy_config.port
            ))
            .map_err(muon::Error::other)?,
        ));
    }

    let mut builder = builder.with_persistence(persistence).without_cookie_store();
    if let Some(sdk) = meet_sdk {
        builder = builder.register_sdk(sdk);
    }

    builder.build()
}

/// Build a muon client without persistence (WASM).
#[cfg(target_arch = "wasm32")]
pub fn build_meet_client(
    app: App,
    environment: Environment,
    proxy: Option<&ProxyConfig>,
) -> muon::Result<MeetClient> {
    let _ = proxy;
    let mut prng = meet_prng();
    let meet_sdk = meet_sdk_from_app(&app);
    let mut builder = Client::builder(app, environment)
        .with_operating_system(WasmSleeper::default(), &mut prng)
        .without_persistence::<()>()
        .without_cookie_store();
    if let Some(sdk) = meet_sdk {
        builder = builder.register_sdk(sdk);
    }
    builder.build()
}
