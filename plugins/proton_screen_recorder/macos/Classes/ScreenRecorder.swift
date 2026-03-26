// import Foundation
// import ScreenCaptureKit
// import AVFoundation

// class ScreenRecorder: NSObject, SCStreamOutput {
//     private var stream: SCStream?
//     private var assetWriter: AVAssetWriter!
//     private var videoInput: AVAssetWriterInput!
//     private var audioInput: AVAssetWriterInput!
//     private var outputURL: URL!

//     func startRecording() async throws {
//         outputURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
//             .appendingPathComponent("ScreenCapture.mov")
//         try? FileManager.default.removeItem(at: outputURL)
//         assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

//         let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
//         guard let currentApp = content.applications.first(where: { $0.bundleIdentifier == Bundle.main.bundleIdentifier }),
//               let mainDisplay = content.displays.first else {
//             throw NSError(domain: "ScreenCap", code: -1, userInfo: [NSLocalizedDescriptionKey: "App window not found"])
//         }

//         let filter = SCContentFilter(display: mainDisplay, includingApplications: [currentApp], exceptingWindows: [])

//         let config = SCStreamConfiguration()
//         config.capturesAudio = true
//         config.excludesCurrentProcessAudio = false
//         config.minimumFrameInterval = CMTime(value: 1, timescale: 30)

//         if let firstWindow = currentApp.windows.first {
//             let scale = firstWindow.screen?.backingScaleFactor ?? 1
//             config.width = Int(firstWindow.frame.width * scale)
//             config.height = Int(firstWindow.frame.height * scale)
//         }

//         let videoSettings: [String: Any] = [
//             AVVideoCodecKey: AVVideoCodecType.h264,
//             AVVideoWidthKey: config.width,
//             AVVideoHeightKey: config.height,
//             AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000]
//         ]
//         videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
//         videoInput.expectsMediaDataInRealTime = true
//         assetWriter.add(videoInput)

//         let audioSettings: [String: Any] = [
//             AVFormatIDKey: kAudioFormatMPEG4AAC,
//             AVNumberOfChannelsKey: 2,
//             AVSampleRateKey: 44100,
//             AVEncoderBitRateKey: 128000
//         ]
//         audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
//         audioInput.expectsMediaDataInRealTime = true
//         assetWriter.add(audioInput)

//         assetWriter.startWriting()
//         let startTime = CMClock.hostTimeClock().time
//         assetWriter.startSession(atSourceTime: startTime)

//         stream = SCStream(filter: filter, configuration: config, delegate: nil)
//         try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
//         try stream?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .main)
//         try await stream?.startCapture()
//     }

//     func stopRecording() {
//         stream?.stopCapture()
//         let endTime = CMClock.hostTimeClock().time
//         assetWriter.endSession(atSourceTime: endTime)
//         videoInput.markAsFinished()
//         audioInput.markAsFinished()
//         assetWriter.finishWriting { [weak self] in
//             if let fileURL = self?.outputURL {
//                 print("Recording saved to \(fileURL.path)")
//             }
//         }
//     }

//     func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
//         switch type {
//         case .screen:
//             if videoInput.isReadyForMoreMediaData {
//                 videoInput.append(sampleBuffer)
//             }
//         case .audio:
//             if audioInput.isReadyForMoreMediaData {
//                 audioInput.append(sampleBuffer)
//             }
//         default:
//             break
//         }
//     }
// }
