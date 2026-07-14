/*
 * getauxval override for Android.
 *
 * Why this exists:
 *   libproton_meet_frb.so is loaded on the mobile app via Dart FFI `dlopen()`.
 *   Its load-time constructors (compiler-rt's `init_have_lse_atomics` /
 *   `__init_cpu_features` for aarch64 LSE/outline-atomics, and vendored
 *   OpenSSL's `OPENSSL_cpuid_setup`) all call `getauxval()` during `.init_array`
 *   execution. On Android 7/8 (API 24-27) the CRT/compiler-rt static `getauxval`
 *   stub reads the process auxv (`__libc_auxv`) which is not reliably initialised
 *   for a library loaded via `dlopen`, so those constructors crash with SIGSEGV
 *   inside `soinfo::call_constructors` -> `call_array` before any Rust code runs.
 *
 * Fix:
 *   Provide a strong `getauxval` definition that forwards to the real bionic
 *   implementation resolved at runtime via `dlsym(RTLD_NEXT, ...)`. If it cannot
 *   be resolved, return 0 (i.e. "no CPU feature detected"), which every caller
 *   handles gracefully. RTLD_NEXT (not RTLD_DEFAULT) is used so we resolve the
 *   next definition in load order (libc's) instead of recursing into ourselves.
 */

#ifdef __ANDROID__

#include <dlfcn.h>

typedef unsigned long (*getauxval_fn)(unsigned long);

unsigned long getauxval(unsigned long type) {
    static getauxval_fn real_getauxval = 0;
    if (!real_getauxval) {
        real_getauxval = (getauxval_fn)dlsym(RTLD_NEXT, "getauxval");
    }
    if (!real_getauxval) {
        return 0;
    }
    return real_getauxval(type);
}

#endif /* __ANDROID__ */
