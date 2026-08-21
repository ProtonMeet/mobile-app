import AVFoundation
import Flutter
import Photos
import ReplayKit

public class ProtonScreenRecorderPlugin: NSObject, FlutterPlugin, RPPreviewViewControllerDelegate,
    FlutterStreamHandler
{
    private var recorder = RPScreenRecorder.shared()
    private var fileRecorder = ReplayKitFileRecorder()
    private var isRecording = false
    private var usesFileRecording = false
    private var eventSink: FlutterEventSink?

    override init() {
        super.init()
        fileRecorder.onBackgroundInterrupt = { [weak self] _ in
            guard let self = self else { return }
            self.isRecording = false
            self.usesFileRecording = false
            self.emitRecordingInterrupted()
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "screen_recording",
            binaryMessenger: registrar.messenger())
        let instance = ProtonScreenRecorderPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)

        let eventChannel = FlutterEventChannel(
            name: "screen_recording/events",
            binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            result(Self.isRecordingSupported(recorder: recorder))
        case "isRecording":
            result(currentlyRecording)
        case "startRecording":
            handleStartRecording(call, result: result)
        case "stopRecording":
            handleStopRecording(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func isRecordingSupported(recorder: RPScreenRecorder) -> Bool {
#if targetEnvironment(simulator)
        return false
#else
        return recorder.isAvailable
#endif
    }

    private var currentlyRecording: Bool {
        if usesFileRecording {
            return fileRecorder.isRecording
        }
        return isRecording || recorder.isRecording
    }

    private func handleStartRecording(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any]
        let enableMicrophone = arguments?["enableMicrophone"] as? Bool ?? true
        let outputPath = arguments?["outputPath"] as? String

        if let outputPath = outputPath, !outputPath.isEmpty {
            startFileRecording(
                outputPath: outputPath,
                enableMicrophone: enableMicrophone,
                result: result)
            return
        }

        startPreviewRecording(enableMicrophone: enableMicrophone, result: result)
    }

    private func startFileRecording(
        outputPath: String,
        enableMicrophone: Bool,
        result: @escaping FlutterResult
    ) {
        usesFileRecording = true
        fileRecorder.startRecording(
            outputPath: outputPath,
            enableMicrophone: enableMicrophone
        ) { [weak self] outcome in
            guard let self = self else { return }
            switch outcome {
            case .success:
                self.isRecording = true
                result(true)
            case .failure(let error):
                self.usesFileRecording = false
                result(
                    FlutterError(
                        code: "RECORDING_ERROR",
                        message: error.localizedDescription,
                        details: nil))
            }
        }
    }

    private func startPreviewRecording(
        enableMicrophone: Bool,
        result: @escaping FlutterResult
    ) {
        guard !isRecording else {
            result(
                FlutterError(
                    code: "RECORDING_ERROR",
                    message: "Recording is already in progress",
                    details: nil))
            return
        }

        guard recorder.isAvailable else {
            result(
                FlutterError(
                    code: "RECORDING_ERROR",
                    message: "Screen recording is not available",
                    details: nil))
            return
        }

        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard let self = self else { return }

            if status != .authorized {
                result(
                    FlutterError(
                        code: "RECORDING_ERROR",
                        message: "Photo library access is required for saving recordings",
                        details: nil))
                return
            }

            self.recorder.isMicrophoneEnabled = enableMicrophone
            self.recorder.isCameraEnabled = false

            self.recorder.startRecording { [weak self] error in
                guard let self = self else { return }

                if let error = error {
                    result(
                        FlutterError(
                            code: "RECORDING_ERROR",
                            message: error.localizedDescription,
                            details: nil))
                    return
                }

                self.isRecording = true
                result(true)
            }
        }
    }

    private func handleStopRecording(result: @escaping FlutterResult) {
        if usesFileRecording {
            fileRecorder.stopRecording { [weak self] outcome in
                guard let self = self else { return }
                self.isRecording = false
                self.usesFileRecording = false
                // File-mode stop is initiated by Dart; no event (avoids wrong thread + double-stop).
                switch outcome {
                case .success(let path):
                    result(path)
                case .failure(let error):
                    result(
                        FlutterError(
                            code: "RECORDING_ERROR",
                            message: error.localizedDescription,
                            details: nil))
                }
            }
            return
        }

        stopPreviewRecording(result: result)
    }

    private func emitRecordingStopped() {
        guard let sink = eventSink else { return }
        let post = { sink("recordingStopped") }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    private func emitRecordingInterrupted() {
        guard let sink = eventSink else { return }
        let post = { sink("recordingInterrupted") }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    private func stopPreviewRecording(result: @escaping FlutterResult) {
        guard isRecording || recorder.isRecording else {
            result(nil)
            return
        }

        isRecording = false

        recorder.stopRecording { [weak self] previewController, error in
            guard let self = self else { return }

            self.isRecording = false
            if let error = error {
                self.emitRecordingStopped()
                result(nil)
                return
            }

            guard let previewController = previewController else {
                self.emitRecordingStopped()
                result(nil)
                return
            }

            previewController.previewControllerDelegate = self

            if let rootViewController = UIApplication.shared.keyWindow?.rootViewController {
                rootViewController.present(previewController, animated: true)
            }

            self.emitRecordingStopped()
            result(nil)
        }
    }

    public func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        previewController.dismiss(animated: true)
    }

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
        -> FlutterError?
    {
        eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
