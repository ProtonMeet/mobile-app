import AVKit
import Flutter
import Foundation
import UIKit
import flutter_webrtc

private struct PipPresentationArgs {
  let participantIdentity: String
  let displayName: String
  let initials: String
  let backgroundColor: UIColor
  let profileTextColor: UIColor
  let hasVideo: Bool
  let peerConnectionId: String
  let remoteStreamId: String
  let videoTrackId: String

  init(_ dict: [String: Any]) {
    participantIdentity = dict["participantIdentity"] as? String ?? ""
    displayName = dict["displayName"] as? String ?? ""
    initials = dict["initials"] as? String ?? ""
    backgroundColor = Self.color(from: dict["backgroundColor"])
    profileTextColor = Self.color(from: dict["profileTextColor"])
    hasVideo = dict["hasVideo"] as? Bool ?? false
    peerConnectionId = dict["peerConnectionId"] as? String ?? ""
    remoteStreamId = dict["remoteStreamId"] as? String ?? ""
    videoTrackId = dict["videoTrackId"] as? String ?? ""
  }

  private static func color(from value: Any?) -> UIColor {
    let argb: Int
    if let i = value as? Int {
      argb = i
    } else if let n = value as? NSNumber {
      argb = n.intValue
    } else {
      return .darkGray
    }
    let a = CGFloat((argb >> 24) & 0xFF) / 255
    let r = CGFloat((argb >> 16) & 0xFF) / 255
    let g = CGFloat((argb >> 8) & 0xFF) / 255
    let b = CGFloat(argb & 0xFF) / 255
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}

/// Lays out video + avatar placeholder + participant name when PiP window size changes.
private final class PipVideoContainerView: UIView {
  let sampleBufferLayer: AVSampleBufferDisplayLayer

  private let avatarBackground = UIView()
  private let initialsLabel = UILabel()
  private let nameBackground = UIView()
  private let nameLabel = UILabel()

