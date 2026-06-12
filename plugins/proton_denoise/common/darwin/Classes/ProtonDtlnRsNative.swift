/// Swift bridge to dtln-rs via [proton_dtln_api.h].
enum ProtonDtlnRsNative {
#if PROTON_DENOISE_DTLN_IOS
  private static let availability: Bool = {
    guard let probe = proton_dtln_create() else {
      return false
    }
    proton_dtln_destroy(probe)
    return true
  }()

  static var isAvailable: Bool { availability }

  static func create() -> OpaquePointer? {
    guard isAvailable else {
      return nil
    }
    return proton_dtln_create()
  }

  static func destroy(_ handle: OpaquePointer?) {
    proton_dtln_destroy(handle)
  }

  static func getSampleRate() -> Int {
    guard isAvailable else {
      return 0
    }
    return Int(proton_dtln_get_sample_rate())
  }

  static func getBlockShift() -> Int {
    guard isAvailable else {
      return 0
    }
    return Int(proton_dtln_get_block_shift())
  }

  static func denoiseInterleaved(
    _ handle: OpaquePointer?,
    _ samples: inout [Float]
  ) -> Bool {
    guard let handle, !samples.isEmpty else {
      return false
    }
    return samples.withUnsafeMutableBufferPointer { buffer in
      guard let base = buffer.baseAddress else {
        return false
      }
      return proton_dtln_denoise_interleaved(handle, base, buffer.count) == 0
    }
  }
#else
  static var isAvailable: Bool { false }

  static func create() -> OpaquePointer? { nil }

  static func destroy(_ handle: OpaquePointer?) {
    _ = handle
  }

  static func getSampleRate() -> Int { 0 }

  static func getBlockShift() -> Int { 0 }

  static func denoiseInterleaved(
    _ handle: OpaquePointer?,
    _ samples: inout [Float]
  ) -> Bool {
    _ = handle
    _ = samples
    return false
  }
#endif
}
