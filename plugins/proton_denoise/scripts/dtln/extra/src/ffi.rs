//! C ABI for proton_denoise mobile static linking (copied into dtln-rs by build-dtln-rs-env.sh).
//!
//! Exports `_dtln_*` symbols consumed from Swift/Kotlin/C++ via `proton_dtln_c_api.cc`.
//! TFLite is merged into `libdtln.a` after `cargo` — see `build-dtln-rs-env.sh`.
use std::os::raw::{c_float, c_int};
use std::ptr;

use crate::constants::{DTLN_BLOCK_SHIFT, DTLN_SAMPLE_RATE_HZ};
use crate::dtln_engine::{self, DtlnEngine};

#[repr(C)]
pub struct DtlnHandle {
    engine: DtlnEngine,
}

/// Returns null on engine init failure (model / TFLite not ready).
#[no_mangle]
pub extern "C" fn dtln_create() -> *mut DtlnHandle {
    match dtln_engine::dtln_create() {
        Some(engine) => Box::into_raw(Box::new(DtlnHandle { engine })),
        None => ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn dtln_destroy(handle: *mut DtlnHandle) {
    if !handle.is_null() {
        // nosemgrep
        unsafe {
            drop(Box::from_raw(handle));
        }
    }
}

/// No-op — kept for API parity with upstream Node bindings.
#[no_mangle]
pub extern "C" fn dtln_stop(_handle: *mut DtlnHandle) {}

#[no_mangle]
pub extern "C" fn dtln_get_sample_rate() -> c_int {
    DTLN_SAMPLE_RATE_HZ as c_int
}

#[no_mangle]
pub extern "C" fn dtln_get_block_shift() -> c_int {
    DTLN_BLOCK_SHIFT as c_int
}

/// In-place denoise; returns 0 on success, -1 on bad args or engine error.
#[no_mangle]
pub extern "C" fn dtln_denoise(
    handle: *mut DtlnHandle,
    input: *const c_float,
    output: *mut c_float,
    sample_count: c_int,
) -> c_int {
    if handle.is_null() || input.is_null() || output.is_null() || sample_count <= 0 {
        return -1;
    }
    let count = sample_count as usize;
    let input_slice = unsafe { std::slice::from_raw_parts(input, count) }; // nosemgrep
    let output_slice = unsafe { std::slice::from_raw_parts_mut(output, count) }; // nosemgrep
    let handle = unsafe { &mut *handle }; // nosemgrep
    match dtln_engine::dtln_denoise(&mut handle.engine, input_slice, output_slice) {
        Ok(()) => 0,
        Err(_) => -1,
    }
}
