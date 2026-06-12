// DTLN (dtln-rs) C API (common/cpp).

@_silgen_name("proton_dtln_create")
func proton_dtln_create() -> OpaquePointer?

@_silgen_name("proton_dtln_destroy")
func proton_dtln_destroy(_ handle: OpaquePointer?)

@_silgen_name("proton_dtln_get_sample_rate")
func proton_dtln_get_sample_rate() -> Int32

@_silgen_name("proton_dtln_get_block_shift")
func proton_dtln_get_block_shift() -> Int32

@_silgen_name("proton_dtln_denoise_interleaved")
func proton_dtln_denoise_interleaved(
  _ handle: OpaquePointer?,
  _ samples: UnsafeMutablePointer<Float>?,
  _ sample_count: Int
) -> Int32
