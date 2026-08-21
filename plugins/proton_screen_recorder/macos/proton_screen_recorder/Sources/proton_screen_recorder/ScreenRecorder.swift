import AVFoundation
import Foundation
import ScreenCaptureKit

/// Writes screen + audio capture directly to a file using ScreenCaptureKit.
///
/// Audio capture APIs require macOS 13.0+; on older systems the plugin falls
/// back to ReplayKit preview mode.
@available(macOS 13.0, *)
final class ScreenCaptureFileRecorder: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private let writeQueue = DispatchQueue(label: "com.proton.screenrecorder.file.write")

    var isRecording: Bool { stream != nil }

    func startRecording(outputPath: String, enableMicrophone: Bool) async throws {
        guard stream == nil else {
            throw RecorderError.alreadyRecording
        }

        let url = URL(fileURLWithPath: outputPath)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: outputPath) {
            try FileManager.default.removeItem(at: url)
        }

        let writer = try CrashSafeAssetWriter.make(outputURL: url)
        outputURL = url

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        guard
            let currentApp = content.applications.first(where: {
                $0.bundleIdentifier == Bundle.main.bundleIdentifier
            }),
            let mainDisplay = content.displays.first
        else {
            throw RecorderError.appWindowNotFound
        }

        let filter = SCContentFilter(
            display: mainDisplay,
            including: [currentApp],
            exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = enableMicrophone
        config.excludesCurrentProcessAudio = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.sampleRate = 44_100
        config.channelCount = 2

        let appWindows = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        if let firstWindow = appWindows.first {
            config.width = Int(firstWindow.frame.width)
            config.height = Int(firstWindow.frame.height)
        } else {
            config.width = Int(mainDisplay.width)
            config.height = Int(mainDisplay.height)
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 5_000_000,
            ],
        ]
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { throw RecorderError.writerSetupFailed }
        writer.add(video)
        videoInput = video

        if enableMicrophone {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44_100,
                AVEncoderBitRateKey: 128_000,
            ]
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audio.expectsMediaDataInRealTime = true
            if writer.canAdd(audio) {
                writer.add(audio)
                audioInput = audio
            }
        }

        assetWriter = writer

        let captureStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try captureStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: writeQueue)
        if enableMicrophone {
            try captureStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: writeQueue)
        }
        try await captureStream.startCapture()
        stream = captureStream
    }

    func stopRecording() async throws -> String {
        guard let captureStream = stream, let url = outputURL else {
            throw RecorderError.notRecording
        }

        stream = nil
        try await captureStream.stopCapture()

        return try await withCheckedThrowingContinuation { continuation in
            writeQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: RecorderError.notRecording)
                    return
                }

                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()

                guard let writer = self.assetWriter else {
                    continuation.resume(throwing: RecorderError.writerSetupFailed)
                    return
                }

                writer.finishWriting {
                    if writer.status == .completed {
                        continuation.resume(returning: url.path)
                    } else {
                        continuation.resume(
                            throwing: writer.error ?? RecorderError.writerSetupFailed)
                    }
                    self.reset()
                }
            }
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let writer = assetWriter else { return }

        if !sessionStarted {
            guard writer.startWriting() else { return }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        switch type {
        case .screen:
            guard let input = videoInput, input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        case .audio:
            guard let input = audioInput, input.isReadyForMoreMediaData else { return }
            input.append(sampleBuffer)
        @unknown default:
            break
        }
    }

    private func reset() {
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        outputURL = nil
        sessionStarted = false
    }

    enum RecorderError: LocalizedError {
        case alreadyRecording
        case notRecording
        case appWindowNotFound
        case writerSetupFailed

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Recording is already in progress"
            case .notRecording: return "No active recording to stop"
            case .appWindowNotFound: return "App window not found for capture"
            case .writerSetupFailed: return "Failed to set up file writer"
            }
        }
    }
}
