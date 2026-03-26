/// Version information for the `proton-meet-core` crate.
///
/// This module provides compile-time access to the crate version from `Cargo.toml`.
///
/// # Examples
///
/// '''rust
/// use proton_meet_core::version::{VERSION, CRATE_NAME, full_version_string, base_version, build_number};
///
/// // Get version string
/// println!("Version: {}", VERSION); // "0.5.1+build.2"
///
/// // Get crate name
/// println!("Crate: {}", CRATE_NAME); // "proton-meet-core"
///
/// // Get formatted version string
/// println!("{}", full_version_string()); // "proton-meet-core v0.5.1+build.2"
///
/// // Get version without build metadata
/// println!("Base version: {}", base_version()); // "0.5.1"
///
/// // Get build number
/// println!("Build: {}", build_number()); // Some("2")
/// '''
/// The version of the `proton-meet-core` crate.
///
/// This is automatically set from `Cargo.toml` at compile time using `env!("CARGO_PKG_VERSION")`.
/// Example: `"0.5.1+build.2"` (SemVer format with build metadata)
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// The name of the crate.
///
/// This is automatically set from `Cargo.toml` at compile time using `env!("CARGO_PKG_NAME")`.
/// Example: `"proton-meet-core"`
pub const CRATE_NAME: &str = env!("CARGO_PKG_NAME");

/// Returns the full version string in the format `"crate-name/version"`.
///
/// Example: `"proton-meet-core/0.5.1.2"`
pub const fn version_string() -> &'static str {
    // Note: We can't concatenate at compile time easily, so we'll provide a function
    // that returns the version. For full string, use format!() at runtime.
    VERSION
}

/// Returns the full version info as a formatted string.
///
/// Example: `"proton-meet-core v0.5.1+build.2"`
pub fn full_version_string() -> String {
    format!("{CRATE_NAME} v{VERSION}")
}

/// Returns the base version without build metadata.
///
/// Example: `"0.5.1+build.2"` → `"0.5.1"`
pub fn base_version() -> String {
    VERSION.split('+').next().unwrap_or(VERSION).to_string()
}

/// Returns the build number if present in the version string.
///
/// Parses build metadata like `+build.2` or `+2` and returns the number.
/// Example: `"0.5.1+build.2"` → `Some("2")`
///          `"0.5.1"` → `None`
pub fn build_number() -> Option<String> {
    VERSION.split('+').nth(1).map(|build| {
        // Try to extract number from formats like "build.2" or just "2"
        if let Some(num) = build.strip_prefix("build.") {
            num.to_string()
        } else {
            build.to_string()
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    #[allow(clippy::const_is_empty)]
    fn test_version_is_not_empty() {
        assert!(!VERSION.is_empty());
        assert!(!CRATE_NAME.is_empty());
    }

    #[test]
    fn test_version_format() {
        // Version should be in SemVer format (e.g., "0.5.1" or "0.5.1-2")
        // Split by - to get base version (before pre-release identifier)
        let base_version = VERSION.split('-').next().unwrap_or(VERSION);
        // Check if base version contains at least one dot
        assert!(
            base_version.contains('.'),
            "Base version should contain at least one dot"
        );
        // Split by dots and verify we have at least major.minor
        let parts: Vec<&str> = base_version.split('.').collect();
        assert!(
            parts.len() >= 2,
            "Version should have at least major.minor format"
        );
        // Verify base version parts (major, minor, patch) are numeric
        for part in &parts {
            assert!(
                part.chars().all(|c| c.is_ascii_digit()),
                "Base version parts (major.minor.patch) should be numeric, got: {part}",
            );
        }
    }

    #[test]
    fn test_full_version_string() {
        let full = full_version_string();
        println!("Full version string: {full}");
        assert!(full.contains(CRATE_NAME));
        assert!(full.contains(VERSION));
    }
}
