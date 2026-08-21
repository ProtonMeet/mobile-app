import Foundation

/// Loads DeepFilterNet from an embedded framework (avoids Rust std duplicate symbols vs rust_builder).
enum ProtonDeepFilterNative {
  enum ModelResource {
    static let net3 = "DeepFilterNet3_onnx"
  }

  /// Voice-call default — caps suppression depth (dB). 100 ≈ unlimited.
  static let defaultAttenLimDb: Float = 30

  private static let sessionQueueKey = DispatchSpecificKey<Void>()

  /// All df_* calls must run on this queue — never block the main thread on it.
  static let sessionQueue: DispatchQueue = {
    let queue = DispatchQueue(label: "me.proton.meet.deepfilter.session")
    queue.setSpecific(key: sessionQueueKey, value: ())
    return queue
  }()

  static func isOnSessionQueue() -> Bool {
    DispatchQueue.getSpecific(key: sessionQueueKey) != nil
  }

  /// Runs [block] on [sessionQueue] without deadlocking when already on that queue.
  static func performOnSessionQueue(_ block: () -> Void) {
    if isOnSessionQueue() {
      block()
    } else {
      sessionQueue.sync(execute: block)
    }
  }

  private static let searchBundles: [Bundle] = [
    Bundle.main,
    Bundle(for: DeepFilterProcessor.self),
  ]

  /// Pod resources and embedded frameworks may land in different bundles (iOS vs macOS).
  private static var resourceSearchBundles: [Bundle] {
    var seen = Set<ObjectIdentifier>()
    var bundles: [Bundle] = []
    let candidates = searchBundles + Bundle.allBundles
    for bundle in candidates {
      let id = ObjectIdentifier(bundle)
      guard seen.insert(id).inserted else {
        continue
      }
      bundles.append(bundle)
    }
    // CocoaPods copies pod resources into a named bundle (static framework on iOS);
    // SwiftPM names it <package>_<target>.
    for bundleName in [
      "proton_denoise", "proton_denoise_deepfilter", "proton_denoise_proton_denoise",
    ] {
      if let url = Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
        let podBundle = Bundle(url: url)
      {
        let id = ObjectIdentifier(podBundle)
        if seen.insert(id).inserted {
          bundles.insert(podBundle, at: 0)
        }
      }
    }
    return bundles
  }

  private static func modelPath(in bundle: Bundle, resourceName: String) -> String? {
    let filename = "\(resourceName).tar.gz"
    if let path = bundle.path(forResource: resourceName, ofType: "tar.gz") {
      return path
    }
    if let url = bundle.url(forResource: resourceName, withExtension: "tar.gz") {
      return url.path
    }
    if let resourceURL = bundle.resourceURL {
      let direct = resourceURL.appendingPathComponent(filename)
      if FileManager.default.fileExists(atPath: direct.path) {
        return direct.path
      }
    }
    return nil
  }

  static func bundledModelPath(resourceName: String) -> String? {
    for bundle in resourceSearchBundles {
      if let path = modelPath(in: bundle, resourceName: resourceName) {
        return path
      }
    }
    // Legacy layout: model copied to the app bundle root.
    let rootCandidate = Bundle.main.bundlePath + "/\(resourceName).tar.gz"
    if FileManager.default.fileExists(atPath: rootCandidate) {
      return rootCandidate
    }
    return nil
  }

  #if PROTON_DENOISE_DEEPFILTER
  private static func hasRuntimeSymbols() -> Bool {
    proton_deepfilter_ensure_loaded() != 0
  }

  static func isBundled(modelResourceName: String) -> Bool {
    hasRuntimeSymbols() && bundledModelPath(resourceName: modelResourceName) != nil
  }

  /// Debug diagnostics for settings UI (read-only; safe to call from any thread).
  static func diagnose(modelResourceName: String) -> [String: Any] {
    let modelPath = bundledModelPath(resourceName: modelResourceName)
    let symbolsOk = hasRuntimeSymbols()
    var createProbe = false
    var frameSize = 0
    sessionQueue.sync {
      if let handle = createOnSessionQueue(modelResourceName: modelResourceName) {
        frameSize = getFrameSizeOnSessionQueue(handle)
        destroyOnSessionQueue(handle)
        createProbe = frameSize > 0
      }
    }
    return [
      "runtimeSymbols": symbolsOk,
      "libraryLoaded": symbolsOk,
      "cApiLinked": true,
      "dfCreate": symbolsOk,
      "dfFree": symbolsOk,
      "dfGetFrameLength": symbolsOk,
      "dfProcessFrame": symbolsOk,
      "modelFound": modelPath != nil,
      "modelPath": modelPath ?? "",
      "createProbe": createProbe,
      "frameSize": frameSize,
    ]
  }

