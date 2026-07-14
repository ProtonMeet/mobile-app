use std::env;

fn main() {
    // On Android, compile a `getauxval` shim into the cdylib so that the
    // load-time CPU-feature-detection constructors (compiler-rt LSE /
    // outline-atomics and vendored OpenSSL `OPENSSL_cpuid_setup`) do not crash
    // when this library is loaded via `dlopen` on Android 7/8 (API 24-27).
    // See getauxval_fix.c for the full explanation.
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os == "android" {
        println!("cargo:rerun-if-changed=getauxval_fix.c");
        cc::Build::new()
            .file("getauxval_fix.c")
            .compile("getauxval_fix");
    }
}
