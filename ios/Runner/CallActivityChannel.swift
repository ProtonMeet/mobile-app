import Flutter
import ActivityKit
import UIKit

@objc class CallActivityChannel: NSObject {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "call_activity", binaryMessenger: registrar.messenger())
        let instance = CallActivityChannel()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
}

extension CallActivityChannel: FlutterPlugin {
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard #available(iOS 16.2, *) else {
            result(FlutterError(code: "UNSUPPORTED", message: "Requires iOS 16.2+", details: nil))
            return
        }
        
        switch call.method {
        case "checkAvailability":
            
            let authInfo = ActivityAuthorizationInfo()
            let isEnabled = authInfo.areActivitiesEnabled
            let hasFrequentPushes = authInfo.frequentPushesEnabled
            print("CallActivityChannel: Live Activities available - enabled: \(isEnabled), frequent: \(hasFrequentPushes)")
            result([
                "available": true,
                "enabled": isEnabled,
                "frequentPushesEnabled": hasFrequentPushes,
                "iosVersion": "16.2+"
            ])
            
            return
            
            
        case "start":
            guard let args = call.arguments as? [String: Any],
                  let callId = args["callId"] as? String,
                  let roomName = args["roomName"] as? String,
                  let count = args["count"] as? Int
            else { result(FlutterError(code: "ARGS", message: "Invalid args", details: nil)); return }
            
            let muted = (args["isMuted"] as? Bool) ?? false
            let video = (args["isVideoEnabled"] as? Bool) ?? true
            CallActivityManager.shared.start(callId: callId, roomName: roomName, participantCount: count, isMuted: muted, isVideoEnabled: video)
            result(nil)
            
        case "update":
            let args = call.arguments as? [String: Any] ?? [:]
            CallActivityManager.shared.update(
                isMuted: args["isMuted"] as? Bool,
                isVideoEnabled: args["isVideoEnabled"] as? Bool,
                participantCount: args["count"] as? Int,
                roomName: args["roomName"] as? String,
                elapsedSeconds: args["elapsedSeconds"] as? Int
            )
            result(nil)
            
        case "end":
            CallActivityManager.shared.end(immediately: (call.arguments as? [String: Any])?["immediately"] as? Bool ?? false)
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
