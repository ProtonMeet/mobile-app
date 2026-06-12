import Foundation

/// Per-backend readiness probes for debug settings UI.
enum DenoiseDiagnostics {
  private static let allTypeIds = ["rnnoise", "deepfilter", "deepfilter2", "dtln-rs"]

  private static var platformName: String {
    #if os(iOS)
      return "ios"
    #elseif os(macOS)
      return "macos"
    #else
      return "darwin"
    #endif
  }

  private static func withPlatform(_ details: [String: Any]) -> [String: Any] {
    var out = details
    out["platform"] = platformName
    return out
  }

  static func warmUpAll() -> [[String: Any]] {
    allTypeIds.map { typeId in
      var entry = warmUp(typeId: typeId)
      entry["id"] = typeId
      return entry
    }
  }

  static func warmUp(typeId: String) -> [String: Any] {
    switch typeId {
    case "rnnoise":
      return warmUpRnnoise()
    case "deepfilter":
      return warmUpDeepFilter(modelResourceName: ProtonDeepFilterNative.ModelResource.net3)
    case "deepfilter2":
      if !ProtonDeepFilterNative.isNet2RuntimeSupported {
        return withPlatform([
          "warmUpOk": false,
          "warmUpMs": 0,
          "error": "libDF runtime does not support DF2 on this build",
        ])
      }
      return warmUpDeepFilter(modelResourceName: ProtonDeepFilterNative.ModelResource.net2)
    case "dtln-rs":
      return warmUpDtln()
    default:
      return withPlatform([
        "warmUpOk": false,
        "warmUpMs": 0,
        "error": "Unknown denoise type: \(typeId)",
      ])
    }
  }

  static func payload() -> [[String: Any]] {
    [
      rnnoiseEntry(),
      deepfilterEntry(
        id: "deepfilter",
        displayName: "DeepFilter 3",
        modelResourceName: ProtonDeepFilterNative.ModelResource.net3,
        isReady: DeepFilterProcessor.isNativeReady(
          modelResourceName: ProtonDeepFilterNative.ModelResource.net3
        ),
      ),
      deepfilterEntry(
        id: "deepfilter2",
        displayName: "DeepFilter 2",
        modelResourceName: ProtonDeepFilterNative.ModelResource.net2,
        isReady: ProtonDeepFilterNative.isNet2RuntimeSupported &&
          DeepFilterProcessor.isNativeReady(
            modelResourceName: ProtonDeepFilterNative.ModelResource.net2
          ),
        note: ProtonDeepFilterNative.isNet2RuntimeSupported
          ? nil
          : "libDF runtime does not support DF2 on this build",
      ),
      dtlnEntry(),
    ]
  }

  private static func rnnoiseEntry() -> [String: Any] {
    var createProbe = false
    var frameSize = 0
    if let probe = proton_rnnoise_create() {
      frameSize = Int(proton_rnnoise_get_frame_size())
      proton_rnnoise_destroy(probe)
      createProbe = frameSize > 0
    }
    return [
      "id": "rnnoise",
      "displayName": "RNNoise",
      "isReady": RnnoiseProcessor.isNativeReady,
      "details": withPlatform([
        "createProbe": createProbe,
        "frameSize": frameSize,
      ]),
    ]
  }

  private static func deepfilterEntry(
    id: String,
    displayName: String,
    modelResourceName: String,
    isReady: Bool,
    note: String? = nil
  ) -> [String: Any] {
    var details = withPlatform(
      ProtonDeepFilterNative.diagnose(modelResourceName: modelResourceName)
    )
    if let note {
      details["note"] = note
    }
    return [
      "id": id,
      "displayName": displayName,
      "isReady": isReady,
      "details": details,
    ]
  }

  private static func warmUpRnnoise() -> [String: Any] {
    let start = CFAbsoluteTimeGetCurrent()
    var warmUpOk = false
    var frameSize = 0
    if let handle = proton_rnnoise_create() {
      frameSize = Int(proton_rnnoise_get_frame_size())
      proton_rnnoise_destroy(handle)
      warmUpOk = frameSize > 0
    }
    let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    return withPlatform([
      "warmUpOk": warmUpOk,
      "warmUpMs": ms,
      "frameSize": frameSize,
    ])
  }

  private static func warmUpDeepFilter(modelResourceName: String) -> [String: Any] {
    guard ProtonDeepFilterNative.isBundled(modelResourceName: modelResourceName) else {
      return withPlatform([
        "warmUpOk": false,
        "warmUpMs": 0,
        "error": "DeepFilter runtime or model not bundled",
      ])
    }
    return withPlatform(
      DeepFilterProcessor.debugWarmUpProbe(modelResourceName: modelResourceName)
    )
  }

  private static func warmUpDtln() -> [String: Any] {
    let start = CFAbsoluteTimeGetCurrent()
    var warmUpOk = false
    var sampleRate = 0
    var blockShift = 0
    if let handle = ProtonDtlnRsNative.create() {
      sampleRate = ProtonDtlnRsNative.getSampleRate()
      blockShift = ProtonDtlnRsNative.getBlockShift()
      ProtonDtlnRsNative.destroy(handle)
      warmUpOk = sampleRate > 0 && blockShift > 0
    }
    let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    return withPlatform([
      "warmUpOk": warmUpOk,
      "warmUpMs": ms,
      "sampleRate": sampleRate,
      "blockShift": blockShift,
    ])
  }

  private static func dtlnEntry() -> [String: Any] {
    #if PROTON_DENOISE_DTLN_IOS
      let compiled = true
      var createProbe = false
      var sampleRate = 0
      var blockShift = 0
      if let probe = ProtonDtlnRsNative.create() {
        sampleRate = ProtonDtlnRsNative.getSampleRate()
        blockShift = ProtonDtlnRsNative.getBlockShift()
        ProtonDtlnRsNative.destroy(probe)
        createProbe = sampleRate > 0 && blockShift > 0
      }
      let details = withPlatform([
        "dtlnCompiled": compiled,
        "createProbe": createProbe,
        "sampleRate": sampleRate,
        "blockShift": blockShift,
      ])
    #else
      let details = withPlatform([
        "dtlnCompiled": false,
        "createProbe": false,
        "note": "DTLN not enabled in proton_denoise pod build (iOS/macOS)",
      ])
    #endif
    return [
      "id": "dtln-rs",
      "displayName": "DTLN",
      "isReady": DtlnRsProcessor.isNativeReady,
      "details": details,
    ]
  }
}
