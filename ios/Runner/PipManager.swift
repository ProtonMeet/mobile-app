import Foundation
import AVKit
import UIKit
import flutter_webrtc

final class PipManager: NSObject {
    
    static let shared = PipManager()
    
    private var pipController: AVPictureInPictureController?
    private var contentSource: AVPictureInPictureController.ContentSource?
    private var videoCallVC: AVPictureInPictureVideoCallViewController?
    private var containerView: UIView?
    private var rtcRenderer: RTCMTLVideoView?
    
    private override init() {
        super.init()
    }
    
    /// Call once when you have the main Flutter view (e.g. in AppDelegate or when the room screen is shown).
    func configureIfNeeded(rootView: UIView) {
        guard videoCallVC == nil else { return }
        
        let vc = AVPictureInPictureVideoCallViewController()
        vc.preferredContentSize = CGSize(width: 320, height: 180)
        vc.view.clipsToBounds = true
        
        let container = UIView(frame: vc.view.bounds)
        container.backgroundColor = .black
        container.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(container)
        
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            container.topAnchor.constraint(equalTo: vc.view.topAnchor),
            container.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor),
        ])
        
        self.videoCallVC = vc
        self.containerView = container
        
        // This is the view where the call UI is shown in your app (Flutter root view).
        // iOS uses it as the "source" for the PiP animation.
        let source = AVPictureInPictureController.ContentSource(
            activeVideoCallSourceView: rootView,
            contentViewController: vc
        )
        self.contentSource = source
    }
    
    /// Start PiP for a given remote stream.
    /// Call this from Flutter via MethodChannel and pass LiveKit/flutter-webrtc ids.
    func startPiP(peerConnectionId: String,
                  remoteStreamId: String,
                  result: @escaping FlutterResult) {
        guard let contentSource,
              let containerView
        else {
            result(FlutterError(code: "pip_not_configured",
                                message: "PiP not configured. Call configureIfNeeded(rootView:) first.",
                                details: nil))
            return
        }
        
        // Create renderer if needed
        if rtcRenderer == nil {
            let renderer = RTCMTLVideoView(frame: containerView.bounds)
            renderer.videoContentMode = .scaleAspectFill
            renderer.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(renderer)
            
            NSLayoutConstraint.activate([
                renderer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                renderer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                renderer.topAnchor.constraint(equalTo: containerView.topAnchor),
                renderer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            ])
            
            self.rtcRenderer = renderer
        }
        
        // Attach renderer to existing flutter-webrtc stream
        let plugin = FlutterWebRTCPlugin.sharedSingleton()
        let mediaStream = plugin?.stream(
            forId: remoteStreamId,
            peerConnectionId: peerConnectionId
        )
        
        guard let videoTrack = mediaStream?.videoTracks.first,
              let renderer = rtcRenderer
        else {
            result(FlutterError(code: "no_video_track",
                                message: "No remote video track found for PiP.",
                                details: nil))
            return
        }
        
        videoTrack.add(renderer)
        
        // Create PiP controller
        let controller = AVPictureInPictureController(contentSource: contentSource)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = self
        
        self.pipController = controller
        
        if AVPictureInPictureController.isPictureInPictureSupported() {
            controller.startPictureInPicture()
            result(true)
        } else {
            result(FlutterError(code: "pip_not_supported",
                                message: "Picture-in-Picture is not supported on this device.",
                                details: nil))
        }
    }
    
    func stopPiP() {
        pipController?.stopPictureInPicture()
    }
    
    func disposePiP() {
        // detach renderer from video track and cleanup
        if let renderer = rtcRenderer {
            renderer.removeFromSuperview()
            rtcRenderer = nil
        }
        pipController = nil
        // don't destroy videoCallVC/containerView so you can reuse them
    }
}

extension PipManager: AVPictureInPictureControllerDelegate {
    
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP will start")
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("PiP will stop")
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController,
                                    failedToStartPictureInPictureWithError error: Error) {
        print("PiP failed to start: \(error.localizedDescription)")
    }
}
