import flutter_webrtc

/// DeepFilterNet capture processor — session queue matches Android [ProtonDeepFilterNative].
@objc final class DeepFilterProcessor: NSObject, ExternalAudioProcessingDelegate {
  private let modelResourceName: String
  private let stateLock = NSLock()
  private(set) var isEnabled = false
  private var handle: OpaquePointer?
  private var frameSize: Int = 0
  private var scratchBuffer: [Float] = []

  @objc init(modelResourceName: String) {
    self.modelResourceName = modelResourceName
    super.init()
  }

  deinit {
    ProtonDeepFilterNative.sessionQueue.sync {
      tearDownOnSessionQueue()
    }
  }

  func enable() {
    isEnabled = true
  }

  func disable() {
    isEnabled = false
  }

  static func isNativeReady(modelResourceName: String) -> Bool {
    ProtonDeepFilterNative.isBundled(modelResourceName: modelResourceName)
  }

  /// Debug-only: same df_create path as in-call [warmUp], synchronously on [sessionQueue].
  /// Avoids main-queue deadlock when invoked from the Flutter method channel thread.
  static func debugWarmUpProbe(modelResourceName: String) -> [String: Any] {
    let start = CFAbsoluteTimeGetCurrent()
    let processor = DeepFilterProcessor(modelResourceName: modelResourceName)
    var warmUpOk = false
    var frameSize = 0
    ProtonDeepFilterNative.sessionQueue.sync {
      warmUpOk = processor.warmUpOnSessionQueue()
      if warmUpOk {
        processor.stateLock.lock()
        frameSize = processor.frameSize
        processor.stateLock.unlock()
      }
      processor.tearDownOnSessionQueue()
    }
    let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    return [
      "warmUpOk": warmUpOk,
      "warmUpMs": ms,
      "frameSize": frameSize,
    ]
  }

  static func warmUp(
    _ processor: DeepFilterProcessor,
    completion: @escaping (Bool) -> Void
  ) {
    ProtonDeepFilterNative.sessionQueue.async {
      let ready = processor.warmUpOnSessionQueue()
      DispatchQueue.main.async {
        completion(ready)
      }
    }
  }

  static func scheduleTeardown(_ processor: DeepFilterProcessor) {
    processor.disable()
    ProtonDeepFilterNative.sessionQueue.async {
      processor.tearDownOnSessionQueue()
    }
  }

  static func replace(
    old: DeepFilterProcessor?,
    new: DeepFilterProcessor,
    completion: @escaping (Bool) -> Void
  ) {
    ProtonDeepFilterNative.sessionQueue.async {
      old?.tearDownOnSessionQueue()
      let ready = new.warmUpOnSessionQueue()
      DispatchQueue.main.async {
        completion(ready)
      }
    }
  }

  @discardableResult
  private func warmUpOnSessionQueue() -> Bool {
    dispatchPrecondition(condition: .onQueue(ProtonDeepFilterNative.sessionQueue))
    stateLock.lock()
    if handle != nil {
      stateLock.unlock()
      return true
    }
    stateLock.unlock()

    guard ProtonDeepFilterNative.isBundled(modelResourceName: modelResourceName),
      let created = ProtonDeepFilterNative.createOnSessionQueue(modelResourceName: modelResourceName)
    else {
      return false
    }
    let createdFrameSize = ProtonDeepFilterNative.getFrameSizeOnSessionQueue(created)

    stateLock.lock()
    // Race: two warm-ups — keep first handle, destroy duplicate df_create.
    if handle == nil {
      handle = created
      frameSize = createdFrameSize
      scratchBuffer = [Float](repeating: 0, count: max(createdFrameSize, 1))
    } else {
      ProtonDeepFilterNative.destroyOnSessionQueue(created)
    }
    stateLock.unlock()
    stateLock.lock()
    let ready = handle != nil && frameSize > 0
    stateLock.unlock()
    return ready
  }

  private func tearDownOnSessionQueue() {
    dispatchPrecondition(condition: .onQueue(ProtonDeepFilterNative.sessionQueue))
    stateLock.lock()
    let toDestroy = handle
    handle = nil
    frameSize = 0
    scratchBuffer.removeAll(keepingCapacity: false)
    stateLock.unlock()

    if let toDestroy {
      ProtonDeepFilterNative.destroyOnSessionQueue(toDestroy)
    }
  }

  private func processAudioBuffer(_ audioBuffer: RTCAudioBuffer) {
    // Snapshot under lock — df_process runs on WebRTC thread, df_* lifecycle on sessionQueue.
    stateLock.lock()
    let processingEnabled = isEnabled
    let activeHandle = handle
    let activeFrameSize = frameSize
    stateLock.unlock()

    guard processingEnabled, let activeHandle, activeFrameSize > 0 else {
      return
    }

    let channels = audioBuffer.channels
    let frames = audioBuffer.frames
    guard channels > 0, frames > 0 else {
      return
    }

    var scratch = scratchBuffer
    for ch in 0..<channels {
      let channelBuffer = audioBuffer.rawBuffer(forChannel: ch)
      var offset = 0
      while offset + activeFrameSize <= frames {
        ProtonDeepFilterNative.processInterleaved(
          activeHandle,
          channelBuffer: channelBuffer,
          frameSize: activeFrameSize,
          offset: offset,
          scratch: &scratch
        )
        offset += activeFrameSize  // df expects fixed hop size per channel
      }
    }
  }

  // MARK: - ExternalAudioProcessingDelegate

  func audioProcessingInitialize(withSampleRate sampleRateHz: Int, channels: Int) {
    _ = sampleRateHz
    _ = channels
  }

  func audioProcessingProcess(_ audioBuffer: RTCAudioBuffer) {
    processAudioBuffer(audioBuffer)
  }

  func audioProcessingRelease() {
    DeepFilterProcessor.scheduleTeardown(self)
  }
}
