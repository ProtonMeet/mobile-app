/*
 * Copyright (c) 2026 Proton AG
 *
 * Flutter plugin entry + WebRTC mic denoise channel (`me.proton.meet/denoise`).
 *
 * Stack:
 *   MeetAudioDenoiseNative — attach / detach / list types
 *   *Processor — ExternalAudioProcessingDelegate on the local audio track
 *     (RnnoiseProcessor, DeepFilterProcessor, DtlnRsProcessor)
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

private enum DenoiseKind: String, CaseIterable {
  case rnnoise
  case deepfilter
  case dtlnRs = "dtln-rs"

  var displayName: String {
    switch self {
    case .rnnoise: return "RNNoise"
    case .deepfilter: return "DeepFilter 3"
    case .dtlnRs: return "DTLN"
    }
  }
}

private protocol DenoiseCaptureProcessor: ExternalAudioProcessingDelegate {
  func setCaptureEnabled(_ enabled: Bool)
}

extension RnnoiseProcessor: DenoiseCaptureProcessor {
  func setCaptureEnabled(_ enabled: Bool) {
    if enabled { enable() } else { disable() }
  }
}

extension DeepFilterProcessor: DenoiseCaptureProcessor {
  func setCaptureEnabled(_ enabled: Bool) {
    if enabled { enable() } else { disable() }
  }
}

extension DtlnRsProcessor: DenoiseCaptureProcessor {
  func setCaptureEnabled(_ enabled: Bool) {
    if enabled { enable() } else { disable() }
  }
}

/// Registers `me.proton.meet/denoise` and attaches denoise on flutter_webrtc local audio tracks.
@objc final class MeetAudioDenoiseNative: NSObject {
  private static var processors: [String: ExternalAudioProcessingDelegate] = [:]
  private static var attachedTrackId: String?
  private static var attachedKind: DenoiseKind?

  private static func parseDeepFilterAttenLimDb(_ args: [String: Any]) -> Float {
    if let value = args["deepFilterAttenLimDb"] as? NSNumber {
      return min(max(value.floatValue, 1), 100)
    }
    return ProtonDeepFilterNative.defaultAttenLimDb
  }

  private static func makeProcessor(
    kind: DenoiseKind,
    deepFilterAttenLimDb: Float = ProtonDeepFilterNative.defaultAttenLimDb
  ) -> ExternalAudioProcessingDelegate {
    switch kind {
    case .rnnoise:
      return RnnoiseProcessor()
    case .deepfilter:
      return DeepFilterProcessor(
        modelResourceName: ProtonDeepFilterNative.ModelResource.net3,
        attenLimDb: deepFilterAttenLimDb
      )
    case .dtlnRs:
      return DtlnRsProcessor()
    }
  }

  private static func stopProcessorOnTrack(
    _ processor: ExternalAudioProcessingDelegate,
    local: LocalAudioTrack
  ) {
    setProcessorEnabled(processor, enabled: false)
    local.removeProcessing(processor)
    if let deepfilter = processor as? DeepFilterProcessor {
      // df_destroy is async on sessionQueue — do not call audioProcessingRelease here.
      DeepFilterProcessor.scheduleTeardown(deepfilter)
    } else {
      processor.audioProcessingRelease()
    }
  }

  private static func attachProcessor(
    trackId: String,
    kind: DenoiseKind,
    local: LocalAudioTrack,
    replacing oldProc: ExternalAudioProcessingDelegate?,
    deepFilterAttenLimDb: Float,
    result: @escaping FlutterResult
  ) {
    let proc = makeProcessor(kind: kind, deepFilterAttenLimDb: deepFilterAttenLimDb)
    let finish: () -> Void = {
      // WebRTC calls initialize at factory setup; processors added later need explicit init.
      proc.audioProcessingInitialize(withSampleRate: 48_000, channels: 1)
      setProcessorEnabled(proc, enabled: true)
      local.addProcessing(proc)
      processors[trackId] = proc
      attachedTrackId = trackId
      attachedKind = kind
      result(nil)
    }

    if let newDeepfilter = proc as? DeepFilterProcessor {
      let oldDeepfilter = oldProc as? DeepFilterProcessor
      // df_create on sessionQueue before addProcessing — avoids blocking WebRTC thread.
      DeepFilterProcessor.replace(old: oldDeepfilter, new: newDeepfilter) { ready in
        if !ready {
          result(
            FlutterError(
              code: "DEEPFILTER",
              message:
                "DeepFilter failed to load — rebuild ios pods and confirm DeepFilterNet3_onnx.tar.gz is in the app bundle",
              details: nil
            ))
          return
        }
        finish()
      }
      return
    }

    if let oldDeepfilter = oldProc as? DeepFilterProcessor {
      DeepFilterProcessor.scheduleTeardown(oldDeepfilter)
    }
    finish()
  }

  private static func setProcessorEnabled(
    _ processor: ExternalAudioProcessingDelegate,
    enabled: Bool
  ) {
    (processor as? DenoiseCaptureProcessor)?.setCaptureEnabled(enabled)
  }

  private static func isReady(kind: DenoiseKind) -> Bool {
    switch kind {
    case .rnnoise:
      return RnnoiseProcessor.isNativeReady
    case .deepfilter:
      return DeepFilterProcessor.isNativeReady(
        modelResourceName: ProtonDeepFilterNative.ModelResource.net3
      )
    case .dtlnRs:
      return DtlnRsProcessor.isNativeReady
    }
  }

  private static func listDenoiseTypesPayload() -> [[String: Any]] {
    DenoiseKind.allCases.map { kind in
      ["id": kind.rawValue, "displayName": kind.displayName, "isReady": isReady(kind: kind)]
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
        result(listDenoiseTypesPayload())
      case "isTypeReady":
        guard let args = call.arguments as? [String: Any],
          let typeId = args["type"] as? String,
          let kind = DenoiseKind(rawValue: typeId)
        else {
          result(false)
          return
        }
        result(isReady(kind: kind))
      case "diagnoseDenoise":
        result(DenoiseDiagnostics.payload())
      case "warmUpDenoise":
        if let args = call.arguments as? [String: Any],
          let typeId = args["type"] as? String,
          !typeId.isEmpty
        {
          var payload = DenoiseDiagnostics.warmUp(typeId: typeId)
          payload["id"] = typeId
          result(payload)
        } else {
          result(DenoiseDiagnostics.warmUpAll())
        }
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
              code: "WEBRTC_NOT_READY",
              message: "FlutterWebRTCPlugin not initialized — retry after the engine settles",
              details: nil))
          return
        }
        guard let local = plugin.localTracks?[trackId] as? LocalAudioTrack else {
          result(
            FlutterError(code: "TRACK", message: "Local audio track not found", details: trackId))
          return
        }
        let deepFilterAttenLimDb = parseDeepFilterAttenLimDb(args)
        if attachedTrackId == trackId, attachedKind == kind,
          let existing = processors[trackId]
        {
          // Idempotent re-attach — same track + backend already wired.
          setProcessorEnabled(existing, enabled: true)
          (existing as? DeepFilterProcessor)?.setAttenLimDb(deepFilterAttenLimDb)
          result(nil)
          return
        }

        let oldProc = processors[trackId]
        if let oldProc {
          setProcessorEnabled(oldProc, enabled: false)
          local.removeProcessing(oldProc)
          processors.removeValue(forKey: trackId)
          if oldProc as? DeepFilterProcessor == nil {
            oldProc.audioProcessingRelease()
          }
        }
        // One mic track at a time — detach denoise from any other local track.
        for (oldTrackId, otherProc) in processors where oldTrackId != trackId {
          if let oldTrack = plugin.localTracks?[oldTrackId] as? LocalAudioTrack {
            stopProcessorOnTrack(otherProc, local: oldTrack)
          }
          processors.removeValue(forKey: oldTrackId)
        }

        attachProcessor(
          trackId: trackId,
          kind: kind,
          local: local,
          replacing: oldProc,
          deepFilterAttenLimDb: deepFilterAttenLimDb,
          result: result
        )
      case "setDeepFilterAttenLim":
        guard let args = call.arguments as? [String: Any],
          let trackId = args["trackId"] as? String,
          !trackId.isEmpty,
          let attenValue = args["attenLimDb"] as? NSNumber
        else {
          result(FlutterError(code: "ARGS", message: "trackId and attenLimDb required", details: nil))
          return
        }
        guard let processor = processors[trackId] as? DeepFilterProcessor else {
          result(
            FlutterError(
              code: "TRACK",
              message: "No DeepFilter processor for track",
              details: trackId
            ))
          return
        }
        processor.setAttenLimDb(min(max(attenValue.floatValue, 1), 100))
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
          stopProcessorOnTrack(proc, local: local)
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
