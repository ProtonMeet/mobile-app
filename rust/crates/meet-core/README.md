# Meet Core

Core functionality for the Proton Meet application that supports both native and WebAssembly (WASM) platforms.

## Running Tests

This crate contains tests for both native and WASM platforms. Follow the instructions below to run tests on your platform of choice.

### Native Platform Tests

To run tests on the native platform:

```bash
# Navigate to the meet-core directory
cd rust/crates/meet-core

# Run all tests
cargo test

# Run tests with output
cargo test -- --nocapture

# Run a specific test
cargo test test_persister
```

### WASM Platform Tests

To run tests on the WASM platform, you'll need to install the following prerequisites:

1. wasm-pack: `cargo install wasm-pack`
2. A browser runtime (Chrome/Firefox)

Then run the WASM tests with:

```bash
# Navigate to the meet-core directory
cd rust/crates/meet-core

# Run WASM tests in Chrome
wasm-pack test --chrome

# Run WASM tests in Firefox
wasm-pack test --firefox

# Run WASM tests in headless Chrome
wasm-pack test --headless --chrome

# Run a specific test
wasm-pack test --chrome -- test_persister_wasm
```

## Test Organization

Tests are organized by platform:
- Native tests use Rust's standard `#[test]` attribute
- WASM tests use `#[wasm_bindgen_test]` from the wasm-bindgen-test crate

## Conditional Compilation

The crate uses conditional compilation to target different platforms:
- `#[cfg(not(target_family = "wasm"))]` for native code
- `#[cfg(target_family = "wasm")]` for WASM code 