import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

/// Local WebRTC loopback so processed mic audio can be heard without joining a room.
///
/// Mirrors the flutter_webrtc device-enumeration sample: publish the capture track on
/// one peer connection and play the received track through an [rtc.RTCVideoRenderer].
class DenoiseMicPreviewLoopback {
  rtc.RTCPeerConnection? _senderPc;
  rtc.RTCPeerConnection? _receiverPc;
  rtc.RTCVideoRenderer? _playbackRenderer;

  rtc.RTCVideoRenderer? get playbackRenderer => _playbackRenderer;

  Future<void> start(LocalAudioTrack track) async {
    await stop();

    final renderer = rtc.RTCVideoRenderer();
    await renderer.initialize();
    _playbackRenderer = renderer;

    final receiverPc = await rtc.createPeerConnection({});
    final senderPc = await rtc.createPeerConnection({});
    _receiverPc = receiverPc;
    _senderPc = senderPc;

    receiverPc.onTrack = (event) {
      if (event.track.kind == 'audio' && event.streams.isNotEmpty) {
        renderer.srcObject = event.streams.first;
      }
    };

    await receiverPc.addTransceiver(
      kind: rtc.RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: rtc.RTCRtpTransceiverInit(
        direction: rtc.TransceiverDirection.RecvOnly,
      ),
    );

    senderPc.onIceCandidate = receiverPc.addCandidate;
    receiverPc.onIceCandidate = senderPc.addCandidate;

    await senderPc.addTrack(track.mediaStreamTrack, track.mediaStream);

    final offer = await senderPc.createOffer();
    await senderPc.setLocalDescription(offer);
    await receiverPc.setRemoteDescription(offer);
    final answer = await receiverPc.createAnswer();
    await receiverPc.setLocalDescription(answer);
    await senderPc.setRemoteDescription(answer);
  }

  Future<void> setAudioOutput(String deviceId) async {
    final renderer = _playbackRenderer;
    if (renderer == null) {
      return;
    }
    await renderer.audioOutput(deviceId);
  }

  Future<void> stop() async {
    final renderer = _playbackRenderer;
    if (renderer != null) {
      renderer.srcObject = null;
      try {
        await renderer.dispose();
      } catch (_) {}
      _playbackRenderer = null;
    }

    final senderPc = _senderPc;
    final receiverPc = _receiverPc;
    _senderPc = null;
    _receiverPc = null;

    if (senderPc != null) {
      try {
        await senderPc.close();
      } catch (_) {}
    }
    if (receiverPc != null) {
      try {
        await receiverPc.close();
      } catch (_) {}
    }
  }
}
