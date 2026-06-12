import flutter_webrtc

/// RNNoise capture processor — in-place on WebRTC [RTCAudioBuffer] (48 kHz mono frames).
@objc final class RnnoiseProcessor: NSObject, ExternalAudioProcessingDelegate {
  private(set) var isEnabled = false
  private var handle: OpaquePointer?
  private var frameSize: Int

  override init() {
    frameSize = Int(proton_rnnoise_get_frame_size())
    super.init()
    handle = proton_rnnoise_create()
  }

  deinit {
    if let handle {
      proton_rnnoise_destroy(handle)
    }
  }

  func enable() {
    if handle == nil {
      handle = proton_rnnoise_create()
    }
    if let handle {
      proton_rnnoise_set_enabled(handle, 1)
    }
    isEnabled = true
  }

  func disable() {
    if let handle {
      proton_rnnoise_set_enabled(handle, 0)
    }
    isEnabled = false
  }

  private func processAudioBuffer(_ audioBuffer: RTCAudioBuffer) {
    guard isEnabled, let handle, frameSize > 0 else {
      return
    }

    let channels = audioBuffer.channels
    let frames = audioBuffer.frames
    guard channels > 0, frames > 0 else {
      return
    }

    for ch in 0..<channels {
      let channelBuffer = audioBuffer.rawBuffer(forChannel: ch)
      var offset = 0
      while offset + frameSize <= frames {
        _ = proton_rnnoise_process_interleaved(
          handle,
          channelBuffer.advanced(by: offset),
          frameSize,
          1
        )
        offset += frameSize  // RNNoise fixed 480-sample hop at 48 kHz
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
    disable()
  }

  static var isNativeReady: Bool {
    guard let probe = proton_rnnoise_create() else {
      return false
    }
    let frameSize = Int(proton_rnnoise_get_frame_size())
    proton_rnnoise_destroy(probe)
    return frameSize > 0
  }
}
