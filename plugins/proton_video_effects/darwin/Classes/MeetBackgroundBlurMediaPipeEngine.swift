/*
 * Copyright (c) 2026 Proton AG
 * Apple platforms: iOS uses MediaPipe Tasks; macOS uses Vision person segmentation.
 * Both share the same Core Image background-blur compositor.
 */

import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Metal
#if os(iOS)
import MediaPipeTasksVision
#elseif os(macOS)
import Vision
#endif

@objc(MeetBackgroundBlurMediaPipeEngine)
public final class MeetBackgroundBlurMediaPipeEngine: NSObject {
  @objc public static var isReady: Bool {
#if os(iOS)
    return modelPath(named: multiclassModelName) != nil
      || modelPath(named: singleClassModelName) != nil
#elseif os(macOS)
    if #available(macOS 12.0, *) {
      return true
    }
    return false
#endif
  }

  private static let multiclassModelName = "selfie_multiclass_256x256"
  private static let singleClassModelName = "selfie_segmenter"
  private static let segmenterInputSize: Int = 256
  private static let backgroundBlurDownsample: CGFloat = 0.25
  private static let backgroundBlurSigma: CGFloat = 24.0
  private static let maskFeatherSigma: CGFloat = 1.5

  private struct MaskSnapshot {
    let image: CIImage
    let data: Data
  }

  private let ciContext: CIContext = MeetBackgroundBlurMediaPipeEngine.makeCIContext()

#if os(iOS)
  private var segmenter: ImageSegmenter?
  private var isMulticlassModel = false
  private var segmentClockMs: Int = 0
#elseif os(macOS)
  private var visionQueue = DispatchQueue(label: "meet.bgblur.vision", qos: .userInitiated)
