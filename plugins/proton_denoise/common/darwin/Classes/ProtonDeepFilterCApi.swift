#if PROTON_DENOISE_DEEPFILTER
// DeepFilter C API (common/cpp) — statically linked on Apple when PROTON_DENOISE_DEEPFILTER is set.

@_silgen_name("proton_deepfilter_ensure_loaded")
func proton_deepfilter_ensure_loaded() -> Int32

@_silgen_name("proton_deepfilter_create")
func proton_deepfilter_create(_ modelPath: UnsafePointer<CChar>?) -> OpaquePointer?

@_silgen_name("proton_deepfilter_destroy")
func proton_deepfilter_destroy(_ handle: OpaquePointer?)

@_silgen_name("proton_deepfilter_get_frame_size")
func proton_deepfilter_get_frame_size(_ handle: OpaquePointer?) -> Int32

@_silgen_name("proton_deepfilter_set_enabled")
func proton_deepfilter_set_enabled(_ handle: OpaquePointer?, _ enabled: Int32)

@_silgen_name("proton_deepfilter_is_enabled")
func proton_deepfilter_is_enabled(_ handle: OpaquePointer?) -> Int32

@_silgen_name("proton_deepfilter_set_atten_lim")
func proton_deepfilter_set_atten_lim(_ handle: OpaquePointer?, _ limDb: Float)

@_silgen_name("proton_deepfilter_process_interleaved")
func proton_deepfilter_process_interleaved(
  _ handle: OpaquePointer?,
  _ samples: UnsafeMutablePointer<Float>?,
  _ sampleCount: Int,
  _ numChannels: Int32
) -> Float
#endif