  /// Caller must be on [sessionQueue].
  static func createOnSessionQueue(
    modelResourceName: String,
    attenLimDb: Float = defaultAttenLimDb
  ) -> OpaquePointer? {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    guard let path = bundledModelPath(resourceName: modelResourceName), hasRuntimeSymbols() else {
      return nil
    }
    return path.withCString { cPath in
      guard let raw = proton_deepfilter_create(cPath) else {
        return nil
      }
      proton_deepfilter_set_atten_lim(raw, attenLimDb)
      return raw
    }
  }

  /// Caller must be on [sessionQueue].
  static func setAttenLimOnSessionQueue(_ handle: OpaquePointer?, limDb: Float) {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    proton_deepfilter_set_atten_lim(handle, limDb)
  }

  /// Caller must be on [sessionQueue].
  static func destroyOnSessionQueue(_ handle: OpaquePointer?) {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    proton_deepfilter_destroy(handle)
  }

  /// Caller must be on [sessionQueue].
  static func getFrameSizeOnSessionQueue(_ handle: OpaquePointer?) -> Int {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    return Int(proton_deepfilter_get_frame_size(handle))
  }

  /// Called from the WebRTC audio thread; blocks only for one frame.
  static func processInterleaved(
    _ handle: OpaquePointer,
    channelBuffer: UnsafeMutablePointer<Float>,
    frameSize: Int,
    offset: Int,
    scratch: inout [Float]
  ) {
    sessionQueue.sync {
      processInterleavedOnSessionQueue(
        handle,
        channelBuffer: channelBuffer,
        frameSize: frameSize,
        offset: offset,
        scratch: &scratch
      )
    }
  }

  /// Caller must be on [sessionQueue].
  static func processInterleavedOnSessionQueue(
    _ handle: OpaquePointer,
    channelBuffer: UnsafeMutablePointer<Float>,
    frameSize: Int,
    offset: Int,
    scratch: inout [Float]
  ) {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    _ = scratch
    guard frameSize > 0 else {
      return
    }
    proton_deepfilter_set_enabled(handle, 1)
    let base = channelBuffer.advanced(by: offset)
    _ = proton_deepfilter_process_interleaved(handle, base, frameSize, 1)
  }