#endif

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
    setupSegmenter()
  }

  private func setupSegmenter() {
#if os(iOS)
    let multiclassPath = Self.modelPath(named: Self.multiclassModelName)
    let singleClassPath = Self.modelPath(named: Self.singleClassModelName)
    guard let path = multiclassPath ?? singleClassPath else {
      segmenter = nil
      return
    }
    isMulticlassModel = (path == multiclassPath)

    let options = ImageSegmenterOptions()
    options.runningMode = .liveStream
    options.imageSegmenterLiveStreamDelegate = self
    options.shouldOutputCategoryMask = false
    options.shouldOutputConfidenceMasks = true
    options.baseOptions.modelAssetPath = path
#if targetEnvironment(simulator)
    options.baseOptions.delegate = .CPU
#else
    options.baseOptions.delegate = .GPU
#endif
    do {
      segmenter = try ImageSegmenter(options: options)
    } catch {
      segmenter = nil
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

  private func ensureBGRAScratch() -> CVPixelBuffer? {
    if let buf = bgraScratch { return buf }
    var out: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferCGImageCompatibilityKey as String: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    let st = CVPixelBufferCreate(
      kCFAllocatorDefault,
      Self.segmenterInputSize,
      Self.segmenterInputSize,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &out)
    guard st == kCVReturnSuccess, let buf = out else { return nil }
    bgraScratch = buf
    return buf
  }

#if os(iOS)
  private func workingBGRABuffer(from source: CVPixelBuffer) -> CVPixelBuffer? {
    let w = CVPixelBufferGetWidth(source)
    let h = CVPixelBufferGetHeight(source)
    guard w > 0, h > 0 else { return nil }
    guard let dst = ensureBGRAScratch() else { return nil }
    let target = CGFloat(Self.segmenterInputSize)
    let scaleX = target / CGFloat(w)
    let scaleY = target / CGFloat(h)
    let image = CIImage(cvPixelBuffer: source)
      .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
    let bounds = CGRect(x: 0, y: 0, width: target, height: target)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    ciContext.render(image, to: dst, bounds: bounds, colorSpace: cs)
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
    data.withUnsafeMutableBytes { raw in
      guard let dst = raw.baseAddress else { return }
      memcpy(dst, src, byteCount)
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

#if os(macOS)
  @available(macOS 12.0, *)
  private func makeMaskSnapshot(from pixelBuffer: CVPixelBuffer) -> MaskSnapshot? {
    let image = CIImage(cvPixelBuffer: pixelBuffer)
    let extent = image.extent
    guard extent.width >= 1, extent.height >= 1 else { return nil }
    let w = Int(extent.width)
    let h = Int(extent.height)
    let rowBytes = w * 4
    let byteCount = rowBytes * h
    var data = Data(count: byteCount)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    data.withUnsafeMutableBytes { raw in
      guard let base = raw.baseAddress else { return }
      ciContext.render(
        image,
        toBitmap: base,
        rowBytes: rowBytes,
        bounds: extent,
        format: .BGRA8,
        colorSpace: cs)
    }
    let grayCs = CGColorSpace(name: CGColorSpace.linearGray)!
    var grayData = Data(count: w * h)
    grayData.withUnsafeMutableBytes { grayRaw in
      guard let grayBase = grayRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
      data.withUnsafeBytes { bgraRaw in
        guard let bgra = bgraRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        for y in 0..<h {
          for x in 0..<w {
            let i = y * rowBytes + x * 4
            grayBase[y * w + x] = bgra[i]
          }
        }
      }
    }
    let grayImage = CIImage(
      bitmapData: grayData,
      bytesPerRow: w,
      size: CGSize(width: CGFloat(w), height: CGFloat(h)),
      format: .L8,
      colorSpace: grayCs)
    return MaskSnapshot(image: grayImage, data: grayData)
  }
#endif

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
    let feathered = maskImage
      .clampedToExtent()
      .applyingGaussianBlur(sigma: Self.maskFeatherSigma)
      .cropped(to: mre)
      .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
      .cropped(to: ire)

    let ds = Self.backgroundBlurDownsample
    let downSigma: CGFloat = Self.backgroundBlurSigma * ds
    let blurredBackground = input
      .clampedToExtent()
      .transformed(by: CGAffineTransform(scaleX: ds, y: ds))
      .applyingGaussianBlur(sigma: downSigma)
      .transformed(by: CGAffineTransform(scaleX: 1.0 / ds, y: 1.0 / ds))
      .cropped(to: ire)

    guard let blend = CIFilter(name: "CIBlendWithMask") else { return }
#if os(iOS)
    if isMulticlassModel {
      blend.setValue(blurredBackground, forKey: kCIInputImageKey)
      blend.setValue(input, forKey: kCIInputBackgroundImageKey)
    } else {
      blend.setValue(input, forKey: kCIInputImageKey)
      blend.setValue(blurredBackground, forKey: kCIInputBackgroundImageKey)
    }
#elseif os(macOS)
    // Vision person mask: high = person → sharp foreground on input image.
    blend.setValue(input, forKey: kCIInputImageKey)
    blend.setValue(blurredBackground, forKey: kCIInputBackgroundImageKey)
#endif
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
#if os(iOS)
    guard let segmenter else {
      clearInferenceInFlight()
      return
    }
    guard let work = workingBGRABuffer(from: pixelBuffer) else {
      clearInferenceInFlight()
      return
    }
    let mpImage: MPImage
    do {
      mpImage = try MPImage(pixelBuffer: work, orientation: .up)
    } catch {
      clearInferenceInFlight()
      return
    }
    segmentClockMs += 33
    do {
      try segmenter.segmentAsync(image: mpImage, timestampInMilliseconds: segmentClockMs)
    } catch {
      clearInferenceInFlight()
    }
#elseif os(macOS)
    if #available(macOS 12.0, *) {
      dispatchVisionSegmentation(on: pixelBuffer)
    } else {
      clearInferenceInFlight()
    }
#endif
  }

#if os(macOS)
  @available(macOS 12.0, *)
  private func dispatchVisionSegmentation(on pixelBuffer: CVPixelBuffer) {
    visionQueue.async { [weak self] in
      guard let self else { return }
      let request = VNGeneratePersonSegmentationRequest()
      request.qualityLevel = .balanced
      request.outputPixelFormat = kCVPixelFormatType_OneComponent8
      let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
      do {
        try handler.perform([request])
        var newSnapshot: MaskSnapshot?
        if let observation = request.results?.first as? VNPixelBufferObservation {
          newSnapshot = self.makeMaskSnapshot(from: observation.pixelBuffer)
        }
        self.maskLock.lock()
        if let snapshot = newSnapshot {
          self.currentMask = snapshot
        }
        self.inferenceInFlight = false
        self.maskLock.unlock()
      } catch {
        self.clearInferenceInFlight()
      }
    }
  }
#endif

  private func clearInferenceInFlight() {
    maskLock.lock()
    inferenceInFlight = false
    maskLock.unlock()
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
    var newSnapshot: MaskSnapshot?
    if error == nil,
       let result,
       let mask = result.confidenceMasks?.first
    {
      newSnapshot = makeFloatMaskSnapshot(from: mask)
    }

    maskLock.lock()
    if let snapshot = newSnapshot {
      currentMask = snapshot
    }
    inferenceInFlight = false
    maskLock.unlock()
  }
}
#endif
