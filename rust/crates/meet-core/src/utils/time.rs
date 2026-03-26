/// Platform-agnostic Instant type
#[cfg(not(target_family = "wasm"))]
pub type PlatformInstant = std::time::Instant;

#[cfg(target_family = "wasm")]
pub type PlatformInstant = wasmtimer::std::Instant;

/// Get the current time as a platform-agnostic Instant
///
/// This function abstracts away the platform differences between
/// native (std::time::Instant) and WASM (wasmtimer::std::Instant).
pub mod instant {
    use crate::utils::PlatformInstant;

    #[cfg(not(target_family = "wasm"))]
    pub fn now() -> PlatformInstant {
        std::time::Instant::now()
    }

    #[cfg(target_family = "wasm")]
    pub fn now() -> PlatformInstant {
        wasmtimer::std::Instant::now()
    }
}

pub fn unix_timestamp_ms() -> u64 {
    #[cfg(not(target_family = "wasm"))]
    {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64
    }

    #[cfg(target_family = "wasm")]
    {
        wasmtimer::std::SystemTime::now()
            .duration_since(wasmtimer::std::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64
    }
}
