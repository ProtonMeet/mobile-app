import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';

/// Extension methods for [RemoteTrackPublication<RemoteVideoTrack>].
extension RemoteVideoTrackPublicationExtension
    on RemoteTrackPublication<RemoteVideoTrack> {
  /// Wait for video track to be bound and ready before configuring
  Future<void> waitForVideoTrackBound({
    Duration timeout = delaySubscriptionUpdate,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      // Wait for track to be bound
      if (track == null) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      } else {
        break;
      }
    }
  }
}
