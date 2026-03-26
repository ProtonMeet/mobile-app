//! # Unified Attribute Macros for Cross-Platform Rust Development
//!
//! This crate provides procedural macros to simplify conditional compilation and
//! reduce repetitive boilerplate when working with:
//!
//! - `tokio::test` vs `wasm_bindgen_test`
//! - `async_trait` usage with `?Send` on `wasm`
//! - `mockall::automock` for trait mocking in tests
//!
//! ## Macros Provided
//!
//! - `#[unified_test]`: Platform-aware test macro
//! - `#[async_trait]`: Platform-aware async trait implementation
//! - `#[async_trait_with_mock]`: Async trait + mocking for unit tests
//!
//! These macros are designed to work across both native and WebAssembly targets seamlessly.
use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, ItemFn, ItemImpl, ItemTrait};

/// Platform-unified test macro for async tests.
///
/// Applies `#[tokio::test]` on native targets and `#[wasm_bindgen_test]` on WebAssembly.
///
/// This reduces the need for conditional compilation blocks like:
/// '''rust
/// #[cfg_attr(not(target_family = "wasm"), tokio::test)]
/// #[cfg_attr(target_family = "wasm", wasm_bindgen_test)]
/// ''' no_run
///
/// ### Example
/// '''rust
/// #[unified_test]
/// async fn test_something() {
///     assert_eq!(2 + 2, 4);
/// }
/// ''' no_run
#[proc_macro_attribute]
pub fn unified_test(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let input = parse_macro_input!(item as ItemFn);

    let fn_attrs = &input.attrs;
    let fn_sig = &input.sig;
    let fn_body = &input.block;

    let result = quote! {
        #[cfg_attr(not(target_family = "wasm"), tokio::test)]
        #[cfg_attr(target_family = "wasm", wasm_bindgen_test::wasm_bindgen_test)]
        #(#fn_attrs)*
        #fn_sig #fn_body
    };

    result.into()
}

/// Platform-unified async trait implementation macro.
///
/// Applies `#[async_trait::async_trait(?Send)]` on `wasm` targets and
/// `#[async_trait::async_trait]` on native targets.
///
/// This allows you to write:
/// '''rust
/// #[async_trait]
/// impl MyTrait for MyType {
///     async fn do_work(&self) { /* ... */ }
/// }
/// ''' no_run
/// Instead of adding target-specific conditionals manually.
#[proc_macro_attribute]
pub fn async_trait(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let input = parse_macro_input!(item as ItemImpl);

    let result = quote! {
        #[cfg_attr(target_family = "wasm", async_trait::async_trait(?Send))]
        #[cfg_attr(not(target_family = "wasm"), async_trait::async_trait)]
        #input
    };

    result.into()
}

/// Platform-unified async trait definition with optional mocking.
///
/// This macro is designed for trait definitions. It:
/// - Applies `#[async_trait::async_trait(?Send)]` on `wasm`
/// - Applies `#[async_trait::async_trait]` on native
/// - Applies `#[mockall::automock]` when `#[cfg(test)]` is active
///
/// This is ideal for domain-level interfaces that require mocking in unit tests.
///
/// ### Example
/// '''rust
/// #[async_trait_with_mock]
/// pub trait MyService {
///     async fn perform(&self) -> Result<(), MyError>;
/// }
/// ''' no_run
#[proc_macro_attribute]
pub fn async_trait_with_mock(_attr: TokenStream, item: TokenStream) -> TokenStream {
    let input = parse_macro_input!(item as ItemTrait);

    let result = quote! {
        #[cfg_attr(target_family = "wasm", async_trait::async_trait(?Send))]
        #[cfg_attr(not(target_family = "wasm"), async_trait::async_trait)]
        #[cfg_attr(test, mockall::automock)]
        #input
    };

    result.into()
}
