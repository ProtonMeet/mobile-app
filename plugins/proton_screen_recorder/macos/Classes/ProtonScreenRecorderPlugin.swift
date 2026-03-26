import AVFoundation
import Cocoa
import FlutterMacOS
import ReplayKit

/// ProtonScreenRecorderPlugin
///
/// This plugin provides screen recording functionality for macOS using ReplayKit.
/// Note: This implementation uses ReplayKit which is available on macOS 11.0 (Big Sur) and later.
///
/// For macOS 15.0 (Sonoma) and later, it's recommended to use ScreenCaptureKit instead of ReplayKit
/// as it provides better performance and more features. Future updates should migrate to:
/// - ScreenCaptureKit for capture
/// - AVAssetWriter for encoding
/// - SCStream for frame processing
///
/// Current limitations:
/// - Requires macOS 11.0 or later
/// - No audio recording support
/// - No camera recording support
/// - Limited control over recording quality
/// - Preview window is required for saving recordings
///
/// Future improvements:
/// - Migrate to ScreenCaptureKit for macOS 15.0+
/// - Add audio recording support
/// - Add camera recording support
/// - Add quality control options
/// - Add direct file saving without preview
///
@available(macOS 11.0, *)
public class ProtonScreenRecorderPlugin: NSObject, FlutterPlugin, RPPreviewViewControllerDelegate,
    NSWindowDelegate, RPScreenRecorderDelegate
{
    // MARK: - Properties

    private var recorder = RPScreenRecorder.shared()
    private var isRecording = false
    private var window: NSWindow?
    private var channel: FlutterMethodChannel?

    // MARK: - FlutterPlugin

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "screen_recording",
            binaryMessenger: registrar.messenger)
        let instance = ProtonScreenRecorderPlugin()
        instance.channel = channel
        instance.recorder.delegate = instance
        registrar.addMethodCallDelegate(instance, channel: channel)

        // Add observer for system bar stop events
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
        case "startRecording":
            handleStartRecording(call, result: result)
        case "stopRecording":
            handleStopRecording(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - RPScreenRecorderDelegate

    public func screenRecorderDidChangeAvailability(_ screenRecorder: RPScreenRecorder) {
        print("Screen recording availability changed: \(screenRecorder.isAvailable)")
        channel?.invokeMethod("recordingAvailabilityChanged", arguments: screenRecorder.isAvailable)
    }

    public func screenRecorder(
        _ screenRecorder: RPScreenRecorder,
        didStopRecordingWith error: Error?,
        previewViewController: RPPreviewViewController?
    ) {
        handleRecordingStop(error: error, previewViewController: previewViewController)
    }

    // MARK: - Notification Handling

    @objc private func handleSystemBarStop(_ notification: Notification) {
        // Only handle if recording was stopped from system bar
        guard !recorder.isRecording && isRecording else { return }

        // Stop recording to get preview controller
        recorder.stopRecording { [weak self] previewController, error in
            self?.handleRecordingStop(error: error, previewViewController: previewController)
        }
    }

    private func handleRecordingStop(error: Error?, previewViewController: RPPreviewViewController?)
    {
        isRecording = false

        if let error = error {
            print("Recording stopped with error: \(error)")
            channel?.invokeMethod("recordingStopped", arguments: nil)
            return
        }

        showPreviewWindow(previewController: previewViewController)
        channel?.invokeMethod("recordingStopped", arguments: nil)
    }

    // MARK: - Private Methods

    private func handleStartRecording(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any]
        let enableAudio = arguments?["enableAudio"] as? Bool ?? false
        let enableMicrophone = arguments?["enableMicrophone"] as? Bool ?? false

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

    private func handleStopRecording(result: @escaping FlutterResult) {
        stopScreenRecording { path in
            result(path)
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
                print("Failed to start recording: \(error)")
                completion(false, error.localizedDescription)
                return
            }

            self.isRecording = true
            print("Started screen recording")
            completion(true, nil)
        }
    }

    private func stopScreenRecording(completion: @escaping (String?) -> Void) {
        guard isRecording else {
            print("No active recording to stop")
            completion(nil)
            return
        }

        recorder.stopRecording { [weak self] previewController, error in
            guard let self = self else { return }
            self.isRecording = false
            if let error = error {
                print("Failed to stop recording: \(error)")
                completion(nil)
                return
            }

            self.showPreviewWindow(previewController: previewController)
            completion("recording_completed")
        }
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

    // MARK: - RPPreviewViewControllerDelegate

    public func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        if let window = window {
            window.close()
            self.window = nil
        }
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window == self.window {
            self.window = nil
        }
    }
}
