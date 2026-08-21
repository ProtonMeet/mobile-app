import AVFoundation
import Foundation
import ReplayKit
import UIKit

/// Writes ReplayKit sample buffers directly to a file (no preview sheet).
final class ReplayKitFileRecorder {
    private let recorder = RPScreenRecorder.shared()
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    /// In-app audio (LiveKit / meeting playback).
    private var appAudioInput: AVAssetWriterInput?
    /// Microphone capture (local speaker).
    private var micAudioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var videoHasSamples = false
    private var appAudioHasSamples = false
    private var micAudioHasSamples = false
    private var isActive = false
    private var enableMicrophoneCapture = true
    private var samplesReceived = 0
    private let writeQueue = DispatchQueue(label: "com.proton.screenrecorder.ios.file.write")
    private var backgroundObserver: NSObjectProtocol?

    /// Called when iOS backgrounds the app and an active capture session is finalized.
    var onBackgroundInterrupt: ((Result<String, Error>) -> Void)?

    init() {
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleAppDidEnterBackground()
        }
    }

    deinit {
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    var isRecording: Bool { isActive }

    private static func nativeVideoDimensions() -> (width: Int, height: Int) {
        let screen = UIScreen.main
        let scale = screen.nativeScale
        let width = max(2, Int(screen.bounds.width * scale) & ~1)
        let height = max(2, Int(screen.bounds.height * scale) & ~1)
        return (width, height)
    }

    private static func makeAudioInput() -> AVAssetWriterInput {
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 96_000,
        ]
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audio.expectsMediaDataInRealTime = true
        return audio
    }

    func startRecording(
        outputPath: String,
        enableMicrophone: Bool,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !isActive else {
            completion(.failure(RecorderError.alreadyRecording))
            return
        }

#if targetEnvironment(simulator)
        completion(.failure(RecorderError.simulatorNotSupported))
        return
#endif

        guard recorder.isAvailable else {
            completion(.failure(RecorderError.notAvailable))
            return
        }

        let url = URL(fileURLWithPath: outputPath)
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: outputPath) {
                try FileManager.default.removeItem(at: url)
            }

            let writer = try CrashSafeAssetWriter.make(outputURL: url)
            outputURL = url

            let (width, height) = Self.nativeVideoDimensions()
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000
                ],
            ]
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            video.expectsMediaDataInRealTime = true
            guard writer.canAdd(video) else {
                throw RecorderError.writerSetupFailed
            }
            writer.add(video)
            videoInput = video

            let appAudio = Self.makeAudioInput()
            if writer.canAdd(appAudio) {
                writer.add(appAudio)
                appAudioInput = appAudio
            }

            if enableMicrophone {
                let micAudio = Self.makeAudioInput()
                if writer.canAdd(micAudio) {
                    writer.add(micAudio)
                    micAudioInput = micAudio
                }
            }

            assetWriter = writer
            enableMicrophoneCapture = enableMicrophone
            recorder.isMicrophoneEnabled = enableMicrophone
            recorder.isCameraEnabled = false

            recorder.startCapture { [weak self] sampleBuffer, bufferType, error in
                guard let self = self else { return }
                if let error = error {
                    print("ReplayKit capture error: \(error)")
                    return
                }
                // Buffers are only valid for the handler call; copy for async writing.
                var copiedBuffer: CMSampleBuffer?
                let copyStatus = CMSampleBufferCreateCopy(
                    allocator: kCFAllocatorDefault,
                    sampleBuffer: sampleBuffer,
                    sampleBufferOut: &copiedBuffer
                )
                guard copyStatus == noErr, let copiedBuffer else { return }
                self.writeQueue.async {
                    self.append(sampleBuffer: copiedBuffer, bufferType: bufferType)
                }
            } completionHandler: { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    self.reset()
                    completion(.failure(error))
                    return
                }
                self.isActive = true
                completion(.success(()))
            }
        } catch {
            reset()
            completion(.failure(error))
        }
    }

    func stopRecording(completion: @escaping (Result<String, Error>) -> Void) {
        guard isActive else {
            completion(.failure(RecorderError.notRecording))
            return
        }

        isActive = false
        recorder.stopCapture { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.writeQueue.async {
                    self.reset()
                    completion(.failure(error))
                }
                return
            }

            self.writeQueue.async {
                self.finalizeRecording(completion: completion)
            }
        }
    }

    private func handleAppDidEnterBackground() {
        guard isActive else { return }
        print("ReplayKitFileRecorder: app backgrounded — finalizing active recording")
        stopRecording { [weak self] result in
            self?.onBackgroundInterrupt?(result)
        }
    }

    private func finalizeRecording(completion: @escaping (Result<String, Error>) -> Void) {
        guard let writer = assetWriter, let url = outputURL else {
            reset()
            completion(.failure(RecorderError.notRecording))
            return
        }

        guard sessionStarted, writer.status == .writing else {
            removeOutputFile(at: url)
            if writer.status == .writing {
                writer.cancelWriting()
            }
            reset()
            print(
                "ReplayKitFileRecorder: finalize without samples "
                    + "(received=\(samplesReceived), started=\(sessionStarted))"
            )
            completion(.failure(RecorderError.noSamplesCaptured))
            return
        }

        markInputFinishedIfNeeded(videoInput, hasSamples: videoHasSamples)
        markInputFinishedIfNeeded(appAudioInput, hasSamples: appAudioHasSamples)
        markInputFinishedIfNeeded(micAudioInput, hasSamples: micAudioHasSamples)

        writer.finishWriting { [weak self] in
            defer { self?.reset() }
            if writer.status == .completed {
                completion(.success(url.path))
            } else {
                completion(.failure(writer.error ?? RecorderError.writerSetupFailed))
            }
        }
    }

    private func markInputFinishedIfNeeded(
        _ input: AVAssetWriterInput?,
        hasSamples: Bool
    ) {
        guard hasSamples, let input = input else { return }
        input.markAsFinished()
    }

    private func removeOutputFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func append(sampleBuffer: CMSampleBuffer, bufferType: RPSampleBufferType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let writer = assetWriter else { return }

        samplesReceived += 1

        if !sessionStarted {
            guard writer.startWriting() else {
                print(
                    "ReplayKitFileRecorder: startWriting failed: "
                        + "\(writer.error?.localizedDescription ?? "unknown")"
                )
                return
            }
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        switch bufferType {
        case .video:
            guard let input = videoInput, input.isReadyForMoreMediaData else { return }
            if input.append(sampleBuffer) {
                videoHasSamples = true
            }
        case .audioApp:
            guard let input = appAudioInput, input.isReadyForMoreMediaData else { return }
            if input.append(sampleBuffer) {
                appAudioHasSamples = true
            }
        case .audioMic:
            guard enableMicrophoneCapture, let input = micAudioInput,
                input.isReadyForMoreMediaData
            else { return }
            if input.append(sampleBuffer) {
                micAudioHasSamples = true
            }
        @unknown default:
            break
        }
    }

    private func reset() {
        assetWriter = nil
        videoInput = nil
        appAudioInput = nil
        micAudioInput = nil
        outputURL = nil
        sessionStarted = false
        videoHasSamples = false
        appAudioHasSamples = false
        micAudioHasSamples = false
        isActive = false
        enableMicrophoneCapture = true
        samplesReceived = 0
    }

    enum RecorderError: LocalizedError {
        case alreadyRecording
        case notRecording
        case notAvailable
        case writerSetupFailed
        /// ReplayKit started but no frames were written (common on Simulator).
        case noSamplesCaptured
        case simulatorNotSupported

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Recording is already in progress"
            case .notRecording: return "No active recording to stop"
            case .notAvailable: return "Screen recording is not available"
            case .writerSetupFailed: return "Failed to set up file writer"
            case .noSamplesCaptured:
                return "No recording data was captured. Keep Proton Meet open in the meeting and try again."
            case .simulatorNotSupported:
                return "Local meeting recording is not available in the iOS Simulator. Use a physical iPhone or iPad."
            }
        }
    }
}