  init(sampleBufferLayer: AVSampleBufferDisplayLayer) {
    self.sampleBufferLayer = sampleBufferLayer
    super.init(frame: .zero)
    backgroundColor = .black
    clipsToBounds = true

    layer.addSublayer(sampleBufferLayer)
    sampleBufferLayer.videoGravity = .resizeAspectFill

    avatarBackground.isHidden = true
    addSubview(avatarBackground)

    initialsLabel.textAlignment = .center
    initialsLabel.adjustsFontSizeToFitWidth = true
    initialsLabel.minimumScaleFactor = 0.5
    avatarBackground.addSubview(initialsLabel)

    nameBackground.backgroundColor = UIColor.black.withAlphaComponent(0.55)
    addSubview(nameBackground)

    nameLabel.textColor = .white
    nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
    nameLabel.lineBreakMode = .byTruncatingTail
    nameLabel.numberOfLines = 1
    nameBackground.addSubview(nameLabel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private(set) var currentDisplayName: String = ""

  func updateParticipant(
    displayName: String,
    initials: String,
    backgroundColor: UIColor,
    profileTextColor: UIColor
  ) {
    currentDisplayName = displayName
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let label = trimmed.isEmpty ? initials : trimmed
    nameLabel.text = label
    initialsLabel.text = initials
    avatarBackground.backgroundColor = backgroundColor
    initialsLabel.textColor = profileTextColor
  }

  func setShowsAvatar(_ shows: Bool) {
    avatarBackground.isHidden = !shows
    sampleBufferLayer.isHidden = shows
    if shows {
      sampleBufferLayer.opacity = 0
    } else {
      sampleBufferLayer.opacity = 1
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    sampleBufferLayer.frame = bounds

    let avatarDiameter = min(bounds.width, bounds.height) * 0.38
    let avatarSize = CGSize(width: avatarDiameter, height: avatarDiameter)
    avatarBackground.frame = CGRect(
      x: (bounds.width - avatarSize.width) / 2,
      y: (bounds.height - avatarSize.height) / 2,
      width: avatarSize.width,
      height: avatarSize.height
    )
    avatarBackground.layer.cornerRadius = avatarDiameter / 2
    avatarBackground.clipsToBounds = true
    initialsLabel.frame = avatarBackground.bounds.insetBy(dx: 8, dy: 8)
    initialsLabel.font = .systemFont(ofSize: avatarDiameter * 0.32, weight: .medium)

    let nameHeight: CGFloat = 28
    nameBackground.frame = CGRect(
      x: 0,
      y: bounds.height - nameHeight,
      width: bounds.width,
      height: nameHeight
    )
    nameLabel.frame = nameBackground.bounds.insetBy(dx: 8, dy: 4)
  }
}

final class PipManager: NSObject {

  static let shared = PipManager()

  var pipEventsChannel: FlutterMethodChannel?

  private var pipController: AVPictureInPictureController?
  private var contentSource: AVPictureInPictureController.ContentSource?
  private var videoCallVC: AVPictureInPictureVideoCallViewController?
  private var videoContainer: PipVideoContainerView?
  private var sampleBufferLayer: AVSampleBufferDisplayLayer?
  private var sampleBufferRenderer: PipSampleBufferRenderer?
  private var pipVideoTrack: RTCVideoTrack?
    private var attachedVideoTrackId: String?
    private var attachedParticipantIdentity: String?
    private var attachedHasVideo = false
    private var isContentAttached = false
  private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
  private var contentBoundsObservation: NSKeyValueObservation?

  private override init() {
    super.init()
  }

  private func notifyPipState(_ active: Bool) {
    pipEventsChannel?.invokeMethod("pipStateChanged", arguments: active)
  }

  private static func flutterRootView() -> UIView? {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows where window.isKeyWindow || window.rootViewController != nil
      {
        if let flutterVC = window.rootViewController as? FlutterViewController {
          return flutterVC.view
        }
      }
    }
    return nil
  }

  func preparePiP(result: FlutterResult? = nil) {
    guard let rootView = Self.flutterRootView() else {
      result?(
        FlutterError(
          code: "pip_no_root_view",
          message: "Could not find Flutter root view for PiP.",
          details: nil))
      return
    }
    configureIfNeeded(rootView: rootView)
    result?(true)
  }

  func configureIfNeeded(rootView: UIView) {
    guard videoCallVC == nil else { return }

    let vc = AVPictureInPictureVideoCallViewController()
    vc.preferredContentSize = CGSize(width: 320, height: 180)
    vc.view.clipsToBounds = true

    let layer = AVSampleBufferDisplayLayer()
    layer.backgroundColor = UIColor.black.cgColor

    let container = PipVideoContainerView(sampleBufferLayer: layer)
    container.translatesAutoresizingMaskIntoConstraints = false
    vc.view.addSubview(container)

    NSLayoutConstraint.activate([
      container.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
      container.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
      container.topAnchor.constraint(equalTo: vc.view.topAnchor),
      container.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
    ])

    let renderer = PipSampleBufferRenderer(displayLayer: layer)
    renderer.delegate = self

    self.videoCallVC = vc
    self.videoContainer = container
    self.sampleBufferLayer = layer
    self.sampleBufferRenderer = renderer

    let source = AVPictureInPictureController.ContentSource(
      activeVideoCallSourceView: rootView,
      contentViewController: vc
    )
    self.contentSource = source

    let controller = AVPictureInPictureController(contentSource: source)
    controller.canStartPictureInPictureAutomaticallyFromInline = false
    controller.delegate = self
    self.pipController = controller

    contentBoundsObservation = vc.view.observe(\.bounds, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async {
        self?.relayoutVideoContent()
      }
    }
  }

  private func resolveVideoTrack(
    peerConnectionId: String,
    remoteStreamId: String,
    videoTrackId: String
  ) -> RTCVideoTrack? {
    guard let plugin = FlutterWebRTCPlugin.sharedSingleton() else {
      return nil
    }

    let pcKey: String? = peerConnectionId.isEmpty ? nil : peerConnectionId
    if !videoTrackId.isEmpty,
      let track = plugin.track(forId: videoTrackId, peerConnectionId: pcKey) as? RTCVideoTrack
    {
      return track
    }

    let mediaStream = plugin.stream(forId: remoteStreamId, peerConnectionId: peerConnectionId)
    return mediaStream?.videoTracks.first as? RTCVideoTrack
  }

  func attachPiP(args: [String: Any], result: @escaping FlutterResult) {
    let presentation = PipPresentationArgs(args)

    if contentSource == nil {
      preparePiP(result: nil)
      guard contentSource != nil else {
        result(
          FlutterError(
            code: "pip_not_configured",
            message: "PiP could not be prepared.",
            details: nil))
        return
      }
    }

    videoContainer?.updateParticipant(
      displayName: presentation.displayName,
      initials: presentation.initials,
      backgroundColor: presentation.backgroundColor,
      profileTextColor: presentation.profileTextColor
    )

    let trackChanged =
      attachedVideoTrackId != presentation.videoTrackId
      || attachedParticipantIdentity != presentation.participantIdentity
      || attachedHasVideo != presentation.hasVideo

    if !presentation.hasVideo {
      detachVideoRenderer()
      videoContainer?.setShowsAvatar(true)
      attachedParticipantIdentity = presentation.participantIdentity
      attachedHasVideo = false
      isContentAttached = true
      videoContainer?.setNeedsLayout()
      result(true)
      return
    }

    if presentation.videoTrackId.isEmpty {
      detachVideoRenderer()
      videoContainer?.setShowsAvatar(true)
      attachedParticipantIdentity = presentation.participantIdentity
      attachedHasVideo = true
      isContentAttached = true
      videoContainer?.setNeedsLayout()
      result(true)
      return
    }

    guard
      let resolvedVideo = resolveVideoTrack(
        peerConnectionId: presentation.peerConnectionId,
        remoteStreamId: presentation.remoteStreamId,
        videoTrackId: presentation.videoTrackId
      ), let renderer = sampleBufferRenderer
    else {
      detachVideoRenderer()
      videoContainer?.setShowsAvatar(true)
      attachedParticipantIdentity = presentation.participantIdentity
      attachedHasVideo = false
      isContentAttached = true
      result(true)
      return
    }

    if trackChanged {
      detachVideoRenderer(flushLayer: false)
      renderer.reset()
      sampleBufferLayer?.flush()
      videoContainer?.setShowsAvatar(true)
    }

    if pipVideoTrack !== resolvedVideo {
      pipVideoTrack?.remove(renderer)
      resolvedVideo.add(renderer)
      pipVideoTrack = resolvedVideo
    } else if trackChanged {
      resolvedVideo.remove(renderer)
      resolvedVideo.add(renderer)
    }

    attachedVideoTrackId = presentation.videoTrackId
    attachedParticipantIdentity = presentation.participantIdentity
    attachedHasVideo = true
    isContentAttached = true
    videoContainer?.setNeedsLayout()
    videoContainer?.layoutIfNeeded()
    result(true)
  }

  func attachPiP(
    peerConnectionId: String,
    remoteStreamId: String,
    videoTrackId: String,
    result: @escaping FlutterResult
  ) {
    attachPiP(
      args: [
        "peerConnectionId": peerConnectionId,
        "remoteStreamId": remoteStreamId,
        "videoTrackId": videoTrackId,
        "hasVideo": !videoTrackId.isEmpty,
      ],
      result: result
    )
  }

  func updatePiP(args: [String: Any], result: @escaping FlutterResult) {
    attachPiP(args: args, result: result)
  }

  func updatePiP(
    peerConnectionId: String,
    remoteStreamId: String,
    videoTrackId: String,
    result: @escaping FlutterResult
  ) {
    attachPiP(
      peerConnectionId: peerConnectionId,
      remoteStreamId: remoteStreamId,
      videoTrackId: videoTrackId,
      result: result
    )
  }

  private func detachVideoRenderer(flushLayer: Bool = true) {
    if let track = pipVideoTrack, let renderer = sampleBufferRenderer {
      track.remove(renderer)
    }
    pipVideoTrack = nil
    attachedVideoTrackId = nil
    sampleBufferRenderer?.reset()
    if flushLayer {
      sampleBufferLayer?.flush()
    }
  }

  func startPiP(result: @escaping FlutterResult) {
    guard isContentAttached, let controller = pipController else {
      result(
        FlutterError(
          code: "pip_not_attached",
          message: "Attach PiP content before starting PiP.",
          details: nil))
      return
    }

    beginBackgroundTaskIfNeeded()

    if AVPictureInPictureController.isPictureInPictureSupported() {
      if !controller.isPictureInPictureActive {
        controller.startPictureInPicture()
      }
      result(true)
    } else {
      result(
        FlutterError(
          code: "pip_not_supported",
          message: "Picture-in-Picture is not supported on this device.",
          details: nil))
    }
  }

  func stopPiP() {
    pipController?.stopPictureInPicture()
    endBackgroundTaskIfNeeded()
  }

  /// Mimics pressing the Home button so PiP stays visible over the home screen.
  func moveAppToBackground(result: @escaping FlutterResult) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
      result(true)
    }
  }

