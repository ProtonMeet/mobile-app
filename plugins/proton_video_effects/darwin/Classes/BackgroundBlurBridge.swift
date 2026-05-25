/*
 * Copyright (c) 2026 Proton AG
 * Shared iOS + macOS blur bridge (flutter_webrtc local track processor).
 */

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif
import flutter_webrtc

private let kLogEveryNthFrame: UInt = 30

private final class MeetBackgroundBlurProcessor: NSObject, ExternalVideoProcessingDelegate {
  private var framesReceived: UInt = 0
  private var isEnabled = true
  private let mediaPipe = MeetBackgroundBlurMediaPipeEngine()

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
  }

  func onFrame(_ frame: RTCVideoFrame) -> RTCVideoFrame {
    if !isEnabled {
      return frame
    }
    if let buf = frame.buffer as? RTCCVPixelBuffer {
      mediaPipe.applyPersonBackgroundBlur(
        to: buf.pixelBuffer,
        rotationDegrees: Int32(frame.rotation.rawValue)
      )
    }
    framesReceived += 1
    if framesReceived == 1 || framesReceived % kLogEveryNthFrame == 0 {
      print(
        "[MeetBackgroundBlur] onFrame #\(framesReceived) width=\(frame.width) "
          + "height=\(frame.height) rotation=\(frame.rotation.rawValue) ts=\(frame.timeStamp)"
      )
    }
    return frame
  }
}

/// Registers `me.proton.meet/video_effects` and attaches blur on flutter_webrtc local tracks.
@objc public final class MeetBackgroundBlurNative: NSObject {
  private static var processors: [String: MeetBackgroundBlurProcessor] = [:]
  private static var sharedProcessor: MeetBackgroundBlurProcessor?
  private static var attachedTrackId: String?

  @objc public static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "me.proton.meet/video_effects",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isImplementationReady":
        result(MeetBackgroundBlurMediaPipeEngine.isReady)
      case "attach":
        guard let args = call.arguments as? [String: Any],
          let trackId = args["trackId"] as? String,
          !trackId.isEmpty
        else {
          result(FlutterError(code: "ARGS", message: "trackId required", details: nil))
          return
        }
        guard let plugin = FlutterWebRTCPlugin.sharedSingleton() else {
          result(
            FlutterError(
              code: "WEBRTC", message: "FlutterWebRTCPlugin not initialized", details: nil))
          return
        }
        guard let local = plugin.localTracks?[trackId] as? LocalVideoTrack else {
          result(
            FlutterError(code: "TRACK", message: "Local video track not found", details: trackId))
          return
        }
        if attachedTrackId == trackId, let existing = processors[trackId] ?? sharedProcessor {
          existing.setEnabled(true)
          processors[trackId] = existing
          result(nil)
          return
        }
        for (oldTrackId, oldProc) in processors where oldTrackId != trackId {
          oldProc.setEnabled(false)
          if let oldTrack = plugin.localTracks?[oldTrackId] as? LocalVideoTrack {
            oldTrack.removeProcessing(oldProc)
          }
          processors.removeValue(forKey: oldTrackId)
        }
        if processors[trackId] != nil {
          result(nil)
          return
        }
        let proc: MeetBackgroundBlurProcessor
        if let existing = sharedProcessor {
          proc = existing
        } else {
          let created = MeetBackgroundBlurProcessor()
          sharedProcessor = created
          proc = created
        }
        proc.setEnabled(true)
        local.addProcessing(proc)
        processors[trackId] = proc
        attachedTrackId = trackId
        result(nil)
      case "detach":
        guard let args = call.arguments as? [String: Any],
          let trackId = args["trackId"] as? String,
          !trackId.isEmpty
        else {
          result(FlutterError(code: "ARGS", message: "trackId required", details: nil))
          return
        }
        if let proc = processors.removeValue(forKey: trackId),
          let plugin = FlutterWebRTCPlugin.sharedSingleton(),
          let local = plugin.localTracks?[trackId] as? LocalVideoTrack
        {
          proc.setEnabled(false)
          local.removeProcessing(proc)
        }
        if attachedTrackId == trackId {
          attachedTrackId = nil
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
