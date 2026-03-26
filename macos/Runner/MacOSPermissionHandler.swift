import AVFoundation
import CoreGraphics
import FlutterMacOS
import Foundation

/// Handler for macOS camera and microphone permissions
class MacOSPermissionHandler: NSObject, FlutterPlugin {

    /// Register the plugin with the Flutter engine
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "me.proton.meet/macos_permissions", binaryMessenger: registrar.messenger)
        let instance = MacOSPermissionHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    /// Handle method calls from Flutter
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "hasCameraPermission":
            result(checkCameraPermission())
        case "cameraStatus":
            result(getCameraStatus())
        case "requestCameraPermission":
            requestCameraPermission { granted in
                result(granted)
            }
        case "hasMicrophonePermission":
            result(checkMicrophonePermission())
        case "microphoneStatus":
            result(getMicrophoneStatus())
        case "requestMicrophonePermission":
            requestMicrophonePermission { granted in
                result(granted)
            }
        case "hasShareScreenCapturePermission":
            let hasPermission = CGPreflightScreenCaptureAccess()
            if !hasPermission {
                let _ = CGRequestScreenCaptureAccess()
            }
            result(hasPermission)
        case "requestShareScreenCapturePermission":
            let hasPermission = CGPreflightScreenCaptureAccess()
            if !hasPermission {
                // Triggers system dialog (only once ever)
                let alert = NSAlert()
                alert.messageText = "Screen Recording Permission Needed"
                alert.informativeText =
                    "To share your screen, please enable screen recording permission in System Settings."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // Open System Settings → Screen Recording
                    if let url = URL(
                        string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
                result(hasPermission)
            } else {
                result(false)
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Check if camera permission is granted
    private func checkCameraPermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .authorized
    }

    /// Get camera permission status as a string
    private func getCameraStatus() -> String {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return authorizationStatusToString(status)
    }

    /// Request camera permission
    private func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            let granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            completion(granted)
        }
    }

    /// Check if microphone permission is granted
    private func checkMicrophonePermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return status == .authorized
    }

    /// Get microphone permission status as a string
    private func getMicrophoneStatus() -> String {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return authorizationStatusToString(status)
    }

    /// Convert AVAuthorizationStatus to string
    private func authorizationStatusToString(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        @unknown default:
            return "denied"
        }
    }

    /// Request microphone permission
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            completion(granted)
        }
    }
}
