import AVFoundation
import CoreVideo
import Foundation
import WebRTC

protocol PipSampleBufferRendererDelegate: AnyObject {
  func pipSampleBufferRendererDidEnqueueFrame(_ renderer: PipSampleBufferRenderer)
  func pipSampleBufferRendererDidReset(_ renderer: PipSampleBufferRenderer)
}

/// Feeds WebRTC frames into `AVSampleBufferDisplayLayer` so PiP keeps updating while the app is backgrounded.
/// `RTCMTLVideoView` stops compositing in the background and shows a frozen frame.
final class PipSampleBufferRenderer: NSObject, RTCVideoRenderer {

  let displayLayer: AVSampleBufferDisplayLayer
  weak var delegate: PipSampleBufferRendererDelegate?

  private let displayQueue = DispatchQueue(
    label: "me.proton.meet.pip.sample-buffer", qos: .userInteractive)
  private var lastPresentationTime = CMTime.invalid

  init(displayLayer: AVSampleBufferDisplayLayer) {
    self.displayLayer = displayLayer
    super.init()
  }

  func reset() {
    displayQueue.sync {
      lastPresentationTime = .invalid
    }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if self.displayLayer.status == .failed {
        self.displayLayer.flush()
      }
      self.delegate?.pipSampleBufferRendererDidReset(self)
    }
  }

  func setSize(_ size: CGSize) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.displayLayer.frame = CGRect(origin: .zero, size: size)
    }
  }

  func renderFrame(_ frame: RTCVideoFrame?) {
    guard let frame else { return }
    guard let pixelBuffer = Self.pixelBuffer(from: frame) else { return }
    guard
      let sampleBuffer = Self.makeSampleBuffer(
        from: pixelBuffer,
        timeStampNs: frame.timeStampNs,
        lastPresentationTime: &lastPresentationTime
      )
    else { return }

    displayQueue.async { [weak self] in
      guard let self else { return }
      DispatchQueue.main.async {
        if self.displayLayer.status == .failed {
          self.displayLayer.flush()
        }
        self.displayLayer.enqueue(sampleBuffer)
        self.delegate?.pipSampleBufferRendererDidEnqueueFrame(self)
      }
    }
  }

  private static func pixelBuffer(from frame: RTCVideoFrame) -> CVPixelBuffer? {
    if let cvBuffer = frame.buffer as? RTCCVPixelBuffer {
      return cvBuffer.pixelBuffer
    }

    let i420 = frame.buffer.toI420()
    return pixelBuffer(fromI420: i420)
  }

  private static func pixelBuffer(fromI420 i420: RTCI420BufferProtocol) -> CVPixelBuffer? {
    let width = Int(i420.width)
    let height = Int(i420.height)

    var pixelBuffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      attrs as CFDictionary,
      &pixelBuffer
    )
    guard status == kCVReturnSuccess, let pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

    guard
      let yDstBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
      let uvDstBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
    else { return nil }

    let yDstStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
    let uvDstStride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
    let ySrcStride = Int(i420.strideY)
    let uSrcStride = Int(i420.strideU)
    let vSrcStride = Int(i420.strideV)

    let yWidth = width
    let uvWidth = width / 2
    let uvHeight = height / 2

    let srcY = i420.dataY
    let srcU = i420.dataU
    let srcV = i420.dataV

    for row in 0..<height {
      let srcRow = srcY.advanced(by: row * ySrcStride)
      let dstRow = yDstBase.advanced(by: row * yDstStride)
      memcpy(dstRow, srcRow, yWidth)
    }

    for row in 0..<uvHeight {
      let srcURow = srcU.advanced(by: row * uSrcStride)
      let srcVRow = srcV.advanced(by: row * vSrcStride)
      let dstUVRow = uvDstBase.advanced(by: row * uvDstStride).assumingMemoryBound(to: UInt8.self)
      for col in 0..<uvWidth {
        dstUVRow[col * 2] = srcURow[col]
        dstUVRow[col * 2 + 1] = srcVRow[col]
      }
    }

    return pixelBuffer
  }

  private static func makeSampleBuffer(
    from pixelBuffer: CVPixelBuffer,
    timeStampNs: Int64,
    lastPresentationTime: inout CMTime
  ) -> CMSampleBuffer? {
    var formatDescription: CMFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDescription
    )
    guard formatStatus == noErr, let formatDescription else { return nil }

    var pts = CMTime(value: timeStampNs, timescale: 1_000_000_000)
    if lastPresentationTime.isValid && CMTimeCompare(pts, lastPresentationTime) <= 0 {
      pts = CMTimeAdd(lastPresentationTime, CMTime(value: 1, timescale: 30))
    }
    lastPresentationTime = pts

    var timing = CMSampleTimingInfo(
      duration: CMTime.invalid,
      presentationTimeStamp: pts,
      decodeTimeStamp: CMTime.invalid
    )

    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: formatDescription,
      sampleTiming: &timing,
      sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr else { return nil }
    return sampleBuffer
  }
}
