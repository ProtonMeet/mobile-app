/*
 * Copyright (c) 2026 Proton AG
 *
 * Per-frame blur engine (iOS + macOS).
 *
 * Pipeline (each camera frame):
 *   1. dispatchAsyncSegmentation — Vision (default) or MediaPipe TFLite (iOS debug models)
 *   2. Store latest person mask snapshot (async; one inference in flight)
 *   3. composite — blurred/replacement background + CIBlendWithMask into the live pixel buffer
 *
 * Segmentation defaults: Vision on iOS 15+ / macOS 12+; MediaPipe single-class on older iOS.
 * Blur tuning: setBlurConfig (σ, obscure opacity, mask feather/erode) from Dart
 * [BackgroundBlurConfig]. The mask edge params are Apple-only; Android has no equivalent.
 */

import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Metal
import Vision

#if os(iOS)
  import MediaPipeTasksVision
  import UIKit
#elseif os(macOS)
  import AppKit
#endif

@objc(MeetBackgroundBlurMediaPipeEngine)
public final class MeetBackgroundBlurMediaPipeEngine: NSObject {
  @objc public static var isReady: Bool {
    #if os(iOS)
      if #available(iOS 15.0, *) {
        return true
      }
      return modelPath(named: multiclassModelName) != nil
        || modelPath(named: singleClassModelName) != nil
        || modelPath(named: landscapeModelName) != nil
    #elseif os(macOS)
      if #available(macOS 12.0, *) {
        return true
      }
      return false
    #endif
  }

  private static let multiclassModelName = "selfie_multiclass_256x256"
  private static let singleClassModelName = "selfie_segmenter"
  private static let landscapeModelName = "selfie_segmenter_landscape"
  private static let squareSegmenterSize: Int = 256
  private static let landscapeInputWidth: Int = 256
  private static let landscapeInputHeight: Int = 144
  /// Lower resolution blur plate — smaller than 0.2 for speed; upscaling still hides detail.
  private static let backgroundBlurDownsample: CGFloat = 0.15
  private static let backgroundBlurPasses: Int = 1
  /// Matches Dart [BackgroundBlurConfig.defaultBlurSigma] until setBlurConfig runs.
  private static let defaultBackgroundBlurSigma: CGFloat = 128.0
  private static let minBackgroundBlurSigma: CGFloat = 4.0
  private static let maxBackgroundBlurSigma: CGFloat = 256.0
  /// How the mask is shaped between Vision's output and the blend. Mirrors Dart `MaskEdgeTuning`.
  ///
  /// Applied in a fixed order — upscale, erode, solidify, feather, gamma — which is what keeps
  /// the fields independent of one another.
  public struct MaskEdgeTuning {
    /// Feather sigma as a fraction of the output height. The look we match hides mask inaccuracy
    /// behind a wide, soft transition rather than a precise silhouette, so the softness belongs
    /// to the output size — deriving it purely from the upscale factor made it shrink exactly
    /// when a finer mask would have let us afford more of it.
    public var featherHeightFraction: CGFloat = 0.014
    /// Erosion radius as a fraction of the output height. Vision's mask runs a little wide of the
    /// real silhouette and the feather spreads it wider still, which shows up as a band of sharp,
    /// bright wall hugging the subject. Also the main lever against motion ghosting.
    public var erodeHeightFraction: CGFloat = 0.014
    /// Steepness of the confidence-to-coverage response; 1.0 disables the step.
    public var solidifySlope: CGFloat = 6.0
    /// Confidence treated as the silhouette boundary.
    public var solidifyMidpoint: CGFloat = 0.55
    /// Gamma on the finished mask; 1.0 is neutral.
    public var foregroundGamma: CGFloat = 1.0

    public init() {}

    static let maxEdgeFraction: CGFloat = 0.05

    static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
      min(max(value, lower), upper)
    }

    /// Clamped to the same ranges as the Dart side, so a bad channel payload cannot produce a
    /// degenerate mask.
    func clamped() -> MaskEdgeTuning {
      var out = MaskEdgeTuning()
      out.featherHeightFraction = Self.clamp(featherHeightFraction, 0, Self.maxEdgeFraction)
      out.erodeHeightFraction = Self.clamp(erodeHeightFraction, 0, Self.maxEdgeFraction)
      out.solidifySlope = Self.clamp(solidifySlope, 1.0, 16.0)
      out.solidifyMidpoint = Self.clamp(solidifyMidpoint, 0.2, 0.8)
      out.foregroundGamma = Self.clamp(foregroundGamma, 0.5, 3.0)
      return out
    }
  }
  /// Floor keeping the feather at least as wide as one upscaled mask pixel. Vision hands back a
  /// small mask (256x192 on `.fast`), so the staircase left by the upscale has a period of about
  /// one mask pixel and has to stay buried even when the height-derived sigma is smaller.
  private static let maskFeatherMaskPixelFraction: CGFloat = 0.9
  /// Vision input long edge. Vision rescales to its network input regardless, so anything
  /// larger just costs preprocessing on the capture thread.
  private static let visionInputMaxLongEdge: Int = 640
  /// `.balanced` measured ~45ms at 720p on Apple Silicon — above the 33ms frame period, which
  /// halves the mask refresh rate and roughly doubles the perceived lag. `.fast` stays under it.
  /// Its coarser 256x192 mask costs silhouette fidelity, but the feather is wide enough to hide
  /// that, so the finer mask is not worth the latency.
  private static let visionUsesFastQuality = true
  /// `VNGeneratePersonSegmentationRequest` is a `VNStatefulRequest`: reusing one instance lets it
  /// "hold on to previous masks to improve temporal stability". That prior is self-reinforcing, so
  /// a fast limb sweep writes a false-positive blob into it that keeps re-asserting itself and only
  /// clears once a real person stands in that region — the background stays torn open indefinitely.
  /// A per-frame request trades Vision's edge smoothing (which the feather already provides) for a
  /// mask that can never disagree with the current frame for more than one frame.
  private static let visionReusesStatefulRequest = false
  /// Recover if Vision stalls (WebRTC capture thread stops dispatching when stuck).
  private static let visionInferenceTimeoutMs: Int = 750
  /// Beyond this the mask describes a scene that has moved on, so it is dropped in favour of
  /// hiding the whole frame. Generous next to the ~40ms steady-state age: it is a backstop for a
  /// wedged segmenter, not a limit on normal jitter.
  private static let maskMaxAgeNs: UInt64 = 500 * 1_000_000
  /// Desaturate the blurred plate so colored objects are harder to recognize.
  private static let backgroundDesaturation: CGFloat = 0.5

  private let configLock = NSLock()
  private var backgroundBlurSigma: CGFloat = defaultBackgroundBlurSigma
  private var backgroundObscureOpacity: CGFloat = 0.1
  private var maskEdge = MaskEdgeTuning()
  private var synchronousSegmentation = false
  private var replacementBackgroundImage: CIImage?
  private var cachedReplacementExtent: CGRect = .zero
  private var cachedScaledReplacement: CIImage?

  private struct MaskSnapshot {
    let image: CIImage
    let data: Data
    /// Capture-thread timestamp of the camera frame this mask was segmented from.
    /// `now - capturedAtNs` at composite time is the visible "mask lags my movement" delay.
    let capturedAtNs: UInt64
  }

  private let ciContext: CIContext = MeetBackgroundBlurMediaPipeEngine.makeCIContext()

  /// Bumped on segmenter reload so late Vision / MediaPipe callbacks are ignored.
  private var segmentationGeneration: UInt64 = 0

  private var preferredModel: String?
  private var activeModelKey = "vision"
  private var activeSegmenterBackend = "apple_vision"
  private var usesAppleVision = false

  #if os(iOS)
    private var segmenter: ImageSegmenter?
    private var isMulticlassModel = false
    private var segmenterInputWidth = squareSegmenterSize
    private var segmenterInputHeight = squareSegmenterSize
    /// iOS: landscape TFLite crashes MediaPipe Tasks — use square model + 16:9 center crop instead.
    private var usesLandscapeCropPreprocess = false
    private var segmentClockMs: Int = 0
    private var inFlightGeneration: UInt64 = 0
    private let segmenterQueue = DispatchQueue(label: "meet.bgblur.segmenter", qos: .userInitiated)
    private var isReloadingSegmenter = false
    private var retainedSegmenters: [ImageSegmenter] = []
  #endif

  private let visionQueue = DispatchQueue(label: "meet.bgblur.vision", qos: .userInitiated)
  /// Separate from `visionQueue` so the stall watchdog cannot be blocked by the stalled work.
  private let watchdogQueue = DispatchQueue(label: "meet.bgblur.watchdog", qos: .utility)
  private var visionSegmentationRequest: VNGeneratePersonSegmentationRequest?
  /// Copies of the camera frame for async Vision — the WebRTC buffer is reused after onFrame
  /// returns. Pooled rather than a single scratch so a wedged inference and its replacement can
  /// hold different buffers.
  private var visionPool: CVPixelBufferPool?
  private var visionPoolWidth: Int = 0
  private var visionPoolHeight: Int = 0
  private var visionPoolFormat: OSType = 0

  private var bgraScratch: CVPixelBuffer?
  private let maskLock = NSLock()
  private var currentMask: MaskSnapshot?
  private var inferenceInFlight: Bool = false
  /// Frame timestamp of the inference currently in flight, carried onto its mask snapshot.
  private var inFlightFrameCapturedAtNs: UInt64 = 0

  // MARK: - Performance instrumentation

  #if DEBUG
    private static let perfLoggingEnabled = true
  #else
    private static let perfLoggingEnabled = false
  #endif
  /// One summary line per this many camera frames (~2s at 30fps).
  private static let perfLogFrameInterval: UInt64 = 60

  private struct PerfWindow {
    var windowStartNs: UInt64 = 0
    var frames: UInt64 = 0
    var composites: UInt64 = 0
    var dispatches: UInt64 = 0
    var skippedDispatches: UInt64 = 0
    var maskUpdates: UInt64 = 0

    var captureCopyNs: UInt64 = 0
    var inferenceNs: UInt64 = 0
    var readbackNs: UInt64 = 0
    var compositeNs: UInt64 = 0
    var maskAgeNs: UInt64 = 0
    var maxCompositeNs: UInt64 = 0
    var maxMaskAgeNs: UInt64 = 0
    var maskWidth: Int = 0
    var maskHeight: Int = 0

    mutating func reset(startNs: UInt64) {
      self = PerfWindow()
      windowStartNs = startNs
    }
  }

  private let perfLock = NSLock()
  private var perf = PerfWindow()

  private static func makeCIContext() -> CIContext {
    var options: [CIContextOption: Any] = [
      .cacheIntermediates: false,
      .workingColorSpace: NSNull(),
    ]
    if #available(iOS 17.0, macOS 14.0, *) {
      options[.allowLowPower] = false
    }
    if let device = MTLCreateSystemDefaultDevice() {
      return CIContext(mtlDevice: device, options: options)
    }
    return CIContext(options: options)
  }

  public override init() {
    super.init()
    #if os(iOS)
      segmenterQueue.sync {
        setupSegmenter()
      }
    #else
      setupSegmenter()
    #endif
  }

  public func setBlurConfig(
    blurSigma: CGFloat,
    backgroundObscureOpacity: CGFloat,
    maskEdge: MaskEdgeTuning
  ) {
    configLock.lock()
    backgroundBlurSigma = min(
      max(blurSigma, Self.minBackgroundBlurSigma),
      Self.maxBackgroundBlurSigma
    )
    self.backgroundObscureOpacity = min(max(backgroundObscureOpacity, 0.0), 1.0)
    self.maskEdge = maskEdge.clamped()
    configLock.unlock()
  }

  /// Drops any retained mask so a re-attach starts clean.
  ///
  /// The processors that own this engine are static and outlive any single track, so without
  /// this a mask stranded by a wedged inference would survive detach/attach and keep painting a
  /// stale silhouette until the process restarted.
  @objc
  public func resetSegmentationState() {
    maskLock.lock()
    currentMask = nil
    inferenceInFlight = false
    maskLock.unlock()
  }

  /// Runs segmentation inline on the capture thread instead of handing it to `visionQueue`.
  ///
  /// The async pipeline composites each frame against a mask built from an earlier one, so a
  /// fast-moving limb leaves the mask claiming foreground where the limb no longer is. Inline
  /// inference pairs every frame with its own mask and removes that lag entirely — at the cost
  /// of blocking WebRTC's capture thread for the duration, which drops capture frames if
  /// inference ever runs past the frame period. Debug-only for that reason.
  @objc
  public func setSynchronousSegmentation(_ enabled: Bool) {
    configLock.lock()
    synchronousSegmentation = enabled
    configLock.unlock()
  }

  private func isSynchronousSegmentationEnabled() -> Bool {
    configLock.lock()
    defer { configLock.unlock() }
    return synchronousSegmentation
  }

  private func currentBlurConfig() -> (
    sigma: CGFloat,
    obscureOpacity: CGFloat,
    maskEdge: MaskEdgeTuning
  ) {
    configLock.lock()
    defer { configLock.unlock() }
    return (backgroundBlurSigma, backgroundObscureOpacity, maskEdge)
  }

  @objc
  @discardableResult
  public func setReplacementBackgroundImagePath(_ path: String?) -> Bool {
    guard let path, !path.isEmpty else {
      clearReplacementBackground()
      return true
    }
    guard let image = Self.ciImage(fromPath: path) else {
      return false
    }
    configLock.lock()
    replacementBackgroundImage = image
    invalidateReplacementCacheLocked()
    configLock.unlock()
    return true
  }

  @objc
  @discardableResult
  public func setReplacementBackgroundImageData(_ data: Data?) -> Bool {
    guard let data, !data.isEmpty else {
      clearReplacementBackground()
      return true
    }
    guard let image = Self.ciImage(fromData: data) else {
      return false
    }
    configLock.lock()
    replacementBackgroundImage = image
    invalidateReplacementCacheLocked()
    configLock.unlock()
    return true
  }

  @objc
  public func clearReplacementBackground() {
    configLock.lock()
    replacementBackgroundImage = nil
    invalidateReplacementCacheLocked()
    configLock.unlock()
  }

  private func invalidateReplacementCacheLocked() {
    cachedReplacementExtent = .zero
    cachedScaledReplacement = nil
  }

  @objc
  public func setSegmentationModelPreference(model: String) {
    #if os(iOS)
      preferredModel = model
      segmenterQueue.sync {
        performReloadSegmenter()
      }
    #elseif os(macOS)
      guard model == "vision" else { return }
      preferredModel = model
      if #available(macOS 12.0, *) {
        configureAppleVision()
      }
    #endif
  }

  @objc
  public func segmentationModelDebugInfo() -> [String: Any] {
    #if os(iOS) || os(macOS)
      return [
        "model": activeModelKey,
        "backend": activeSegmenterBackend,
        "forced": preferredModel != nil,
        "supported": true,
      ]
    #else
      return [
        "model": "none",
        "backend": "none",
        "forced": false,
        "supported": false,
      ]
    #endif
  }

  @available(iOS 15.0, macOS 12.0, *)
  private func configureAppleVision() {
    usesAppleVision = true
    activeModelKey = "vision"
    activeSegmenterBackend = "apple_vision"
    #if os(iOS)
      usesLandscapeCropPreprocess = false
      isMulticlassModel = false
      segmenter = nil
    #endif
  }

  #if os(iOS)

    private func performReloadSegmenter() {
      isReloadingSegmenter = true
      drainInferenceInFlight(timeoutMs: 350)
      if let old = segmenter {
        retainedSegmenters.append(old)
      }
      segmenter = nil
      bgraScratch = nil
      segmentationGeneration &+= 1
      maskLock.lock()
      currentMask = nil
      inferenceInFlight = false
      maskLock.unlock()
      setupSegmenter()
      isReloadingSegmenter = false
      let generationAtReload = segmentationGeneration
      segmenterQueue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
        guard let self, self.segmentationGeneration == generationAtReload else { return }
        self.retainedSegmenters.removeAll()
      }
    }

    /// Wait for an in-flight `segmentAsync` callback before destroying the segmenter graph.
    private func drainInferenceInFlight(timeoutMs: Int) {
      let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(timeoutMs) * 1_000_000
      while DispatchTime.now().uptimeNanoseconds < deadline {
        maskLock.lock()
        let flying = inferenceInFlight
        maskLock.unlock()
        if !flying {
          return
        }
        Thread.sleep(forTimeInterval: 0.005)
      }
      maskLock.lock()
      inferenceInFlight = false
      maskLock.unlock()
    }

    private struct ResolvedSegmenterModel {
      let path: String
      let key: String
      let isMulticlass: Bool
      let inputWidth: Int
      let inputHeight: Int
    }

    private func resolveSegmenterModel() -> ResolvedSegmenterModel? {
      usesLandscapeCropPreprocess = false
      let multiclassPath = Self.modelPath(named: Self.multiclassModelName)
      let singleClassPath = Self.modelPath(named: Self.singleClassModelName)
      let landscapePath = Self.modelPath(named: Self.landscapeModelName)

      func pick(
        _ key: String,
        path: String?,
        isMulticlass: Bool,
        width: Int,
        height: Int
      ) -> ResolvedSegmenterModel? {
        guard let path else { return nil }
        return ResolvedSegmenterModel(
          path: path,
          key: key,
          isMulticlass: isMulticlass,
          inputWidth: width,
          inputHeight: height
        )
      }

      if let preferredModel {
        switch preferredModel {
        case "vision":
          return nil
        case "landscape":
          // The landscape TFLite graph crashes MediaPipe Tasks on iOS (native bad_function_call).
          // Emulate Meet-style 16:9 segmentation with the stable square model + center crop.
          usesLandscapeCropPreprocess = true
          if let resolved = pick(
            "landscape",
            path: singleClassPath,
            isMulticlass: false,
            width: Self.squareSegmenterSize,
            height: Self.squareSegmenterSize
          ) {
            return resolved
          }
          usesLandscapeCropPreprocess = false
        case "multiclass":
          return pick(
            "multiclass",
            path: multiclassPath,
            isMulticlass: true,
            width: Self.squareSegmenterSize,
            height: Self.squareSegmenterSize
          )
        case "single":
          return pick(
            "single",
            path: singleClassPath,
            isMulticlass: false,
            width: Self.squareSegmenterSize,
            height: Self.squareSegmenterSize
          )
        default:
          break
        }
      }

      return pick(
        "single",
        path: singleClassPath,
        isMulticlass: false,
        width: Self.squareSegmenterSize,
        height: Self.squareSegmenterSize
      )
        ?? pick(
          "landscape",
          path: landscapePath,
          isMulticlass: false,
          width: Self.landscapeInputWidth,
          height: Self.landscapeInputHeight
        )
        ?? pick(
          "multiclass",
          path: multiclassPath,
          isMulticlass: true,
          width: Self.squareSegmenterSize,
          height: Self.squareSegmenterSize
        )
    }
  #endif

  private func setupSegmenter() {
    #if os(macOS)
      if #available(macOS 12.0, *) {
        configureAppleVision()
      }
    #elseif os(iOS)
      let wantsVision = preferredModel == nil || preferredModel == "vision"
      if wantsVision {
        if #available(iOS 15.0, *) {
          configureAppleVision()
          return
        }
      }
      usesAppleVision = false

      guard let resolved = resolveSegmenterModel() else {
        segmenter = nil
        activeSegmenterBackend = "none"
        return
      }
      let path = resolved.path
      isMulticlassModel = resolved.isMulticlass
      activeModelKey = resolved.key
      segmenterInputWidth = resolved.inputWidth
      segmenterInputHeight = resolved.inputHeight

      let delegatesToTry: [Delegate]
      #if targetEnvironment(simulator)
        delegatesToTry = [.CPU]
      #else
        // Multiclass + landscape-crop paths use CPU (GPU delegate is unstable on iOS).
        if usesLandscapeCropPreprocess || resolved.key == "multiclass" {
          delegatesToTry = [.CPU]
        } else {
          delegatesToTry = [.GPU, .CPU]
        }
      #endif

      activeSegmenterBackend = "none"
      for delegate in delegatesToTry {
        let options = ImageSegmenterOptions()
        options.runningMode = .liveStream
        options.imageSegmenterLiveStreamDelegate = self
        options.shouldOutputCategoryMask = false
        options.shouldOutputConfidenceMasks = true
        options.baseOptions.modelAssetPath = path
        options.baseOptions.delegate = delegate
        do {
          segmenter = try ImageSegmenter(options: options)
          activeSegmenterBackend = delegate == .GPU ? "mediapipe_gpu" : "mediapipe_cpu"
          return
        } catch {
          continue
        }
      }
      segmenter = nil
      activeSegmenterBackend = "none"
      // Last resort: never leave blur without a segmenter when single-class exists.
      if segmenter == nil, let singlePath = Self.modelPath(named: Self.singleClassModelName) {
        usesLandscapeCropPreprocess = false
        isMulticlassModel = false
        activeModelKey = "single"
        segmenterInputWidth = Self.squareSegmenterSize
        segmenterInputHeight = Self.squareSegmenterSize
        for delegate in [Delegate.CPU] {
          let options = ImageSegmenterOptions()
          options.runningMode = .liveStream
          options.imageSegmenterLiveStreamDelegate = self
          options.shouldOutputCategoryMask = false
          options.shouldOutputConfidenceMasks = true
          options.baseOptions.modelAssetPath = singlePath
          options.baseOptions.delegate = delegate
          if let created = try? ImageSegmenter(options: options) {
            segmenter = created
            activeSegmenterBackend = "mediapipe_cpu"
            break
          }
        }
      }
    #endif
  }

  #if os(iOS)
    private static func modelPath(named name: String) -> String? {
      let bundles: [Bundle] = [
        Bundle(for: MeetBackgroundBlurMediaPipeEngine.self),
        Bundle.main,
      ]
      for bundle in bundles {
        if let path = bundle.path(forResource: name, ofType: "tflite", inDirectory: "Resources")
          ?? bundle.path(forResource: name, ofType: "tflite")
        {
          return path
        }
      }
      return nil
    }
  #endif

  private func outputColorSpace(forPixelFormat fmt: OSType) -> CGColorSpace {
    switch fmt {
    case kCVPixelFormatType_32BGRA:
      return CGColorSpace(name: CGColorSpace.sRGB)!
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
      return CGColorSpace(name: CGColorSpace.itur_709)!
    default:
      return CGColorSpace(name: CGColorSpace.sRGB)!
    }
  }

  private func ensureBGRAScratch(width: Int, height: Int) -> CVPixelBuffer? {
    if let buf = bgraScratch,
      CVPixelBufferGetWidth(buf) == width,
      CVPixelBufferGetHeight(buf) == height
    {
      return buf
    }
    bgraScratch = nil
    var out: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    let st = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &out)
    guard st == kCVReturnSuccess, let buf = out else { return nil }
    bgraScratch = buf
    return buf
  }

  /// Vends a Vision input buffer that stays valid for as long as the inference holds it.
  ///
  /// A single reused scratch buffer only works while exactly one inference is ever in flight.
  /// The stall watchdog deliberately breaks that invariant — it lets a new inference start while
  /// a wedged one is still reading — so the capture thread would otherwise overwrite a buffer
  /// mid-read. A pool hands each inference its own buffer and recycles it on release, so the
  /// allocation cost stays bounded without the aliasing.
  private func dequeueVisionFrameBuffer(
    width: Int,
    height: Int,
    pixelFormat: OSType
  ) -> CVPixelBuffer? {
    if visionPool == nil
      || visionPoolWidth != width
      || visionPoolHeight != height
      || visionPoolFormat != pixelFormat
    {
      let attrs: [String: Any] = [
        kCVPixelBufferCGImageCompatibilityKey as String: true,
        kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        kCVPixelBufferMetalCompatibilityKey as String: true,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
      ]
      var pool: CVPixelBufferPool?
      let st = CVPixelBufferPoolCreate(
        kCFAllocatorDefault,
        nil,
        attrs as CFDictionary,
        &pool
      )
      guard st == kCVReturnSuccess, let pool else { return nil }
      visionPool = pool
      visionPoolWidth = width
      visionPoolHeight = height
      visionPoolFormat = pixelFormat
    }
    guard let pool = visionPool else { return nil }
    var out: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &out) == kCVReturnSuccess
    else {
      return nil
    }
    return out
  }

  /// Snapshot the live camera buffer before handing it to Vision on a background queue.
  ///
  /// Also downscales in the same render: Vision resizes to its own network input anyway, so
  /// feeding it 720p only pays for preprocessing. Halving the long edge keeps this render —
  /// which runs on the WebRTC capture thread — cheap.
  private func copyForVisionInference(from source: CVPixelBuffer) -> CVPixelBuffer? {
    let w = CVPixelBufferGetWidth(source)
    let h = CVPixelBufferGetHeight(source)
    guard w > 0, h > 0 else { return nil }

    let longEdge = max(w, h)
    let scale =
      longEdge > Self.visionInputMaxLongEdge
      ? CGFloat(Self.visionInputMaxLongEdge) / CGFloat(longEdge)
      : 1.0
    // Even dimensions keep the aspect ratio exact for chroma-subsampled sources.
    let targetW = max(2, Int((CGFloat(w) * scale).rounded()) & ~1)
    let targetH = max(2, Int((CGFloat(h) * scale).rounded()) & ~1)

    guard
      let dst = dequeueVisionFrameBuffer(
        width: targetW,
        height: targetH,
        pixelFormat: kCVPixelFormatType_32BGRA
      )
    else {
      return nil
    }
    let image = CIImage(cvPixelBuffer: source)
      .transformed(
        by: CGAffineTransform(
          scaleX: CGFloat(targetW) / CGFloat(w),
          y: CGFloat(targetH) / CGFloat(h)
        ))
    let bounds = CGRect(x: 0, y: 0, width: CGFloat(targetW), height: CGFloat(targetH))
    ciContext.render(
      image, to: dst, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    return dst
  }

  #if os(iOS)
    private func workingBGRABuffer(from source: CVPixelBuffer) -> CVPixelBuffer? {
      if usesLandscapeCropPreprocess {
        return workingBGRABufferWithLandscapeCrop(from: source)
      }
      let w = CVPixelBufferGetWidth(source)
      let h = CVPixelBufferGetHeight(source)
      guard w > 0, h > 0 else { return nil }
      let targetW = segmenterInputWidth
      let targetH = segmenterInputHeight
      guard let dst = ensureBGRAScratch(width: targetW, height: targetH) else { return nil }
      let scaleX = CGFloat(targetW) / CGFloat(w)
      let scaleY = CGFloat(targetH) / CGFloat(h)
      let image = CIImage(cvPixelBuffer: source)
        .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
      let bounds = CGRect(x: 0, y: 0, width: CGFloat(targetW), height: CGFloat(targetH))
      let cs = CGColorSpace(name: CGColorSpace.sRGB)!
      ciContext.render(image, to: dst, bounds: bounds, colorSpace: cs)
      return dst
    }

    /// Center-crop to 16:9 (Meet / landscape segmenter aspect) then scale to 256² for the square model.
    private func workingBGRABufferWithLandscapeCrop(from source: CVPixelBuffer) -> CVPixelBuffer? {
      let targetSize = Self.squareSegmenterSize
      guard let dst = ensureBGRAScratch(width: targetSize, height: targetSize) else { return nil }

      let image = CIImage(cvPixelBuffer: source)
      let extent = image.extent
      guard extent.width >= 1, extent.height >= 1 else { return nil }

      let targetAspect = CGFloat(Self.landscapeInputWidth) / CGFloat(Self.landscapeInputHeight)
      let srcAspect = extent.width / extent.height
      var cropX = extent.origin.x
      var cropY = extent.origin.y
      var cropW = extent.width
      var cropH = extent.height
      if srcAspect > targetAspect {
        cropW = extent.height * targetAspect
        cropX = extent.origin.x + (extent.width - cropW) / 2
      } else if srcAspect < targetAspect {
        cropH = extent.width / targetAspect
        cropY = extent.origin.y + (extent.height - cropH) / 2
      }

      let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
      let cropped = image.cropped(to: cropRect)
      let translated = cropped.transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
      let scaleX = CGFloat(targetSize) / cropW
      let scaleY = CGFloat(targetSize) / cropH
      let scaled = translated.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
      let bounds = CGRect(x: 0, y: 0, width: CGFloat(targetSize), height: CGFloat(targetSize))
      let cs = CGColorSpace(name: CGColorSpace.sRGB)!
      ciContext.render(scaled, to: dst, bounds: bounds, colorSpace: cs)
      return dst
    }

    private func makeFloatMaskSnapshot(from mask: Mask, capturedAtNs: UInt64) -> MaskSnapshot? {
      let w = mask.width
      let h = mask.height
      guard w > 0, h > 0 else { return nil }
      let rowBytes = w * MemoryLayout<Float>.size
      let byteCount = rowBytes * h
      var data = Data(count: byteCount)
      let src = mask.float32Data
      let invertToForeground = isMulticlassModel
      data.withUnsafeMutableBytes { raw in
        guard let dst = raw.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
        let pixelCount = w * h
        for i in 0..<pixelCount {
          let confidence = src[i]
          dst[i] = invertToForeground ? (1.0 - confidence) : confidence
        }
      }
      let cs = CGColorSpace(name: CGColorSpace.linearGray)!
      let image = CIImage(
        bitmapData: data,
        bytesPerRow: rowBytes,
        size: CGSize(width: CGFloat(w), height: CGFloat(h)),
        format: .Lf,
        colorSpace: cs)
      return MaskSnapshot(image: image, data: data, capturedAtNs: capturedAtNs)
    }
  #endif

  @available(iOS 15.0, macOS 12.0, *)
  private func makeVisionMaskSnapshot(
    from pixelBuffer: CVPixelBuffer,
    capturedAtNs: UInt64
  ) -> MaskSnapshot? {
    let w = CVPixelBufferGetWidth(pixelBuffer)
    let h = CVPixelBufferGetHeight(pixelBuffer)
    guard w > 0, h > 0 else { return nil }

    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

    let srcStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    var data = Data(count: w * h)
    data.withUnsafeMutableBytes { raw in
      guard let dst = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
      let src = base.assumingMemoryBound(to: UInt8.self)
      for y in 0..<h {
        memcpy(dst.advanced(by: y * w), src.advanced(by: y * srcStride), w)
      }
    }

    let cs = CGColorSpace(name: CGColorSpace.linearGray)!
    let image = CIImage(
      bitmapData: data,
      bytesPerRow: w,
      size: CGSize(width: CGFloat(w), height: CGFloat(h)),
      format: .L8,
      colorSpace: cs
    )
    return MaskSnapshot(image: image, data: data, capturedAtNs: capturedAtNs)
  }

  @available(iOS 15.0, macOS 12.0, *)
  private func visionRequest() -> VNGeneratePersonSegmentationRequest {
    if Self.visionReusesStatefulRequest, let request = visionSegmentationRequest {
      return request
    }
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = Self.visionUsesFastQuality ? .fast : .balanced
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    if Self.visionReusesStatefulRequest {
      visionSegmentationRequest = request
    }
    return request
  }

  @objc
  public func applyPersonBackgroundBlur(to pixelBuffer: CVPixelBuffer, rotationDegrees: Int32) {
    _ = rotationDegrees
    let frameStartNs = Self.nowNs()

    maskLock.lock()
    let canDispatch = !inferenceInFlight
    if canDispatch {
      inferenceInFlight = true
      inFlightFrameCapturedAtNs = frameStartNs
    }
    maskLock.unlock()

    recordFrame(dispatched: canDispatch, atNs: frameStartNs)

    if canDispatch {
      if useSynchronousVisionSegmentation(), #available(iOS 15.0, macOS 12.0, *) {
        // Blocks until this frame's own mask exists, so the read below picks it up.
        performVisionSegmentationInline(on: pixelBuffer, capturedAtNs: frameStartNs)
      } else {
        // Times the synchronous capture-thread work only; inference itself runs async.
        let copyStartNs = Self.nowNs()
        dispatchAsyncSegmentation(on: pixelBuffer)
        recordCaptureCopy(ns: Self.nowNs() &- copyStartNs)
      }
    }

    // Read after segmenting rather than before: in synchronous mode the mask for this very frame
    // has just landed, and taking it here is the whole point of that mode. Async is unaffected —
    // its dispatch returns before any mask is stored.
    //
    // A mask this old no longer describes the scene, so trusting it would paint the real room
    // wherever it still claims foreground. Dropping it hides everything instead, which is the
    // safe direction to fail for a privacy feature.
    maskLock.lock()
    let snapshot = currentMask.flatMap { mask -> MaskSnapshot? in
      let ageNs = Self.nowNs() &- mask.capturedAtNs
      return ageNs > Self.maskMaxAgeNs ? nil : mask
    }
    maskLock.unlock()

    // No usable mask still composites: passing the frame through untouched would publish the
    // real room. Without a mask the plate covers everything, so the subject is hidden too.
    let compositeStartNs = Self.nowNs()
    composite(pixelBuffer: pixelBuffer, mask: snapshot)
    let compositeEndNs = Self.nowNs()
    recordComposite(
      ns: compositeEndNs &- compositeStartNs,
      maskAgeNs: snapshot.map { compositeEndNs &- $0.capturedAtNs } ?? 0,
      maskSize: snapshot?.image.extent.size ?? .zero
    )
    maybeLogPerf(nowNs: compositeEndNs)
  }

  /// Composites `snapshot` over the background plate, or hides the whole frame when it is nil.
  private func composite(pixelBuffer: CVPixelBuffer, mask snapshot: MaskSnapshot?) {
    let input = CIImage(cvPixelBuffer: pixelBuffer)
    let ire = input.extent
    guard ire.width >= 1, ire.height >= 1 else { return }

    let config = currentBlurConfig()
    let backgroundPlate = makeBackgroundPlate(from: input, extent: ire, config: config)

    guard let snapshot else {
      renderComposite(backgroundPlate, to: pixelBuffer, extent: ire)
      return
    }

    let maskImage = snapshot.image
    let mre = maskImage.extent
    guard mre.width >= 1, mre.height >= 1 else {
      renderComposite(backgroundPlate, to: pixelBuffer, extent: ire)
      return
    }

    let scaleX = ire.width / mre.width
    let scaleY = ire.height / mre.height
    // Erode, then feather, both after the upscale. A sigma applied in mask space shrinks by the
    // scale factor on the way up, leaving the resampling staircase along diagonal edges intact.
    // Eroding first is what keeps the two independent: it moves the boundary without touching the
    // ramp, so widening the feather softens the edge instead of pushing it out into the wall.
    // Harden last, so the gamma reshapes a smooth full-resolution gradient instead of steepening
    // the coarse mask into an edge the feather then has to undo.
    let edge = config.maskEdge
    let featherSigma = max(
      1.0,
      edge.featherHeightFraction * ire.height,
      Self.maskFeatherMaskPixelFraction * max(scaleX, scaleY)
    )
    let feathered = hardenForegroundMask(
      solidifyMask(
        erodeMask(
          upscaleMask(maskImage, scaleX: scaleX, scaleY: scaleY).clampedToExtent(),
          radius: edge.erodeHeightFraction * ire.height
        ),
        slope: edge.solidifySlope,
        midpoint: edge.solidifyMidpoint
      )
      .clampedToExtent()
      .applyingGaussianBlur(sigma: featherSigma),
      gamma: edge.foregroundGamma
    ).cropped(to: ire)

    guard let blend = CIFilter(name: "CIBlendWithMask") else { return }
    // Mask is always foreground (person) confidence — same as Android after inversion.
    blend.setValue(input, forKey: kCIInputImageKey)
    blend.setValue(backgroundPlate, forKey: kCIInputBackgroundImageKey)
    blend.setValue(feathered, forKey: kCIInputMaskImageKey)
    guard let out = blend.outputImage else { return }
    renderComposite(out, to: pixelBuffer, extent: ire)
  }

  private func makeBackgroundPlate(
    from input: CIImage,
    extent: CGRect,
    config: (sigma: CGFloat, obscureOpacity: CGFloat, maskEdge: MaskEdgeTuning)
  ) -> CIImage {
    if let replacement = scaledReplacementBackground(extent: extent) {
      return replacement
    }
    let blurredBackground = makeBlurredBackgroundPlate(
      from: input,
      extent: extent,
      blurSigma: config.sigma
    )
    return applyObscureVeil(
      to: blurredBackground,
      extent: extent,
      opacity: config.obscureOpacity
    )
  }

  private func renderComposite(_ image: CIImage, to pixelBuffer: CVPixelBuffer, extent: CGRect) {
    let out = image.cropped(to: extent)
    let dstFmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
    let outCS = outputColorSpace(forPixelFormat: dstFmt)

    let lock = CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    guard lock == kCVReturnSuccess else { return }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0)) }

    ciContext.render(out, to: pixelBuffer, bounds: extent, colorSpace: outCS)
  }

  private func dispatchAsyncSegmentation(on pixelBuffer: CVPixelBuffer) {
    if usesAppleVision {
      if #available(iOS 15.0, macOS 12.0, *) {
        dispatchVisionSegmentation(on: pixelBuffer)
      } else {
        clearInferenceInFlight()
      }
      return
    }
    #if os(iOS)
      guard let work = workingBGRABuffer(from: pixelBuffer) else {
        clearInferenceInFlight()
        return
      }
      let dispatchGeneration = segmentationGeneration
      segmenterQueue.async { [weak self] in
        guard let self else { return }
        if self.isReloadingSegmenter || dispatchGeneration != self.segmentationGeneration {
          self.clearInferenceInFlight()
          return
        }
        guard let segmenter = self.segmenter else {
          self.clearInferenceInFlight()
          return
        }
        let mpImage: MPImage
        do {
          mpImage = try MPImage(pixelBuffer: work, orientation: .up)
        } catch {
          self.clearInferenceInFlight()
          return
        }
        self.maskLock.lock()
        self.inFlightGeneration = dispatchGeneration
        self.maskLock.unlock()
        self.segmentClockMs += 33
        do {
          try segmenter.segmentAsync(
            image: mpImage,
            timestampInMilliseconds: self.segmentClockMs
          )
        } catch {
          self.clearInferenceInFlight()
        }
      }
    #endif
  }

  /// Only Vision has an inline path; the MediaPipe segmenter is callback-driven.
  private func useSynchronousVisionSegmentation() -> Bool {
    guard usesAppleVision else { return false }
    return isSynchronousSegmentationEnabled()
  }

  /// Segments on the calling (capture) thread and stores the mask before returning.
  ///
  /// No watchdog here, unlike the async path: there is no other thread left to rescue this one.
  /// A wedged Vision call blocks capture outright, which is the risk this mode trades for having
  /// the mask match the frame.
  @available(iOS 15.0, macOS 12.0, *)
  private func performVisionSegmentationInline(
    on pixelBuffer: CVPixelBuffer,
    capturedAtNs: UInt64
  ) {
    defer { clearInferenceInFlight() }

    let copyStartNs = Self.nowNs()
    guard let inferenceBuffer = copyForVisionInference(from: pixelBuffer) else { return }
    recordCaptureCopy(ns: Self.nowNs() &- copyStartNs)

    let generation = segmentationGeneration
    let request = visionRequest()
    let handler = VNImageRequestHandler(cvPixelBuffer: inferenceBuffer, options: [:])
    do {
      let inferenceStartNs = Self.nowNs()
      try handler.perform([request])
      let inferenceEndNs = Self.nowNs()
      guard let observation = request.results?.first as? VNPixelBufferObservation else { return }
      let snapshot = makeVisionMaskSnapshot(
        from: observation.pixelBuffer,
        capturedAtNs: capturedAtNs
      )
      recordInference(
        ns: inferenceEndNs &- inferenceStartNs,
        readbackNs: Self.nowNs() &- inferenceEndNs
      )
      maskLock.lock()
      if generation == segmentationGeneration, let snapshot {
        storeMaskIfNewerLocked(snapshot)
      }
      maskLock.unlock()
    } catch {
      // defer clears inferenceInFlight
    }
  }

  @available(iOS 15.0, macOS 12.0, *)
  private func dispatchVisionSegmentation(on pixelBuffer: CVPixelBuffer) {
    // Copy on the capture thread: WebRTC recycles `pixelBuffer` once onFrame returns.
    guard let inferenceBuffer = copyForVisionInference(from: pixelBuffer) else {
      clearInferenceInFlight()
      return
    }

    let generation = segmentationGeneration
    maskLock.lock()
    let capturedAtNs = inFlightFrameCapturedAtNs
    maskLock.unlock()

    // Not on visionQueue: it is serial, so a watchdog queued there waits behind the very
    // inference it is meant to rescue and can only ever run once that inference has already
    // finished and cancelled it. A wedged Vision call would otherwise pin `inferenceInFlight`
    // forever, stopping all further dispatches and freezing the mask for the process lifetime.
    let watchdog = DispatchWorkItem { [weak self] in
      self?.clearInferenceInFlight()
    }
    watchdogQueue.asyncAfter(
      deadline: .now() + .milliseconds(Self.visionInferenceTimeoutMs),
      execute: watchdog
    )

    visionQueue.async { [weak self] in
      guard let self else { return }
      defer {
        watchdog.cancel()
        self.clearInferenceInFlight()
      }
      guard generation == self.segmentationGeneration else { return }

      let request = self.visionRequest()
      let handler = VNImageRequestHandler(cvPixelBuffer: inferenceBuffer, options: [:])
      do {
        let inferenceStartNs = Self.nowNs()
        try handler.perform([request])
        let inferenceEndNs = Self.nowNs()
        var newSnapshot: MaskSnapshot?
        if let observation = request.results?.first as? VNPixelBufferObservation {
          newSnapshot = self.makeVisionMaskSnapshot(
            from: observation.pixelBuffer,
            capturedAtNs: capturedAtNs
          )
        }
        self.recordInference(
          ns: inferenceEndNs &- inferenceStartNs,
          readbackNs: Self.nowNs() &- inferenceEndNs
        )
        self.maskLock.lock()
        if generation == self.segmentationGeneration, let snapshot = newSnapshot {
          self.storeMaskIfNewerLocked(snapshot)
        }
        self.maskLock.unlock()
      } catch {
        // defer clears inferenceInFlight
      }
    }
  }

  private func clearInferenceInFlight() {
    maskLock.lock()
    inferenceInFlight = false
    maskLock.unlock()
  }

  /// Keeps the stored mask monotonic in capture time. Once the watchdog can let a second
  /// inference start behind a wedged one, completions are no longer ordered, and a late result
  /// carrying an old frame's timestamp would otherwise replace a fresher mask and snap the
  /// silhouette back to where the subject used to be.
  private func storeMaskIfNewerLocked(_ snapshot: MaskSnapshot) {
    if let existing = currentMask, snapshot.capturedAtNs <= existing.capturedAtNs {
      return
    }
    currentMask = snapshot
  }

  // MARK: - Performance instrumentation

  private static func nowNs() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
  }

  private func recordFrame(dispatched: Bool, atNs: UInt64) {
    guard Self.perfLoggingEnabled else { return }
    perfLock.lock()
    if perf.windowStartNs == 0 {
      perf.windowStartNs = atNs
    }
    perf.frames += 1
    if dispatched {
      perf.dispatches += 1
    } else {
      perf.skippedDispatches += 1
    }
    perfLock.unlock()
  }

  private func recordCaptureCopy(ns: UInt64) {
    guard Self.perfLoggingEnabled else { return }
    perfLock.lock()
    perf.captureCopyNs += ns
    perfLock.unlock()
  }

  private func recordInference(ns: UInt64, readbackNs: UInt64) {
    guard Self.perfLoggingEnabled else { return }
    perfLock.lock()
    perf.inferenceNs += ns
    perf.readbackNs += readbackNs
    perf.maskUpdates += 1
    perfLock.unlock()
  }

  private func recordComposite(ns: UInt64, maskAgeNs: UInt64, maskSize: CGSize) {
    guard Self.perfLoggingEnabled else { return }
    perfLock.lock()
    perf.composites += 1
    perf.maskWidth = Int(maskSize.width)
    perf.maskHeight = Int(maskSize.height)
    perf.compositeNs += ns
    perf.maskAgeNs += maskAgeNs
    perf.maxCompositeNs = max(perf.maxCompositeNs, ns)
    perf.maxMaskAgeNs = max(perf.maxMaskAgeNs, maskAgeNs)
    perfLock.unlock()
  }

  /// Emits one aggregated line per window so logging never dominates the measurement.
  private func maybeLogPerf(nowNs: UInt64) {
    guard Self.perfLoggingEnabled else { return }
    perfLock.lock()
    guard perf.frames >= Self.perfLogFrameInterval else {
      perfLock.unlock()
      return
    }
    let window = perf
    perf.reset(startNs: nowNs)
    perfLock.unlock()

    let elapsedS = Double(nowNs &- window.windowStartNs) / 1_000_000_000
    guard elapsedS > 0 else { return }

    func ms(_ total: UInt64, _ count: UInt64) -> String {
      guard count > 0 else { return "n/a" }
      return String(format: "%.1f", Double(total) / Double(count) / 1_000_000)
    }
    func ms(_ value: UInt64) -> String {
      String(format: "%.1f", Double(value) / 1_000_000)
    }

    let frameFps = Double(window.frames) / elapsedS
    let maskFps = Double(window.maskUpdates) / elapsedS
    let backend = usesAppleVision ? activeSegmenterBackend : activeModelKey
    let quality = Self.visionUsesFastQuality ? "fast" : "balanced"
    let mode = useSynchronousVisionSegmentation() ? "sync" : "async"
    let state = Self.visionReusesStatefulRequest ? "stateful" : "stateless"

    print(
      """
      [MeetBlurPerf] \(backend)/\(quality)/\(mode)/\(state) \
      mask=\(window.maskWidth)x\(window.maskHeight) \
      frameFps=\(String(format: "%.1f", frameFps)) \
      maskFps=\(String(format: "%.1f", maskFps)) | \
      maskAge avg=\(ms(window.maskAgeNs, window.composites))ms max=\(ms(window.maxMaskAgeNs))ms | \
      composite avg=\(ms(window.compositeNs, window.composites))ms \
      max=\(ms(window.maxCompositeNs))ms | \
      captureCopy avg=\(ms(window.captureCopyNs, window.dispatches))ms | \
      inference avg=\(ms(window.inferenceNs, window.maskUpdates))ms | \
      maskReadback avg=\(ms(window.readbackNs, window.maskUpdates))ms | \
      dispatched=\(window.dispatches) skipped=\(window.skippedDispatches)
      """
    )
  }

  /// Scales the segmentation mask up to frame size.
  ///
  /// Vision's mask is small (256x192 on `.fast`) and squashed to the model's own aspect ratio, so
  /// this is a non-uniform ~5x upscale. An affine transform resamples bilinearly and leaves a
  /// staircase on diagonal edges that is too coarse for the feather to hide; Lanczos reconstructs
  /// a far smoother ramp for the same output size.
  private func upscaleMask(_ mask: CIImage, scaleX: CGFloat, scaleY: CGFloat) -> CIImage {
    let affine = mask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    guard scaleY > 0, let lanczos = CIFilter(name: "CILanczosScaleTransform") else { return affine }
    lanczos.setValue(mask, forKey: kCIInputImageKey)
    lanczos.setValue(scaleY, forKey: kCIInputScaleKey)
    lanczos.setValue(scaleX / scaleY, forKey: kCIInputAspectRatioKey)
    return lanczos.outputImage ?? affine
  }

  /// Pulls the mask boundary inward by `radius` output pixels. A morphological minimum moves the
  /// edge while leaving the ramp's shape alone, unlike a gamma, which shrinks the foreground only
  /// by steepening the very gradient the feather is there to provide.
  private func erodeMask(_ mask: CIImage, radius: CGFloat) -> CIImage {
    guard radius >= 0.5, let erode = CIFilter(name: "CIMorphologyMinimum") else { return mask }
    erode.setValue(mask, forKey: kCIInputImageKey)
    erode.setValue(Float(radius), forKey: kCIInputRadiusKey)
    return erode.outputImage ?? mask
  }

  /// Drives confident interior values to a solid 1.0 and confident exterior values to 0.
  ///
  /// Vision reports confidence, not coverage, so the middle of the subject can sit well below
  /// 1.0 — and `CIBlendWithMask` reads that as translucency, letting the background show through
  /// the person. Steepening the response around the midpoint makes the body opaque while leaving
  /// a narrow ramp at the boundary, which the feather that runs next widens back into a soft
  /// edge. Running before the blur is what keeps the edge smooth: the reverse order would
  /// re-sharpen the very gradient the feather just created.
  private func solidifyMask(_ mask: CIImage, slope: CGFloat, midpoint: CGFloat) -> CIImage {
    guard slope > 1.0 else { return mask }
    let bias = 0.5 - slope * midpoint
    let stretched = mask.applyingFilter(
      "CIColorMatrix",
      parameters: [
        "inputRVector": CIVector(x: slope, y: 0, z: 0, w: 0),
        "inputGVector": CIVector(x: 0, y: slope, z: 0, w: 0),
        "inputBVector": CIVector(x: 0, y: 0, z: slope, w: 0),
        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
      ]
    )
    // The matrix pushes values past 0 and 1; without clamping those overshoots survive into the
    // blend as out-of-range alpha.
    return stretched.applyingFilter("CIColorClamp")
  }

  /// Reweights soft foreground confidence. Above 1.0 shrinks it so the background covers more of
  /// the frame; below 1.0 grows it. Either way it steepens or flattens the feather's ramp, which
  /// is why the neutral 1.0 short-circuits rather than running a no-op filter every frame.
  private func hardenForegroundMask(_ mask: CIImage, gamma: CGFloat) -> CIImage {
    guard gamma != 1.0 else { return mask }
    return mask.applyingFilter("CIGammaAdjust", parameters: ["inputPower": gamma])
  }

  private static func ciImage(fromPath path: String) -> CIImage? {
    #if os(iOS)
      guard let uiImage = UIImage(contentsOfFile: path) else { return nil }
      return ciImageApplyingOrientation(from: uiImage)
    #elseif os(macOS)
      guard let nsImage = NSImage(contentsOfFile: path) else { return nil }
      return ciImage(fromNSImage: nsImage)
    #endif
  }

  private static func ciImage(fromData data: Data) -> CIImage? {
    #if os(iOS)
      guard let uiImage = UIImage(data: data) else { return nil }
      return ciImageApplyingOrientation(from: uiImage)
    #elseif os(macOS)
      guard let nsImage = NSImage(data: data) else { return nil }
      return ciImage(fromNSImage: nsImage)
    #endif
  }

  #if os(iOS)
    /// `CIImage(image:)` ignores `UIImage.imageOrientation`; apply EXIF upright pixels.
    private static func ciImageApplyingOrientation(from uiImage: UIImage) -> CIImage? {
      guard let base = CIImage(image: uiImage) else { return nil }
      guard uiImage.imageOrientation != .up else { return base }
      return base.oriented(forExifOrientation: exifOrientation(uiImage.imageOrientation))
    }

    private static func exifOrientation(_ orientation: UIImage.Orientation) -> Int32 {
      switch orientation {
      case .up: return 1
      case .down: return 3
      case .left: return 8
      case .right: return 6
      case .upMirrored: return 2
      case .downMirrored: return 4
      case .leftMirrored: return 5
      case .rightMirrored: return 7
      @unknown default: return 1
      }
    }
  #endif

  #if os(macOS)
    private static func ciImage(fromNSImage image: NSImage) -> CIImage? {
      var rect = CGRect(origin: .zero, size: image.size)
      guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
        return nil
      }
      return CIImage(cgImage: cgImage)
    }
  #endif

  private func scaledReplacementBackground(extent: CGRect) -> CIImage? {
    configLock.lock()
    if extent == cachedReplacementExtent, let cached = cachedScaledReplacement {
      configLock.unlock()
      return cached
    }
    let source = replacementBackgroundImage
    configLock.unlock()
    guard let source else { return nil }
    let srcExtent = source.extent
    guard srcExtent.width >= 1, srcExtent.height >= 1 else { return nil }
    let scale = max(extent.width / srcExtent.width, extent.height / srcExtent.height)
    let scaled = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let scaledExtent = scaled.extent
    let tx = extent.midX - scaledExtent.midX
    let ty = extent.midY - scaledExtent.midY
    let result =
      scaled
      .transformed(by: CGAffineTransform(translationX: tx, y: ty))
      .cropped(to: extent)
    configLock.lock()
    cachedReplacementExtent = extent
    cachedScaledReplacement = result
    configLock.unlock()
    return result
  }

  /// Blurred camera plate when no replacement image is set.
  private func makeBlurredBackgroundPlate(
    from input: CIImage,
    extent: CGRect,
    blurSigma: CGFloat
  ) -> CIImage {
    let ds = Self.backgroundBlurDownsample
    // Single pass at low res — scale σ so upscaled blur still blocks background detail.
    let downSigma = blurSigma * ds * 1.35
    var plate = input
    for _ in 0..<Self.backgroundBlurPasses {
      plate =
        plate
        .clampedToExtent()
        .transformed(by: CGAffineTransform(scaleX: ds, y: ds))
        .applyingGaussianBlur(sigma: downSigma)
        .transformed(by: CGAffineTransform(scaleX: 1.0 / ds, y: 1.0 / ds))
        .cropped(to: extent)
    }
    if Self.backgroundDesaturation > 0,
      let controls = CIFilter(name: "CIColorControls")
    {
      controls.setValue(plate, forKey: kCIInputImageKey)
      controls.setValue(1.0 - Self.backgroundDesaturation, forKey: kCIInputSaturationKey)
      plate = controls.outputImage?.cropped(to: extent) ?? plate
    }
    return plate
  }

  private func applyObscureVeil(
    to background: CIImage,
    extent: CGRect,
    opacity: CGFloat
  ) -> CIImage {
    guard opacity > 0,
      let overlay = CIFilter(name: "CISourceOverCompositing"),
      let gray = CIFilter(name: "CIConstantColorGenerator")
    else {
      return background
    }
    gray.setValue(
      CIColor(red: 0.45, green: 0.45, blue: 0.48, alpha: opacity),
      forKey: kCIInputColorKey
    )
    guard let veil = gray.outputImage?.cropped(to: extent) else {
      return background
    }
    overlay.setValue(veil, forKey: kCIInputImageKey)
    overlay.setValue(background, forKey: kCIInputBackgroundImageKey)
    return overlay.outputImage?.cropped(to: extent) ?? background
  }
}

