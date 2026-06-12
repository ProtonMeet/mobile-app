import flutter_webrtc

/// DTLN capture processor — resamples WebRTC 48 kHz PCM to 16 kHz for dtln-rs.
@objc final class DtlnRsProcessor: NSObject, ExternalAudioProcessingDelegate {
  private(set) var isEnabled = false
  private var handle: OpaquePointer?
  private var sampleRateHz = MeetAudioPcm.webrtcCaptureSampleRateHz
  private var numChannels = 1
  private var streamState = MeetAudioDtlnStreamState()

  deinit {
    releaseHandle()
  }

  func enable() {
    ensureHandle()
    isEnabled = true
  }

  func disable() {
    isEnabled = false
    streamState.reset()
  }

  static var isNativeReady: Bool {
    ProtonDtlnRsNative.isAvailable
  }

  private func ensureHandle() {
    if handle != nil || !ProtonDtlnRsNative.isAvailable {
      return
    }
    handle = ProtonDtlnRsNative.create()
  }

  private func releaseHandle() {
    if let handle {
      ProtonDtlnRsNative.destroy(handle)
      self.handle = nil
    }
  }

  private func processAudioBuffer(_ audioBuffer: RTCAudioBuffer) {
    guard isEnabled, let handle else {
      return
    }

    let channels = audioBuffer.channels
    let frames = audioBuffer.frames
    guard channels > 0, frames > 0 else {
      return
    }

    var interleaved = [Float](repeating: 0, count: frames * channels)
    // RTCAudioBuffer is planar — gather to interleaved for DTLN pipeline.
    for ch in 0..<channels {
      let channelBuffer = audioBuffer.rawBuffer(forChannel: ch)
      for frame in 0..<frames {
        interleaved[frame * channels + ch] = channelBuffer[frame]
      }
    }

    MeetAudioDtlnPipeline.processInterleavedInPlace(
      handle: handle,
      sampleRateHz: sampleRateHz,
      numChannels: channels,
      numFrames: frames,
      floats: &interleaved,
      streamState: &streamState
    )

    for ch in 0..<channels {
      let channelBuffer = audioBuffer.rawBuffer(forChannel: ch)
      for frame in 0..<frames {
        channelBuffer[frame] = interleaved[frame * channels + ch]  // scatter back to planar
      }
    }
  }

  // MARK: - ExternalAudioProcessingDelegate

  func audioProcessingInitialize(withSampleRate sampleRateHz: Int, channels: Int) {
    self.sampleRateHz = max(sampleRateHz, 1)
    self.numChannels = max(channels, 1)
    streamState.reset()
    ensureHandle()
  }

  func audioProcessingProcess(_ audioBuffer: RTCAudioBuffer) {
    processAudioBuffer(audioBuffer)
  }

  func audioProcessingRelease() {
    disable()
    releaseHandle()
  }
}