  #else
  typealias DfCreateFn = @convention(c) (UnsafePointer<CChar>?, Float, UnsafePointer<CChar>?) ->
    UnsafeMutableRawPointer?
  typealias DfFreeFn = @convention(c) (UnsafeMutableRawPointer?) -> Void
  typealias DfFrameLenFn = @convention(c) (UnsafeMutableRawPointer?) -> Int
  typealias DfSetAttenFn = @convention(c) (UnsafeMutableRawPointer?, Float) -> Void
  typealias DfProcessFn = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<Float>?,
    UnsafeMutablePointer<Float>?
  ) -> Float

  private static func deepFilterFrameworkURL(in bundle: Bundle) -> URL? {
    let candidates = [
      bundle.privateFrameworksURL?.appendingPathComponent("DeepFilter.framework"),
      bundle.bundleURL.appendingPathComponent("Frameworks/DeepFilter.framework"),
      bundle.url(forResource: "DeepFilter", withExtension: "framework"),
    ]
    for candidate in candidates {
      guard let url = candidate,
        FileManager.default.fileExists(atPath: url.path)
      else {
        continue
      }
      return url
    }
    return nil
  }

  private static func loadDeepFilterLibrary() -> UnsafeMutableRawPointer? {
    for bundle in searchBundles {
      guard let frameworkURL = deepFilterFrameworkURL(in: bundle),
        let fwBundle = Bundle(url: frameworkURL),
        let executable = fwBundle.executableURL
      else {
        continue
      }
      if let handle = dlopen(executable.path, RTLD_NOW) {
        return handle
      }
    }
    if let main = dlopen(nil, RTLD_NOW), dlsym(main, "df_create") != nil {
      return main
    }
    return nil
  }

  private static let library: UnsafeMutableRawPointer? = loadDeepFilterLibrary()

  private static func symbol<T>(_ name: String) -> T? {
    guard let library else {
      return nil
    }
    guard let ptr = dlsym(library, name) else {
      return nil
    }
    return unsafeBitCast(ptr, to: T.self)
  }

  private static var dfCreate: DfCreateFn? { symbol("df_create") }
  private static var dfFree: DfFreeFn? { symbol("df_free") }
  private static var dfGetFrameLength: DfFrameLenFn? { symbol("df_get_frame_length") }
  private static var dfSetAttenFn: DfSetAttenFn? { symbol("df_set_atten_lim") }
  private static var dfProcessFrame: DfProcessFn? { symbol("df_process_frame") }

  private static func hasRuntimeSymbols() -> Bool {
    library != nil &&
      dfCreate != nil &&
      dfFree != nil &&
      dfGetFrameLength != nil &&
      dfProcessFrame != nil
  }

  static func isBundled(modelResourceName: String) -> Bool {
    hasRuntimeSymbols() && bundledModelPath(resourceName: modelResourceName) != nil
  }

  /// Debug diagnostics for settings UI (read-only; safe to call from any thread).
  static func diagnose(modelResourceName: String) -> [String: Any] {
    let modelPath = bundledModelPath(resourceName: modelResourceName)
    var createProbe = false
    var frameSize = 0
    sessionQueue.sync {
      if let handle = createOnSessionQueue(modelResourceName: modelResourceName) {
        frameSize = getFrameSizeOnSessionQueue(handle)
        destroyOnSessionQueue(handle)
        createProbe = frameSize > 0
      }
    }
    return [
      "runtimeSymbols": hasRuntimeSymbols(),
      "libraryLoaded": library != nil,
      "cApiLinked": false,
      "dfCreate": dfCreate != nil,
      "dfFree": dfFree != nil,
      "dfGetFrameLength": dfGetFrameLength != nil,
      "dfProcessFrame": dfProcessFrame != nil,
      "modelFound": modelPath != nil,
      "modelPath": modelPath ?? "",
      "createProbe": createProbe,
      "frameSize": frameSize,
    ]
  }

  /// Caller must be on [sessionQueue].
  static func createOnSessionQueue(
    modelResourceName: String,
    attenLimDb: Float = defaultAttenLimDb
  ) -> OpaquePointer? {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    guard let path = bundledModelPath(resourceName: modelResourceName), let dfCreate else {
      return nil
    }
    return path.withCString { cPath in
      guard let raw = dfCreate(cPath, attenLimDb, nil) else {
        return nil
      }
      return OpaquePointer(raw)
    }
  }

  /// Caller must be on [sessionQueue].
  static func setAttenLimOnSessionQueue(_ handle: OpaquePointer?, limDb: Float) {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    guard let handle, let dfSetAttenFn else {
      return
    }
    dfSetAttenFn(UnsafeMutableRawPointer(handle), limDb)
  }

  /// Caller must be on [sessionQueue].
  static func destroyOnSessionQueue(_ handle: OpaquePointer?) {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    guard let handle, let dfFree else {
      return
    }
    dfFree(UnsafeMutableRawPointer(handle))
  }

  /// Caller must be on [sessionQueue].
  static func getFrameSizeOnSessionQueue(_ handle: OpaquePointer?) -> Int {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    guard let handle, let dfGetFrameLength else {
      return 0
    }
    return dfGetFrameLength(UnsafeMutableRawPointer(handle))
  }

  /// Called from the WebRTC audio thread; blocks only for one frame.
  static func processInterleaved(
    _ handle: OpaquePointer,
    channelBuffer: UnsafeMutablePointer<Float>,
    frameSize: Int,
    offset: Int,
    scratch: inout [Float]
  ) {
    sessionQueue.sync {
      processInterleavedOnSessionQueue(
        handle,
        channelBuffer: channelBuffer,
        frameSize: frameSize,
        offset: offset,
        scratch: &scratch
      )
    }
  }

  /// Caller must be on [sessionQueue].
  static func processInterleavedOnSessionQueue(
    _ handle: OpaquePointer,
    channelBuffer: UnsafeMutablePointer<Float>,
    frameSize: Int,
    offset: Int,
    scratch: inout [Float]
  ) {
    dispatchPrecondition(condition: .onQueue(sessionQueue))
    guard let dfProcessFrame, frameSize > 0 else {
      return
    }
    if scratch.count < frameSize {
      scratch = [Float](repeating: 0, count: frameSize)
    }
    let base = channelBuffer.advanced(by: offset)
    scratch.withUnsafeMutableBufferPointer { output in
      guard let outBase = output.baseAddress else {
        return
      }
      _ = dfProcessFrame(
        UnsafeMutableRawPointer(handle),
        base,
        outBase
      )
      for i in 0..<frameSize {
        base[i] = outBase[i]
      }
    }
  }
  #endif
}