  func disposePiP() {
    contentBoundsObservation?.invalidate()
    contentBoundsObservation = nil
    detachVideoRenderer()
        attachedParticipantIdentity = nil
        attachedHasVideo = false
        isContentAttached = false
    sampleBufferLayer = nil
    sampleBufferRenderer = nil
    videoContainer = nil
    pipController?.delegate = nil
    pipController = nil
    contentSource = nil
    videoCallVC = nil
    endBackgroundTaskIfNeeded()
  }

  private func beginBackgroundTaskIfNeeded() {
    guard backgroundTaskId == .invalid else { return }
    backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "PiP") { [weak self] in
      self?.endBackgroundTaskIfNeeded()
    }
  }

  private func endBackgroundTaskIfNeeded() {
    guard backgroundTaskId != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTaskId)
    backgroundTaskId = .invalid
  }

  private func relayoutVideoContent() {
    videoContainer?.setNeedsLayout()
    videoContainer?.layoutIfNeeded()
    if let layer = sampleBufferLayer, layer.status == .failed {
      layer.flush()
    }
  }
}

extension PipManager: PipSampleBufferRendererDelegate {

  func pipSampleBufferRendererDidEnqueueFrame(_ renderer: PipSampleBufferRenderer) {
    videoContainer?.setShowsAvatar(false)
  }

  func pipSampleBufferRendererDidReset(_ renderer: PipSampleBufferRenderer) {
    videoContainer?.setShowsAvatar(true)
  }
}

extension PipManager: AVPictureInPictureControllerDelegate {

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    notifyPipState(true)
    DispatchQueue.main.async { [weak self] in
      self?.relayoutVideoContent()
    }
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    notifyPipState(false)
    endBackgroundTaskIfNeeded()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    notifyPipState(false)
    endBackgroundTaskIfNeeded()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    notifyPipState(false)
    endBackgroundTaskIfNeeded()
    completionHandler(true)
  }
}
