import flutter_webrtc

/// DeepFilter capture processor stub (pass-through until native model is linked).
@objc final class DeepFilterProcessor: NSObject, ExternalAudioProcessingDelegate {
  private(set) var isEnabled = false

  func enable() {
    isEnabled = true
  }

  func disable() {
    isEnabled = false
  }

  // MARK: - ExternalAudioProcessingDelegate

  func audioProcessingInitialize(withSampleRate sampleRateHz: Int, channels: Int) {
    _ = sampleRateHz
    _ = channels
  }

  func audioProcessingProcess(_ audioBuffer: RTCAudioBuffer) {
    _ = audioBuffer
  }

  func audioProcessingRelease() {
    disable()
  }
}
