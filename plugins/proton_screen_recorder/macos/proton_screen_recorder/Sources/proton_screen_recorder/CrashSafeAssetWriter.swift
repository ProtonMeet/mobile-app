import AVFoundation
import Foundation

/// Configures `AVAssetWriter` for crash-safe incremental file output.
enum CrashSafeAssetWriter {
    /// Fragment interval — each fragment includes its own metadata so the file
    /// remains playable if the process exits before `finishWriting()`.
    private static let fragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)

    static func make(outputURL: URL) throws -> AVAssetWriter {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        configureForCrashRecovery(writer)
        return writer
    }

    static func configureForCrashRecovery(_ writer: AVAssetWriter) {
        writer.movieFragmentInterval = fragmentInterval
    }
}
