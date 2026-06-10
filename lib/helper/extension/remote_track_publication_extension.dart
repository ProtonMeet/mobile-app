import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';

/// Shared bind-wait polling for remote track publications (audio / video).
extension RemoteTrackPublicationBindExtension on RemoteTrackPublication {
  /// Wait until [track] is non-null or [timeout] elapses.
  /// Returns `true` when bound before the deadline.
  Future<bool> waitForTrackBound({
    Duration timeout = delaySubscriptionUpdate,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (track != null) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return track != null;
  }
}

/// Audio alias mirroring [RemoteVideoTrackPublicationExtension.waitForVideoTrackBound].
extension RemoteAudioTrackPublicationExtension
    on RemoteTrackPublication<RemoteAudioTrack> {
  Future<bool> waitForAudioTrackBound({
    Duration timeout = delaySubscriptionUpdate,
  }) =>
      waitForTrackBound(timeout: timeout);
}
