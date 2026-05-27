// RNNoise C API (common/cpp).

@_silgen_name("proton_rnnoise_create")
func proton_rnnoise_create() -> OpaquePointer?

@_silgen_name("proton_rnnoise_destroy")
func proton_rnnoise_destroy(_ handle: OpaquePointer?)

@_silgen_name("proton_rnnoise_get_frame_size")
func proton_rnnoise_get_frame_size() -> Int32

@_silgen_name("proton_rnnoise_set_enabled")
func proton_rnnoise_set_enabled(_ handle: OpaquePointer?, _ enabled: Int32)

@_silgen_name("proton_rnnoise_is_enabled")
func proton_rnnoise_is_enabled(_ handle: OpaquePointer?) -> Int32

@_silgen_name("proton_rnnoise_process_interleaved")
func proton_rnnoise_process_interleaved(
  _ handle: OpaquePointer?,
  _ samples: UnsafeMutablePointer<Float>?,
  _ sample_count: Int,
  _ num_channels: Int32
) -> Float
