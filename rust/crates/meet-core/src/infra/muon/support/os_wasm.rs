//! Browser-friendly sleep/time for muon's WASM reqwest connector.

use std::pin::Pin;

use futures::Future;
use js_sys;
use muon::rt::{InstantFactory, Monotonic, MuonInstant, Sleep};

#[derive(Debug, Clone, Default)]
pub struct WasmSleeper;

impl Sleep for WasmSleeper {
    type Sleep<'a>
        = Pin<Box<dyn Future<Output = ()> + 'a>>
    where
        Self: 'a;

    fn sleep(&self, duration: std::time::Duration) -> Self::Sleep<'static> {
        Box::pin(gloo_timers::future::sleep(duration))
    }
}

unsafe impl Monotonic for WasmSleeper {}

impl InstantFactory for WasmSleeper {
    type Instant = MuonInstant;

    fn now(&self) -> Self::Instant {
        MuonInstant::from_duration(std::time::Duration::from_millis(js_sys::Date::now() as u64))
    }
}
