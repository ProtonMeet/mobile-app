import AVFoundation
import Cocoa
import FlutterMacOS
import ReplayKit

/// ProtonScreenRecorderPlugin
///
/// Supports two capture modes on macOS:
/// - **File mode** (preferred): ScreenCaptureKit + AVAssetWriter writes incrementally
///   to a caller-supplied path — survives crashes with a partial file.
/// - **Preview mode** (legacy): ReplayKit + RPPreviewViewController when no path is given.
@available(macOS 11.0, *)
public class ProtonScreenRecorderPlugin: NSObject, FlutterPlugin, RPPreviewViewControllerDelegate,
    NSWindowDelegate, RPScreenRecorderDelegate
{
    private var recorder = RPScreenRecorder.shared()
    private var isRecording = false
    private var window: NSWindow?
    private var channel: FlutterMethodChannel?
    private var eventSink: FlutterEventSink?
    private var stopRecordingCompletion: ((String?) -> Void)?
    private var didPresentStopPreview = false

    /// Type-erased holder — [ScreenCaptureFileRecorder] requires macOS 13.0+.
    private var fileRecordingSession: Any?

    private var usesFileRecording = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "screen_recording",
            binaryMessenger: registrar.messenger)
        let instance = ProtonScreenRecorderPlugin()
        instance.channel = channel
        instance.recorder.delegate = instance
        registrar.addMethodCallDelegate(instance, channel: channel)

        let eventChannel = FlutterEventChannel(
            name: "screen_recording/events",
            binaryMessenger: registrar.messenger)
        eventChannel.setStreamHandler(instance)

        NotificationCenter.default.addObserver(
            instance,
            selector: #selector(handleSystemBarStop),
            name: NSNotification.Name("RPScreenRecorderRecordingStateChanged"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isSupported":
            result(recorder.isAvailable)
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

    private var currentlyRecording: Bool {
        if usesFileRecording {
            if #available(macOS 13.0, *) {
                return isMacOSFileRecording
            }
        }
        return isRecording || recorder.isRecording
    }

    public func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        eventSink?("recordingAvailabilityChanged")
    }

    public func screenRecorder(
        _ screenRecorder: RPScreenRecorder,
        didStopRecordingWith error: Error?,
        previewViewController: RPPreviewViewController?
    ) {
        handleRecordingStop(error: error, previewViewController: previewViewController)
    }

    @objc private func handleSystemBarStop(_ notification: Notification) {
        guard !usesFileRecording else { return }
        guard !recorder.isRecording && isRecording else { return }

        recorder.stopRecording { [weak self] previewController, error in
            self?.handleRecordingStop(error: error, previewViewController: previewController)
        }
    }

    private func handleRecordingStop(error: Error?, previewViewController: RPPreviewViewController?)
    {
        guard !usesFileRecording else { return }

        isRecording = false

        if stopRecordingCompletion != nil {
            return
        }

        if let error = error {
            print("Recording stopped with error: \(error)")
            eventSink?("recordingStopped")
            return
        }

        presentStopPreview(previewViewController: previewViewController)
        eventSink?("recordingStopped")
    }

    private func handleStartRecording(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any]
        let enableAudio = arguments?["enableAudio"] as? Bool ?? false
        let enableMicrophone = arguments?["enableMicrophone"] as? Bool ?? false
        let outputPath = arguments?["outputPath"] as? String

        if let outputPath = outputPath, !outputPath.isEmpty {
            if #available(macOS 13.0, *) {
                startFileRecording(
                    outputPath: outputPath,
                    enableMicrophone: enableMicrophone || enableAudio,
                    result: result)
            } else {
                // ScreenCaptureKit file APIs need macOS 13+ — fall back to ReplayKit.
                startScreenRecording(
                    enableAudio: enableAudio,
                    enableMicrophone: enableMicrophone
                ) { success, error in
                    if success {
                        result(true)
                    } else {
                        result(
                            FlutterError(
                                code: "RECORDING_ERROR",
                                message: error ?? "Failed to start recording",
                                details: nil))
                    }
                }
            }
            return
        }

        startScreenRecording(enableAudio: enableAudio, enableMicrophone: enableMicrophone) {
            success, error in
            if success {
                result(true)
            } else {
                result(
                    FlutterError(
                        code: "RECORDING_ERROR",
                        message: error ?? "Failed to start recording",
                        details: nil))
            }
        }
    }

    private func startFileRecording(
        outputPath: String,
        enableMicrophone: Bool,
        result: @escaping FlutterResult
    ) {
        usesFileRecording = true
        Task {
            do {
                if #available(macOS 13.0, *) {
                    try await startMacOSFileRecording(
                        outputPath: outputPath,
                        enableMicrophone: enableMicrophone)
                }
                await MainActor.run {
                    self.isRecording = true
                    result(true)
                }
            } catch {
                await MainActor.run {
                    self.usesFileRecording = false
                    result(
                        FlutterError(
                            code: "RECORDING_ERROR",
                            message: error.localizedDescription,
                            details: nil))
                }
            }
        }
    }

    private func handleStopRecording(result: @escaping FlutterResult) {
        if usesFileRecording {
            stopFileRecording(result: result)
            return
        }

        stopScreenRecording { path in
            result(path)
        }
    }

    private func stopFileRecording(result: @escaping FlutterResult) {
        guard #available(macOS 13.0, *) else {
            result(nil)
            return
        }

        Task {
            do {
                let path: String
                if #available(macOS 13.0, *) {
                    path = try await stopMacOSFileRecording()
                } else {
                    path = ""
                }
                await MainActor.run {
                    self.isRecording = false
                    self.usesFileRecording = false
                    self.eventSink?("recordingStopped")
                    result(path.isEmpty ? nil : path)
                }
            } catch {
                await MainActor.run {
                    self.isRecording = false
                    self.usesFileRecording = false
                    self.eventSink?("recordingStopped")
                    result(
                        FlutterError(
                            code: "RECORDING_ERROR",
                            message: error.localizedDescription,
                            details: nil))
                }
            }
        }
    }

    private func startScreenRecording(
        enableAudio: Bool, enableMicrophone: Bool, completion: @escaping (Bool, String?) -> Void
    ) {
        guard !isRecording else {
            completion(false, "Recording is already in progress")
            return
        }

        guard recorder.isAvailable else {
            completion(false, "Screen recording is not available")
            return
        }

        configureRecorder(enableMicrophone: enableMicrophone)

        if enableAudio {
            checkAndRequestAudioPermission { [weak self] granted, error in
                if granted {
                    self?.startRecordingWithAudio(completion: completion)
                } else {
                    completion(false, error)
                }
            }
        } else {
            startRecordingWithAudio(completion: completion)
        }
    }

    private func configureRecorder(enableMicrophone: Bool) {
        recorder.isMicrophoneEnabled = enableMicrophone
        recorder.isCameraEnabled = false
    }

    private func checkAndRequestAudioPermission(completion: @escaping (Bool, String?) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true, nil)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    completion(true, nil)
                } else {
                    completion(false, "Microphone permission not granted")
                }
            }
        case .denied, .restricted:
            completion(false, "Microphone permission denied")
        @unknown default:
            completion(false, "Unknown microphone permission status")
        }
    }

    private func startRecordingWithAudio(completion: @escaping (Bool, String?) -> Void) {
        recorder.startRecording { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                completion(false, error.localizedDescription)
                return
            }

            self.isRecording = true
            self.didPresentStopPreview = false
            completion(true, nil)
        }
    }

    private func stopScreenRecording(completion: @escaping (String?) -> Void) {
        guard isRecording || recorder.isRecording else {
            completion(nil)
            return
        }

        if stopRecordingCompletion != nil {
            completion(nil)
            return
        }

        isRecording = false
        stopRecordingCompletion = completion

        recorder.stopRecording { [weak self] previewController, error in
            guard let self = self else { return }

            let complete = self.stopRecordingCompletion
            self.stopRecordingCompletion = nil

            if let error = error {
                self.eventSink?("recordingStopped")
                complete?(nil)
                return
            }

            self.presentStopPreview(previewViewController: previewController)
            self.eventSink?("recordingStopped")
            complete?("recording_completed")
        }
    }

    private func presentStopPreview(previewViewController: RPPreviewViewController?) {
        guard !didPresentStopPreview else { return }
        didPresentStopPreview = true
        showPreviewWindow(previewController: previewViewController)
    }

    private func showPreviewWindow(previewController: RPPreviewViewController?) {
        guard let previewController = previewController else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let window = self.createPreviewWindow()
            window.contentViewController = previewController
            window.makeKeyAndOrderFront(nil)
            self.window = window

            previewController.previewControllerDelegate = self
        }
    }

    private func createPreviewWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Screen Recording Preview"
        window.delegate = self
        window.isReleasedWhenClosed = false
        return window
    }

    public func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        if let window = window {
            window.close()
            self.window = nil
        }
    }

    public func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == self.window {
            self.window = nil
        }
    }
}

extension ProtonScreenRecorderPlugin: FlutterStreamHandler {
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

@available(macOS 13.0, *)
private extension ProtonScreenRecorderPlugin {
    var macOSFileRecorder: ScreenCaptureFileRecorder {
        if let recorder = fileRecordingSession as? ScreenCaptureFileRecorder {
            return recorder
        }
        let recorder = ScreenCaptureFileRecorder()
        fileRecordingSession = recorder
        return recorder
    }

    var isMacOSFileRecording: Bool {
        (fileRecordingSession as? ScreenCaptureFileRecorder)?.isRecording ?? false
    }

    func startMacOSFileRecording(outputPath: String, enableMicrophone: Bool) async throws {
        try await macOSFileRecorder.startRecording(
            outputPath: outputPath,
            enableMicrophone: enableMicrophone)
    }

    func stopMacOSFileRecording() async throws -> String {
        defer { fileRecordingSession = nil }
        return try await macOSFileRecorder.stopRecording()
    }
}
