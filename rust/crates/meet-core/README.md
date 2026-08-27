# Meet Core

Core functionality for the Proton Meet application that supports both native and WebAssembly (WASM) platforms.

## Running Tests

This crate contains tests for both native and WASM platforms. Follow the instructions below to run tests on your platform of choice. The following cargo features can be used:

- `test-load` enables load testing tests (e.g. connecting 500 participants to a meeting)
- `test-prod` switches the tests to run on production environment (WIP)
- `test-logging` enables tracing in the tests for more verbose outputs
- `test-e2e` enables end to end tests

### Native Platform Tests

To run tests on the native platform:

```bash
# Navigate to the meet-core directory
cd rust/crates/meet-core

# Run all unit tests
cargo test

# Run all unit and end-to-end tests
cargo test --features test-e2e

# Run tests with output
cargo test -- --nocapture

# Run a specific test
cargo test test_persister

# Run a specific test with logging enabled
cargo test --features test-logging test_persister
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
