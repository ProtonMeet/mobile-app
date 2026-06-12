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
 * Blur tuning: setBlurConfig (σ, obscure opacity) from Dart [BackgroundBlurConfig].
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
  private static let maskFeatherSigma: CGFloat = 1.5
  /// Pushes uncertain mask values toward background so fans / furniture leak less.
  private static let maskForegroundGamma: CGFloat = 1.5
  /// Recover if Vision stalls (WebRTC capture thread stops dispatching when stuck).
  private static let visionInferenceTimeoutMs: Int = 750
  /// Desaturate the blurred plate so colored objects are harder to recognize.
  private static let backgroundDesaturation: CGFloat = 0.5

  private let configLock = NSLock()
  private var backgroundBlurSigma: CGFloat = defaultBackgroundBlurSigma
  private var backgroundObscureOpacity: CGFloat = 0.1
  private var replacementBackgroundImage: CIImage?
  private var cachedReplacementExtent: CGRect = .zero
  private var cachedScaledReplacement: CIImage?

  private struct MaskSnapshot {
    let image: CIImage
    let data: Data
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
  private var visionSegmentationRequest: VNGeneratePersonSegmentationRequest?
  /// Copy of the camera frame for async Vision — the WebRTC buffer is reused after onFrame returns.
  private var visionFrameScratch: CVPixelBuffer?

  private var bgraScratch: CVPixelBuffer?
  private let maskLock = NSLock()
  private var currentMask: MaskSnapshot?
  private var inferenceInFlight: Bool = false

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

  @objc
  public func setBlurConfig(blurSigma: CGFloat, backgroundObscureOpacity: CGFloat) {
    configLock.lock()
    backgroundBlurSigma = min(
      max(blurSigma, Self.minBackgroundBlurSigma),
      Self.maxBackgroundBlurSigma
    )
    self.backgroundObscureOpacity = min(max(backgroundObscureOpacity, 0.0), 1.0)
    configLock.unlock()
  }

  private func currentBlurConfig() -> (sigma: CGFloat, obscureOpacity: CGFloat) {
    configLock.lock()
    defer { configLock.unlock() }
    return (backgroundBlurSigma, backgroundObscureOpacity)
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

  private func ensureVisionFrameScratch(
    width: Int,
    height: Int,
    pixelFormat: OSType
  ) -> CVPixelBuffer? {
    if let buf = visionFrameScratch,
      CVPixelBufferGetWidth(buf) == width,
      CVPixelBufferGetHeight(buf) == height,
      CVPixelBufferGetPixelFormatType(buf) == pixelFormat
    {
      return buf
    }
    visionFrameScratch = nil
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
      pixelFormat,
      attrs as CFDictionary,
      &out)
    guard st == kCVReturnSuccess, let buf = out else { return nil }
    visionFrameScratch = buf
    return buf
  }

  /// Snapshot the live camera buffer before handing it to Vision on a background queue.
  private func copyForVisionInference(from source: CVPixelBuffer) -> CVPixelBuffer? {
    let w = CVPixelBufferGetWidth(source)
    let h = CVPixelBufferGetHeight(source)
    guard w > 0, h > 0 else { return nil }
    let fmt = CVPixelBufferGetPixelFormatType(source)
    guard let dst = ensureVisionFrameScratch(width: w, height: h, pixelFormat: fmt) else {
      return nil
    }
    let cs = outputColorSpace(forPixelFormat: fmt)
    let image = CIImage(cvPixelBuffer: source)
    let bounds = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
    ciContext.render(image, to: dst, bounds: bounds, colorSpace: cs)
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

  private func makeFloatMaskSnapshot(from mask: Mask) -> MaskSnapshot? {
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
    return MaskSnapshot(image: image, data: data)
  }
#endif

  @available(iOS 15.0, macOS 12.0, *)
  private func makeVisionMaskSnapshot(from pixelBuffer: CVPixelBuffer) -> MaskSnapshot? {
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
    return MaskSnapshot(image: image, data: data)
  }

  @available(iOS 15.0, macOS 12.0, *)
  private func visionRequest() -> VNGeneratePersonSegmentationRequest {
    if let request = visionSegmentationRequest {
      return request
    }
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .balanced
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    visionSegmentationRequest = request
    return request
  }

  @objc
  public func applyPersonBackgroundBlur(to pixelBuffer: CVPixelBuffer, rotationDegrees: Int32) {
    _ = rotationDegrees

    maskLock.lock()
    let canDispatch = !inferenceInFlight
    if canDispatch {
      inferenceInFlight = true
    }
    let snapshot = currentMask
    maskLock.unlock()

    if canDispatch {
      dispatchAsyncSegmentation(on: pixelBuffer)
    }

    guard let snapshot else { return }
    composite(pixelBuffer: pixelBuffer, mask: snapshot)
  }

  private func composite(pixelBuffer: CVPixelBuffer, mask snapshot: MaskSnapshot) {
    let input = CIImage(cvPixelBuffer: pixelBuffer)
    let ire = input.extent
    guard ire.width >= 1, ire.height >= 1 else { return }

    let maskImage = snapshot.image
    let mre = maskImage.extent
    guard mre.width >= 1, mre.height >= 1 else { return }

    let scaleX = ire.width / mre.width
    let scaleY = ire.height / mre.height
    let hardenedMask = hardenForegroundMask(maskImage)
    let feathered = hardenedMask
      .clampedToExtent()
      .applyingGaussianBlur(sigma: Self.maskFeatherSigma)
      .cropped(to: mre)
      .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
      .cropped(to: ire)

    let (blurSigma, obscureOpacity) = currentBlurConfig()
    let backgroundPlate: CIImage
    if let replacement = scaledReplacementBackground(extent: ire) {
      backgroundPlate = replacement
    } else {
      var blurredBackground = makeBlurredBackgroundPlate(
        from: input,
        extent: ire,
        blurSigma: blurSigma
      )
      backgroundPlate = applyObscureVeil(
        to: blurredBackground,
        extent: ire,
        opacity: obscureOpacity
      )
    }

    guard let blend = CIFilter(name: "CIBlendWithMask") else { return }
    // Mask is always foreground (person) confidence — same as Android after inversion.
    blend.setValue(input, forKey: kCIInputImageKey)
    blend.setValue(backgroundPlate, forKey: kCIInputBackgroundImageKey)
    blend.setValue(feathered, forKey: kCIInputMaskImageKey)
    guard var out = blend.outputImage else { return }
    out = out.cropped(to: ire)

    let dstFmt = CVPixelBufferGetPixelFormatType(pixelBuffer)
    let outCS = outputColorSpace(forPixelFormat: dstFmt)

    let lock = CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    guard lock == kCVReturnSuccess else { return }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0)) }

    ciContext.render(out, to: pixelBuffer, bounds: ire, colorSpace: outCS)
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

  @available(iOS 15.0, macOS 12.0, *)
  private func dispatchVisionSegmentation(on pixelBuffer: CVPixelBuffer) {
    // Copy on the capture thread: WebRTC recycles `pixelBuffer` once onFrame returns.
    guard let inferenceBuffer = copyForVisionInference(from: pixelBuffer) else {
      clearInferenceInFlight()
      return
    }

    let generation = segmentationGeneration
    let watchdog = DispatchWorkItem { [weak self] in
      self?.clearInferenceInFlight()
    }
    visionQueue.asyncAfter(
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
        try handler.perform([request])
        var newSnapshot: MaskSnapshot?
        if let observation = request.results?.first as? VNPixelBufferObservation {
          newSnapshot = self.makeVisionMaskSnapshot(from: observation.pixelBuffer)
        }
        self.maskLock.lock()
        if generation == self.segmentationGeneration, let snapshot = newSnapshot {
          self.currentMask = snapshot
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

  /// Shrinks soft foreground confidence so background blur covers more of the frame.
  private func hardenForegroundMask(_ mask: CIImage) -> CIImage {
    guard Self.maskForegroundGamma > 1.0 else { return mask }
    return mask.applyingFilter(
      "CIGammaAdjust",
      parameters: ["inputPower": Self.maskForegroundGamma]
    )
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
    let result = scaled
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
      plate = plate
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
      newSnapshot = makeFloatMaskSnapshot(from: mask)
    }

    maskLock.lock()
    if inFlightGeneration == segmentationGeneration, let snapshot = newSnapshot {
      currentMask = snapshot
    }
    inferenceInFlight = false
    maskLock.unlock()
  }
}
#endif
