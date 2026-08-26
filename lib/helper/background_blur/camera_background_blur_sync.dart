import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/background_blur/camera_background_effect_service.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';

export 'camera_background_effect_service.dart';
export 'camera_background_selection.dart';

/// Attaches or detaches native camera background blur for the local camera track.
Future<void> syncLocalCameraBackgroundBlur({
  required Room room,
  required bool enabled,
}) {
  final selection = enabled
      ? const CameraBackgroundSelection.blur()
      : const CameraBackgroundSelection.none();
  return syncLocalCameraBackgroundEffect(room: room, selection: selection);
}
