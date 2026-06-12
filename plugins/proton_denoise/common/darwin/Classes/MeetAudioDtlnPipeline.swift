import Foundation

// MARK: - Tail suppressor (co-located so CocoaPods always compiles it)

struct MeetAudioTailSuppressorState {
  var levelEnvelope: Float = 0
  var tailLowpass: Float = 0

  mutating func reset() {
    levelEnvelope = 0
    tailLowpass = 0
  }
}

struct MeetAudioTailSuppressorConfig {
  let openLevel: Float
  let minGain: Float
  let speechReleaseSec: Double
  let tailReleaseSec: Double
  let tailLowpassBlend: Float
  let lowpassGainThreshold: Float

  static let dtln16k = MeetAudioTailSuppressorConfig(
    openLevel: 0.006,
    minGain: 0.02,
    speechReleaseSec: 0.038,
    tailReleaseSec: 0.01,
    tailLowpassBlend: 0.45,
    lowpassGainThreshold: 0.94
  )

  static let dtlnPostUpsample = MeetAudioTailSuppressorConfig(
    openLevel: 0.0045,
    minGain: 0.07,
    speechReleaseSec: 0.035,
    tailReleaseSec: 0.008,
    tailLowpassBlend: 0.38,
    lowpassGainThreshold: 0.9
  )
}

/// Soft downward expander — attenuates low-level musical / electrical tails after words.
enum MeetAudioTailSuppressor {
  static func apply(
    samples: inout [Float],
    sampleRateHz: Int,
    state: inout MeetAudioTailSuppressorState,
    config: MeetAudioTailSuppressorConfig
  ) {
    guard !samples.isEmpty, sampleRateHz > 0 else {
      return
    }
    let releaseSpeech = releaseCoeff(seconds: config.speechReleaseSec, sampleRateHz: sampleRateHz)
    let releaseTail = releaseCoeff(seconds: config.tailReleaseSec, sampleRateHz: sampleRateHz)
    var envelope = state.levelEnvelope
    var lowpass = state.tailLowpass

    for i in samples.indices {
      let magnitude = abs(samples[i])
      if magnitude > envelope {
        envelope = 0.1 * magnitude + 0.9 * envelope
      } else {
        let release = envelope < config.openLevel ? releaseTail : releaseSpeech
        envelope = release * envelope + (1 - release) * magnitude
      }

      var gain: Float = 1
      if envelope < config.openLevel {
        let ratio = min(max(envelope / config.openLevel, 0), 1)
        gain = config.minGain + (1 - config.minGain) * ratio * ratio * ratio
      }

      var sample = samples[i] * gain
      if gain < config.lowpassGainThreshold {
        lowpass = (1 - config.tailLowpassBlend) * lowpass + config.tailLowpassBlend * sample
        sample = lowpass
      } else {
        lowpass = sample
      }
      samples[i] = sample
    }

    state.levelEnvelope = envelope
    state.tailLowpass = lowpass
  }

  private static func releaseCoeff(seconds: Double, sampleRateHz: Int) -> Float {
    Float(exp(-1.0 / (seconds * Double(sampleRateHz))))
  }
}

// MARK: - DTLN pipeline

/// Streaming state for 16 kHz mono blocks (DTLN hop = 128 samples).
struct MeetAudioDtlnStreamState {
  var pending16k: [Float] = []
  var ready16k: [Float] = []
  var rateConverter = MeetAudioDtlnRateConverter()
  var tail16k = MeetAudioTailSuppressorState()
  var tailPostUpsample = MeetAudioTailSuppressorState()

  mutating func reset() {
    pending16k.removeAll(keepingCapacity: false)
    ready16k.removeAll(keepingCapacity: false)
    rateConverter.reset()
    tail16k.reset()
    tailPostUpsample.reset()
  }
}

/// dtln-rs processing shared by live capture (mirrors Android [MeetAudioDtlnPipeline]).
enum MeetAudioDtlnPipeline {
  static let internalSampleRateHz = MeetAudioPcm.dtlnSampleRateHz

