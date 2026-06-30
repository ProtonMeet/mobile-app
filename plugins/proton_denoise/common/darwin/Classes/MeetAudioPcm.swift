import Foundation

/// Shared PCM helpers for capture processors (mirrors Android [MeetAudioPcm]).
enum MeetAudioPcm {
  /// Typical WebRTC capture rate.
  static let webrtcCaptureSampleRateHz = 48_000

  /// dtln-rs model input rate.
  static let dtlnSampleRateHz = 16_000

  static func downmix(_ samples: [Float], channels: Int) -> [Float] {
    if channels <= 1 {
      return samples
    }
    let frames = samples.count / channels
    return (0..<frames).map { frame in
      var sum: Float = 0
      for ch in 0..<channels {
        sum += samples[frame * channels + ch]
      }
      return sum / Float(channels)
    }
  }

  static func upmixToChannels(_ mono: [Float], channels: Int, frames: Int) -> [Float] {
    var out = [Float](repeating: 0, count: frames * channels)
    for frame in 0..<frames {
      let value = frame < mono.count ? mono[frame] : 0
      for ch in 0..<channels {
        out[frame * channels + ch] = value
      }
    }
    return out
  }

  static func resample(_ input: [Float], fromRate: Int, toRate: Int) -> [Float] {
    if fromRate == toRate || input.isEmpty {
      return input
    }
    let outLen = max(((input.count * toRate) / fromRate), 1)
    return (0..<outLen).map { i in
      let srcPos = Double(i) * Double(fromRate) / Double(toRate)
      let idx = min(max(Int(srcPos), 0), input.count - 1)
      let frac = Float(srcPos - Double(idx))
      let next = min(idx + 1, input.count - 1)
      return input[idx] * (1 - frac) + input[next] * frac
    }
  }

  static func fitToLength(_ samples: [Float], targetLen: Int) -> [Float] {
    if targetLen <= 0 {
      return []
    }
    if samples.count == targetLen {
      return samples
    }
    if samples.count > targetLen {
      return Array(samples.prefix(targetLen))
    }
    var out = samples
    out.append(contentsOf: [Float](repeating: 0, count: targetLen - samples.count))
    return out
  }

  @available(
    *,
    deprecated,
    message: "Unused; web-parity DTLN uses streaming ring buffers instead of per-buffer padding."
  )
  static func padToMultiple(_ samples: [Float], blockSize: Int) -> [Float] {
    if blockSize <= 0 {
      return samples
    }
    let len = ((samples.count + blockSize - 1) / blockSize) * blockSize
    if len == samples.count {
      return samples
    }
    var padded = samples
    padded.append(contentsOf: [Float](repeating: 0, count: len - samples.count))
    return padded
  }
}
