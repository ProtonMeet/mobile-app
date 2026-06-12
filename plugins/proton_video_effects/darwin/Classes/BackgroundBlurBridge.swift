/*
 * Copyright (c) 2026 Proton AG
 *
 * Flutter method channel ↔ flutter_webrtc local video track.
 *
 * Stack:
 *   MeetBackgroundBlurNative  — channel handler (attach / detach / config)
 *   MeetBackgroundBlurProcessor — ExternalVideoProcessingDelegate on the camera track
 *   MeetBackgroundBlurMediaPipeEngine — segmentation mask + Core Image composite
 *
 * One shared processor is reused across attach cycles; detach disables processing without
 * destroying the segmenter (matches Android BackgroundBlurChannel).
 */

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#endif
import flutter_webrtc

private let kLogEveryNthFrame: UInt = 30

/// Until Dart sends setBackgroundBlurConfig, matches [BackgroundBlurConfig] production defaults.
private let kPendingDefaultBlurSigma: CGFloat = 128.0
private let kPendingDefaultObscureOpacity: CGFloat = 0.1

private final class MeetBackgroundBlurProcessor: NSObject, ExternalVideoProcessingDelegate {
  private var framesReceived: UInt = 0
  private var isEnabled = true
  private let mediaPipe = MeetBackgroundBlurMediaPipeEngine()

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
  }

  func applyBlurConfig(blurSigma: CGFloat, backgroundObscureOpacity: CGFloat) {
    mediaPipe.setBlurConfig(
      blurSigma: blurSigma,
      backgroundObscureOpacity: backgroundObscureOpacity
    )
  }

  @discardableResult
  func setReplacementBackgroundImagePath(_ path: String?) -> Bool {
    mediaPipe.setReplacementBackgroundImagePath(path)
  }

  @discardableResult
  func setReplacementBackgroundImageData(_ data: Data?) -> Bool {
    mediaPipe.setReplacementBackgroundImageData(data)
  }

  func clearReplacementBackground() {
    mediaPipe.clearReplacementBackground()
  }

  func setSegmentationModelPreference(model: String) {
    mediaPipe.setSegmentationModelPreference(model: model)
  }

  func segmentationModelDebugInfo() -> [String: Any] {
    mediaPipe.segmentationModelDebugInfo()
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
  private static var pendingBlurSigma: CGFloat = kPendingDefaultBlurSigma
  private static var pendingObscureOpacity: CGFloat = kPendingDefaultObscureOpacity
  private static var pendingReplacementPath: String?
  private static var pendingReplacementData: Data?

  private static func storePendingBlurConfig(from args: [String: Any]) {
    if let sigma = (args["blurSigma"] as? NSNumber)?.doubleValue {
      pendingBlurSigma = CGFloat(sigma)
    }
    if let obscure = (args["backgroundObscureOpacity"] as? NSNumber)?.doubleValue {
      pendingObscureOpacity = CGFloat(obscure)
    }
  }

  private static func applyPendingBlurConfig(to proc: MeetBackgroundBlurProcessor) {
    proc.applyBlurConfig(
      blurSigma: pendingBlurSigma,
      backgroundObscureOpacity: pendingObscureOpacity
    )
  }

  /// Active per-track processors plus the shared instance (if not already in the map).
  private static func allProcessors() -> [MeetBackgroundBlurProcessor] {
    var list = Array(processors.values)
    if let shared = sharedProcessor, !list.contains(where: { $0 === shared }) {
      list.append(shared)
    }
    return list
  }

  private static func applyPendingStateToAll() {
    for proc in allProcessors() {
      applyPendingBlurConfig(to: proc)
      applyPendingReplacement(to: proc)
    }
  }

  private static func storePendingReplacement(from args: [String: Any]) {
    if args["backgroundMode"] as? String == "blur" {
      pendingReplacementPath = nil
      pendingReplacementData = nil
      return
    }
    if let path = args["replacementImagePath"] as? String, !path.isEmpty {
      pendingReplacementPath = path
      pendingReplacementData = nil
      return
    }
    if let path = args["filePath"] as? String, !path.isEmpty {
      pendingReplacementPath = path
      pendingReplacementData = nil
      return
    }
    if let typed = args["imageBytes"] as? FlutterStandardTypedData {
      pendingReplacementPath = nil
      pendingReplacementData = typed.data
    }
  }

  private static func applyPendingReplacement(to proc: MeetBackgroundBlurProcessor) {
    if let data = pendingReplacementData {
      _ = proc.setReplacementBackgroundImageData(data)
      return
    }
    if let path = pendingReplacementPath {
      _ = proc.setReplacementBackgroundImagePath(path)
      return
    }
    proc.clearReplacementBackground()
  }

  @discardableResult
  private static func applyReplacementBackground(
    from args: [String: Any],
    to processors: some Collection<MeetBackgroundBlurProcessor>
  ) -> Bool {
    storePendingReplacement(from: args)
    if args["backgroundMode"] as? String == "blur" {
      processors.forEach { $0.clearReplacementBackground() }
      return true
    }
    if let path = args["replacementImagePath"] as? String, !path.isEmpty {
      return processors.contains { $0.setReplacementBackgroundImagePath(path) }
    }
    if let path = args["filePath"] as? String, !path.isEmpty {
      return processors.contains { $0.setReplacementBackgroundImagePath(path) }
    }
    if let typed = args["imageBytes"] as? FlutterStandardTypedData {
      return processors.contains { $0.setReplacementBackgroundImageData(typed.data) }
    }
    return false
  }

  @objc public static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "me.proton.meet/video_effects",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isImplementationReady":
        result(MeetBackgroundBlurMediaPipeEngine.isReady)
      case "setBackgroundBlurConfig":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "ARGS", message: "config map required", details: nil))
          return
        }
        storePendingBlurConfig(from: args)
        storePendingReplacement(from: args)
        applyPendingStateToAll()
        result(nil)
      case "setReplacementBackgroundImage":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "ARGS", message: "filePath or imageBytes required", details: nil))
          return
        }
        storePendingReplacement(from: args)
        let targets = allProcessors()
        if targets.isEmpty {
          result(nil)
          return
        }
        if applyReplacementBackground(from: args, to: targets) {
          result(nil)
        } else {
          result(FlutterError(code: "IMAGE", message: "Failed to decode replacement image", details: nil))
        }
      case "setSegmentationModel":
        guard let args = call.arguments as? [String: Any],
          let model = args["model"] as? String
        else {
          result(FlutterError(code: "ARGS", message: "model required (single|landscape|multiclass|vision)", details: nil))
          return
        }