  static func processInterleavedInPlace(
    handle: OpaquePointer?,
    sampleRateHz: Int,
    numChannels: Int,
    numFrames: Int,
    floats: inout [Float],
    streamState: inout MeetAudioDtlnStreamState
  ) {
    guard let handle, numFrames > 0, numChannels > 0 else {
      return
    }

    let mono = MeetAudioPcm.downmix(floats, channels: numChannels)
    let blockShift = max(ProtonDtlnRsNative.getBlockShift(), 128)
    // DTLN model is 16 kHz — resample capture before block-wise denoise.
    let at16k = streamState.rateConverter.downsample(
      mono,
      fromRate: sampleRateHz,
      toRate: internalSampleRateHz
    )

    // Feed real samples only — never zero-pad per WebRTC buffer (breaks overlap + adds noise).
    streamState.pending16k.append(contentsOf: at16k)
    while streamState.pending16k.count >= blockShift {
      var block = Array(streamState.pending16k.prefix(blockShift))
      streamState.pending16k.removeFirst(blockShift)
      guard ProtonDtlnRsNative.denoiseInterleaved(handle, &block) else {
        return
      }
      streamState.ready16k.append(contentsOf: block)
    }

    var out16k: [Float]
    if streamState.ready16k.count >= at16k.count {
      out16k = Array(streamState.ready16k.prefix(at16k.count))
      streamState.ready16k.removeFirst(at16k.count)
    } else {
      // Pipeline priming (~8 ms): blend available denoised samples with dry tail.
      let denoisedCount = streamState.ready16k.count
      var blended = streamState.ready16k
      if denoisedCount < at16k.count {
        blended.append(contentsOf: at16k[denoisedCount..<at16k.count])
      }
      out16k = blended
      streamState.ready16k.removeAll(keepingCapacity: true)
    }

    MeetAudioTailSuppressor.apply(
      samples: &out16k,
      sampleRateHz: internalSampleRateHz,
      state: &streamState.tail16k,
      config: .dtln16k
    )

    // 100% denoised — do not blend with dry capture here. DTLN + resamplers add
    // ~8–15 ms latency; mixing with undelayed dry causes a light echo/shadow.
    var denoisedAtRate = streamState.rateConverter.upsample(
      out16k,
      fromRate: internalSampleRateHz,
      toRate: sampleRateHz
    )
    MeetAudioTailSuppressor.apply(
      samples: &denoisedAtRate,
      sampleRateHz: sampleRateHz,
      state: &streamState.tailPostUpsample,
      config: .dtlnPostUpsample
    )
    let outInterleaved = MeetAudioPcm.upmixToChannels(
      denoisedAtRate,
      channels: numChannels,
      frames: numFrames
    )

    let copyCount = min(outInterleaved.count, floats.count)
    if copyCount > 0 {
      floats.replaceSubrange(0..<copyCount, with: outInterleaved[0..<copyCount])
    }
  }

}

// MARK: - Band-limited 48 kHz ↔ 16 kHz (co-located so CocoaPods always compiles it)

private enum MeetAudioFirResampler {
  static let taps = 45
  static let factor = 3

  static let decimateKernel: [Float] = buildLowpassKernel(gain: 1)
  static let interpolatePhases: [[Float]] = buildInterpolatePhases()

  static func createDecimator() -> FirDecimateBy3 {
    FirDecimateBy3(kernel: decimateKernel)
  }

  static func createInterpolator() -> FirInterpolateBy3 {
    FirInterpolateBy3(phases: interpolatePhases)
  }

  private static func buildLowpassKernel(gain: Float) -> [Float] {
    // Just under 16 kHz Nyquist; slightly higher than 7 kHz for less muffled speech.
    let cutoffHz = 7_600.0
    let sampleRateHz = Double(MeetAudioPcm.webrtcCaptureSampleRateHz)
    let fc = cutoffHz / sampleRateHz
    let mid = Double(taps - 1) / 2.0
    var raw = [Double](repeating: 0, count: taps)
    for n in 0..<taps {
      let x = Double(n) - mid
      let sinc: Double
      if abs(x) < 1e-9 {
        sinc = 2.0 * Double.pi * fc
      } else {
        sinc = sin(2.0 * Double.pi * fc * x) / x
      }
      let window = 0.54 - 0.46 * cos(2.0 * Double.pi * Double(n) / Double(taps - 1))
      raw[n] = sinc * window
    }
    let sum = max(raw.reduce(0, +), 1e-6)
    return raw.map { Float($0 / sum) * gain }
  }

  private static func buildInterpolatePhases() -> [[Float]] {
    let kernel = buildLowpassKernel(gain: Float(factor))
    let phaseLen = taps / factor
    return (0..<factor).map { phase in
      (0..<phaseLen).map { tap in kernel[tap * factor + phase] }
    }
  }
}

