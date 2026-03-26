use std::str::FromStr;
use std::sync::{Arc, Mutex};

use flutter_rust_bridge::DartFnFuture;
use lazy_static::lazy_static;
use tracing::{Event, Level, Subscriber};
use tracing_subscriber::layer::Context;
use tracing_subscriber::Layer;

pub enum RustLevel {
    Trace = 0,
    Debug = 1,
    Info = 2,
    Warn = 3,
    Error = 4,
    Unknown = 99,
}

impl RustLevel {
    pub fn from_string_ref(level: &str) -> Self {
        Level::from_str(level)
            .map(|level| level.into())
            .unwrap_or(RustLevel::Unknown)
    }

    pub fn to_str(&self) -> String {
        match self {
            RustLevel::Trace => "TRACE".to_string(),
            RustLevel::Debug => "DEBUG".to_string(),
            RustLevel::Info => "INFO".to_string(),
            RustLevel::Warn => "WARN".to_string(),
            RustLevel::Error => "ERROR".to_string(),
            RustLevel::Unknown => "UNKNOWN".to_string(),
        }
    }
}

impl From<Level> for RustLevel {
    fn from(level: Level) -> Self {
        match level {
            Level::TRACE => RustLevel::Trace,
            Level::DEBUG => RustLevel::Debug,
            Level::INFO => RustLevel::Info,
            Level::WARN => RustLevel::Warn,
            Level::ERROR => RustLevel::Error,
        }
    }
}

// Use async callback type (DartFnFuture) so flutter_rust_bridge can generate bindings
// Even though logging happens synchronously, the callback registration can be async
pub type LoggerCallback = dyn Fn(RustLevel, String) -> DartFnFuture<()> + Send + Sync + 'static;

// Use std::sync::Mutex for synchronous access from on_event
// We'll handle async spawning separately
lazy_static! {
    static ref MEET_DART_LOGGER_CALLBACK: Arc<Mutex<Option<Arc<LoggerCallback>>>> =
        Arc::new(Mutex::new(None));
}

// Make this async to match the callback signature
// flutter_rust_bridge cannot generate bindings for impl Trait parameters
pub async fn set_flutter_log_callback(
    callback: impl Fn(RustLevel, String) -> DartFnFuture<()> + Send + Sync + 'static,
) {
    // Use blocking lock since this is called from async context
    let mut guard = MEET_DART_LOGGER_CALLBACK.lock().unwrap();
    *guard = Some(Arc::new(callback));
}

pub struct FlutterLogLayer {}
impl FlutterLogLayer {
    pub(crate) fn new() -> Self {
        Self {}
    }
}

impl Default for FlutterLogLayer {
    fn default() -> Self {
        Self::new()
    }
}

impl<S> Layer<S> for FlutterLogLayer
where
    S: Subscriber,
{
    fn on_event(&self, event: &Event, _ctx: Context<S>) {
        // Filter out TRACE level logs - they're too verbose and cause performance issues
        // Also filter out verbose libraries that spam logs
        let metadata = event.metadata();
        let level = *metadata.level();

        // Skip TRACE level logs entirely
        if level == Level::TRACE {
            return;
        }

        // Filter out verbose library logs at DEBUG and TRACE levels
        // These logs are too verbose and don't provide useful information for debugging
        let target = metadata.target();
        if level == Level::DEBUG || level == Level::TRACE {
            // Skip verbose internal library logs that spam the console
            // Connection pool logs are normal but too verbose for production
            if target.starts_with("hyper")
                || target.starts_with("hyper_util")
                || target.starts_with("muon::store")
                || target.starts_with("tower")
                || target.starts_with("h2")
                || target.starts_with("rustls")
                || target.starts_with("want")
            {
                return;
            }
        }

        // Get callback synchronously (on_event is called synchronously)
        let callback_opt = {
            match MEET_DART_LOGGER_CALLBACK.lock() {
                Ok(guard) => guard.as_ref().cloned(),
                Err(_) => None, // lock poisoned → ignore
            }
        };

        // temp solution. we will need to use channel sync the logs for mobile debugging
        if let Some(callback) = callback_opt {
            let level: RustLevel = level.into();
            // Format the event message properly
            let mut msg = String::new();
            use std::fmt::Write;
            let _ = write!(&mut msg, "{:?}", event);

            // Only spawn if we have a Tokio runtime available
            // flutter_rust_bridge::spawn requires a runtime, so we check first
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                // We're in a Tokio runtime context, spawn safely
                let callback = callback.clone();
                handle.spawn(async move {
                    let _ = callback(level, msg).await; // do not crash app on error
                });
            }
            // If no runtime is available, silently skip the callback
            // Logging failures shouldn't crash the app
        }
    }
}