#if os(iOS)
        let valid = model == "single" || model == "landscape" || model == "multiclass" || model == "vision"
#elseif os(macOS)
        let valid = model == "vision"
#else
        let valid = false
#endif
        guard valid else {
          result(FlutterError(code: "ARGS", message: "unknown model: \(model)", details: nil))
          return
        }
        for proc in processors.values {
          proc.setSegmentationModelPreference(model: model)
        }
        sharedProcessor?.setSegmentationModelPreference(model: model)
        result(nil)
      case "getSegmentationModel":
        if let proc = processors.values.first ?? sharedProcessor {
          result(proc.segmentationModelDebugInfo())
        } else {
          result(MeetBackgroundBlurMediaPipeEngine().segmentationModelDebugInfo())
        }
      case "clearReplacementBackground":
        pendingReplacementPath = nil
        pendingReplacementData = nil
        for proc in processors.values {
          proc.clearReplacementBackground()
        }
        sharedProcessor?.clearReplacementBackground()
        result(nil)
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
          storePendingBlurConfig(from: args)
          applyPendingBlurConfig(to: existing)
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
        if let existing = processors[trackId] {
          storePendingBlurConfig(from: args)
          applyPendingBlurConfig(to: existing)
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
        if let args = call.arguments as? [String: Any] {
          storePendingBlurConfig(from: args)
        }
        applyPendingBlurConfig(to: proc)
        applyPendingReplacement(to: proc)
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