fileprivate final class FirDecimateBy3 {
  private let kernel: [Float]
  private var window: [Float]
  private var windowFill = 0
  private var samplesSinceOutput = 0

  init(kernel: [Float]) {
    self.kernel = kernel
    window = [Float](repeating: 0, count: kernel.count)
  }

  func reset() {
    window = [Float](repeating: 0, count: kernel.count)
    windowFill = 0
    samplesSinceOutput = 0
  }

  func process(_ input: [Float]) -> [Float] {
    if input.isEmpty {
      return []
    }
    var out = [Float]()
    out.reserveCapacity(input.count / MeetAudioFirResampler.factor + 1)
    for sample in input {
      if windowFill < kernel.count {
        window[windowFill] = sample
        windowFill += 1
        if windowFill == kernel.count {
          samplesSinceOutput = 0
          out.append(convolve(window))
          samplesSinceOutput = 1
        }
        continue
      }
      window.removeFirst()
      window.append(sample)
      samplesSinceOutput += 1
      if samplesSinceOutput >= MeetAudioFirResampler.factor {
        out.append(convolve(window))
        samplesSinceOutput = 0
      }
    }
    return out
  }

  private func convolve(_ samples: [Float]) -> Float {
    var sum: Float = 0
    for i in kernel.indices {
      sum += samples[i] * kernel[i]
    }
    return sum
  }
}

fileprivate final class FirInterpolateBy3 {
  private let phases: [[Float]]
  private var history: [Float]
  private var historyFill = 0

  init(phases: [[Float]]) {
    self.phases = phases
    history = [Float](repeating: 0, count: max(phases[0].count - 1, 0))
  }

  func reset() {
    history = [Float](repeating: 0, count: history.count)
    historyFill = 0
  }

  func process(_ input: [Float]) -> [Float] {
    if input.isEmpty {
      return []
    }
    var out = [Float]()
    out.reserveCapacity(input.count * MeetAudioFirResampler.factor)
    for sample in input {
      for phase in phases {
        out.append(convolvePhase(sample, phase))
      }
      pushHistory(sample)
    }
    return out
  }

  private func pushHistory(_ sample: Float) {
    if historyFill < history.count {
      history[historyFill] = sample
      historyFill += 1
      return
    }
    history.removeFirst()
    history.append(sample)
  }

  private func convolvePhase(_ sample: Float, _ phaseKernel: [Float]) -> Float {
    var sum: Float = 0
    for i in phaseKernel.indices {
      let rel = i - (phaseKernel.count - 1)
      let value: Float
      if rel < -historyFill {
        value = 0
      } else if rel < 0 {
        value = history[historyFill + rel]
      } else if rel == 0 {
        value = sample
      } else {
        value = 0
      }
      sum += value * phaseKernel[i]
    }
    return sum
  }
}

final class MeetAudioDtlnRateConverter {
  private var decimator: FirDecimateBy3?
  private var interpolator: FirInterpolateBy3?

  func downsample(_ mono: [Float], fromRate: Int, toRate: Int) -> [Float] {
    if fromRate == toRate || mono.isEmpty {
      return mono
    }
    if fromRate == MeetAudioPcm.webrtcCaptureSampleRateHz &&
      toRate == MeetAudioPcm.dtlnSampleRateHz
    {
      let d = decimator ?? MeetAudioFirResampler.createDecimator()
      decimator = d
      return d.process(mono)
    }
    return MeetAudioPcm.resample(mono, fromRate: fromRate, toRate: toRate)
  }

  func upsample(_ mono: [Float], fromRate: Int, toRate: Int) -> [Float] {
    if fromRate == toRate || mono.isEmpty {
      return mono
    }
    if fromRate == MeetAudioPcm.dtlnSampleRateHz &&
      toRate == MeetAudioPcm.webrtcCaptureSampleRateHz
    {
      let i = interpolator ?? MeetAudioFirResampler.createInterpolator()
      interpolator = i
      let upsampled = i.process(mono)
      return fitLength(
        upsampled,
        targetLen: expectedLength(inputLen: mono.count, fromRate: fromRate, toRate: toRate)
      )
    }
    return MeetAudioPcm.resample(mono, fromRate: fromRate, toRate: toRate)
  }

  func reset() {
    decimator?.reset()
    interpolator?.reset()
    decimator = nil
    interpolator = nil
  }

  private func expectedLength(inputLen: Int, fromRate: Int, toRate: Int) -> Int {
    max((inputLen * toRate) / fromRate, 1)
  }

  private func fitLength(_ samples: [Float], targetLen: Int) -> [Float] {
    if samples.count == targetLen {
      return samples
    }
    if samples.count > targetLen {
      return Array(samples.prefix(targetLen))
    }
    var out = samples
    let last = samples.last ?? 0
    out.append(contentsOf: [Float](repeating: last, count: targetLen - samples.count))
    return out
  }
}
