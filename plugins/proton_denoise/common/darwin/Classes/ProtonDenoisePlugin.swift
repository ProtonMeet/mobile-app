/*
 * Copyright (c) 2026 Proton AG
 * Flutter plugin entry + WebRTC track denoise (`me.proton.meet/denoise`).
 */

import flutter_webrtc

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

public class ProtonDenoisePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      MeetAudioDenoiseNative.register(with: registrar.messenger())
    #else
      MeetAudioDenoiseNative.register(with: registrar.messenger)
    #endif
  }
}

private enum DenoiseKind: String {
  case rnnoise
  case deepfilter
}

/// Registers `me.proton.meet/denoise` and attaches denoise on flutter_webrtc local audio tracks.
@objc final class MeetAudioDenoiseNative: NSObject {
  private static var processors: [String: ExternalAudioProcessingDelegate] = [:]
  private static var attachedTrackId: String?
  private static var attachedKind: DenoiseKind?

  private static func makeProcessor(kind: DenoiseKind) -> ExternalAudioProcessingDelegate {
    switch kind {
    case .rnnoise:
      return RnnoiseProcessor()
    case .deepfilter:
      return DeepFilterProcessor()
    }
  }

  private static func setProcessorEnabled(
    _ processor: ExternalAudioProcessingDelegate,
    enabled: Bool
  ) {
    if let rnnoise = processor as? RnnoiseProcessor {
      if enabled {
        rnnoise.enable()
      } else {
        rnnoise.disable()
      }
    } else if let deepfilter = processor as? DeepFilterProcessor {
      if enabled {
        deepfilter.enable()
      } else {
        deepfilter.disable()
      }
    }
  }

  private static func isReady(kind: DenoiseKind) -> Bool {
    switch kind {
    case .rnnoise:
      return true
    case .deepfilter:
      return false
    }
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "me.proton.meet/denoise",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "listDenoiseTypes":
        result([
          ["id": "rnnoise", "displayName": "RNNoise", "isReady": isReady(kind: .rnnoise)],
          ["id": "deepfilter", "displayName": "DeepFilter", "isReady": isReady(kind: .deepfilter)],
        ])
      case "isTypeReady":
        guard let args = call.arguments as? [String: Any],
          let typeId = args["type"] as? String,
          let kind = DenoiseKind(rawValue: typeId)
        else {
          result(false)
          return
        }
        result(isReady(kind: kind))
      case "attach":
        guard let args = call.arguments as? [String: Any],
          let trackId = args["trackId"] as? String,
          !trackId.isEmpty,
          let typeId = args["type"] as? String,
          let kind = DenoiseKind(rawValue: typeId)
        else {
          result(FlutterError(code: "ARGS", message: "trackId and type required", details: nil))
          return
        }
        guard let plugin = FlutterWebRTCPlugin.sharedSingleton() else {
          result(
            FlutterError(
              code: "WEBRTC", message: "FlutterWebRTCPlugin not initialized", details: nil))
          return
        }
        guard let local = plugin.localTracks?[trackId] as? LocalAudioTrack else {
          result(
            FlutterError(code: "TRACK", message: "Local audio track not found", details: trackId))
          return
        }
        if attachedTrackId == trackId, attachedKind == kind,
          let existing = processors[trackId]
        {
          setProcessorEnabled(existing, enabled: true)
          result(nil)
          return
        }
        if let oldProc = processors[trackId] {
          setProcessorEnabled(oldProc, enabled: false)
          local.removeProcessing(oldProc)
          processors.removeValue(forKey: trackId)
        }
        for (oldTrackId, oldProc) in processors where oldTrackId != trackId {
          setProcessorEnabled(oldProc, enabled: false)
          if let oldTrack = plugin.localTracks?[oldTrackId] as? LocalAudioTrack {
            oldTrack.removeProcessing(oldProc)
          }
          processors.removeValue(forKey: oldTrackId)
        }
        let proc = makeProcessor(kind: kind)
        setProcessorEnabled(proc, enabled: true)
        local.addProcessing(proc)
        processors[trackId] = proc
        attachedTrackId = trackId
        attachedKind = kind
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
          let local = plugin.localTracks?[trackId] as? LocalAudioTrack
        {
          setProcessorEnabled(proc, enabled: false)
          local.removeProcessing(proc)
        }
        if attachedTrackId == trackId {
          attachedTrackId = nil
          attachedKind = nil
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
