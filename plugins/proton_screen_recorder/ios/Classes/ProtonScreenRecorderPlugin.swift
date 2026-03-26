import AVFoundation
import Flutter
import Photos
import ReplayKit

public class ProtonScreenRecorderPlugin: NSObject, FlutterPlugin, RPPreviewViewControllerDelegate {
    private var recorder = RPScreenRecorder.shared()
    private var isRecording = false
    private var methodChannel: FlutterMethodChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "screen_recording",
            binaryMessenger: registrar.messenger())
        let instance = ProtonScreenRecorderPlugin()
        instance.methodChannel = channel
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startRecording":
            startScreenRecording { success, error in
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
        case "stopRecording":
            stopScreenRecording { path in
                result(path)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startScreenRecording(completion: @escaping (Bool, String?) -> Void) {
        guard !isRecording else {
            completion(false, "Recording is already in progress")
            return
        }

        // Check if screen recording is available
        guard recorder.isAvailable else {
            completion(false, "Screen recording is not available")
            return
        }

        // Check photo library permissions
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard let self = self else { return }

            if status != .authorized {
                completion(false, "Photo library access is required for saving recordings")
                return
            }

            // Configure recorder
            self.recorder.isMicrophoneEnabled = true
            self.recorder.isCameraEnabled = false

            // Start recording
            self.recorder.startRecording { [weak self] error in
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

            guard let previewController = previewController else {
                print("No preview controller available")
                completion(nil)
                return
            }

            previewController.previewControllerDelegate = self

            // Present the preview controller so the user can save/share the video
            if let rootViewController = UIApplication.shared.keyWindow?.rootViewController {
                rootViewController.present(previewController, animated: true)
            }

            // You cannot get the file path or save programmatically on iOS
            completion(nil)
        }
    }

    // MARK: - RPPreviewViewControllerDelegate

    public func previewControllerDidFinish(_ previewController: RPPreviewViewController) {
        previewController.dismiss(animated: true)
    }
}
