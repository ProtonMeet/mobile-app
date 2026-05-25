import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:proton_video_effects/proton_video_effects.dart';

/// Attaches or detaches native camera background blur for the local camera track.
Future<void> syncLocalCameraBackgroundBlur({
  required Room room,
  required bool enabled,
}) async {
  if (kIsWeb) {
    return;
  }
  try {
    final unleash = ManagerFactory()
        .get<DataProviderManager>()
        .unleashDataProvider;
    if (!unleash.isMeetCameraBackgroundBlur()) {
      return;
    }
  } catch (_) {
    return;
  }

  final lp = room.localParticipant;
  if (lp == null) {
    return;
  }

  LocalVideoTrack? camera;
  for (final pub in lp.videoTrackPublications) {
    if (pub.isScreenShare) {
      continue;
    }
    final t = pub.track;
    if (t is LocalVideoTrack) {
      camera = t;
      break;
    }
  }
  if (camera == null) {
    return;
  }

  final id = camera.mediaStreamTrack.id;
  if (id == null || id.isEmpty) {
    return;
  }

  final effects = ProtonVideoEffects.instance;
  final ready = await effects.isBackgroundBlurReady();
  if (!ready) {
    return;
  }

  try {
    if (!enabled) {
      await effects.detachBackgroundBlur(trackId: id);
      return;
    }
    await effects.attachBackgroundBlur(trackId: id);
  } catch (e, st) {
    l.logger.e(
      '[CameraBackgroundBlur] sync failed: $e',
      error: e,
      stackTrace: st,
    );
  }
}
