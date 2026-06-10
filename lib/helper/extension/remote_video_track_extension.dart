import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/remote_track_publication_extension.dart';

/// Extension methods for [RemoteTrackPublication<RemoteVideoTrack>].
extension RemoteVideoTrackPublicationExtension
    on RemoteTrackPublication<RemoteVideoTrack> {
  /// Wait for video track to be bound and ready before configuring.
  /// Returns `true` when [track] is non-null before [timeout], else `false`.
  Future<bool> waitForVideoTrackBound({
    Duration timeout = delaySubscriptionUpdate,
  }) =>
      waitForTrackBound(timeout: timeout);
}