#if os(iOS)
  extension MeetBackgroundBlurMediaPipeEngine: ImageSegmenterLiveStreamDelegate {
    public func imageSegmenter(
      _ imageSegmenter: ImageSegmenter,
      didFinishSegmentation result: ImageSegmenterResult?,
      timestampInMilliseconds: Int,
      error: Error?
    ) {
      maskLock.lock()
      let stale = inFlightGeneration != segmentationGeneration
      let capturedAtNs = inFlightFrameCapturedAtNs
      maskLock.unlock()
      if stale {
        clearInferenceInFlight()
        return
      }

      var newSnapshot: MaskSnapshot?
      if error == nil,
        let result,
        let mask = result.confidenceMasks?.first
      {
        let readbackStartNs = Self.nowNs()
        newSnapshot = makeFloatMaskSnapshot(from: mask, capturedAtNs: capturedAtNs)
        recordInference(
          ns: Self.nowNs() &- capturedAtNs,
          readbackNs: Self.nowNs() &- readbackStartNs
        )
      }

      maskLock.lock()
      if inFlightGeneration == segmentationGeneration, let snapshot = newSnapshot {
        storeMaskIfNewerLocked(snapshot)
      }
      inferenceInFlight = false
      maskLock.unlock()
    }
  }
#endif
