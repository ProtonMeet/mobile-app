import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/helper/background_blur/virtual_background_presets.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:proton_video_effects/proton_video_effects.dart';

/// Production blur tuning defaults from [BackgroundBlurConfig].
BackgroundBlurConfig resolveCameraBackgroundBlurConfig([
  CameraBackgroundSelection selection = const CameraBackgroundSelection.none(),
]) {
  return selection.toBlurConfig();
}

/// Applies [selection] to an existing local camera track without recreating it.
Future<void> applyCameraBackgroundSelectionToTrack({
  required String trackId,
  required CameraBackgroundSelection selection,
}) async {
  if (kIsWeb) {
    return;
  }

  final effects = ProtonVideoEffects.instance;
  final ready = await effects.isBackgroundBlurReady();
  if (!ready) {
    return;
  }

  try {
    if (!selection.isEffectActive) {
      await effects.clearReplacementBackground();
      await effects.detachBackgroundBlur(trackId: trackId);
      return;
    }

    // A rejected image must not take the attach down with it: the caller has
    // already committed the selection to state, so bailing here would leave the
    // track on its previous effect while the UI claims the new one is live.
    // Degrading to blur keeps the camera covered, which is the point of the
    // feature, and matches what the native side falls back to.
    var effectiveSelection = selection;
    try {
      await _applyReplacementImageIfNeeded(effects, selection);
    } catch (e, st) {
      l.logger.e(
        '[CameraBackgroundEffect] replacement image rejected, '
        'falling back to blur: $e',
        error: e,
        stackTrace: st,
      );
      await effects.clearReplacementBackground();
      effectiveSelection = const CameraBackgroundSelection.blur();
    }

    final config = effectiveSelection.toBlurConfig(
      replacementImagePath:
          effectiveSelection.kind == CameraBackgroundEffectKind.custom
          ? effectiveSelection.customImagePath
          : null,
    );
    await effects.setBackgroundBlurConfig(config);
    await effects.attachBackgroundBlur(trackId: trackId, config: config);
  } catch (e, st) {
    l.logger.e(
      '[CameraBackgroundEffect] apply failed: $e',
      error: e,
      stackTrace: st,
    );
  }
}

/// Attaches or detaches native camera background effects for the local camera track.
Future<void> syncLocalCameraBackgroundEffect({
  required Room room,
  required CameraBackgroundSelection selection,
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

  await applyCameraBackgroundSelectionToTrack(
    trackId: id,
    selection: selection,
  );
}

Future<void> _applyReplacementImageIfNeeded(
  ProtonVideoEffects effects,
  CameraBackgroundSelection selection,
) async {
  switch (selection.kind) {
    case CameraBackgroundEffectKind.none:
    case CameraBackgroundEffectKind.blur:
      await effects.clearReplacementBackground();
      return;
    case CameraBackgroundEffectKind.custom:
      final path = selection.customImagePath;
      if (path != null && path.isNotEmpty) {
        await effects.setReplacementBackgroundImagePath(path);
      }
      return;
    case CameraBackgroundEffectKind.preset:
      final presetId = selection.presetId;
      if (presetId == null || presetId.isEmpty) {
        return;
      }
      final bytes = await VirtualBackgroundPresets.loadPresetBytes(presetId);
      if (bytes == null) {
        return;
      }
      await effects.setReplacementBackgroundImageBytes(_viewOf(bytes));
      return;
  }
}

/// Bytes actually covered by [data].
///
/// `rootBundle.load` may hand back a window onto a larger buffer, so reading
/// the whole backing store would ship neighbouring assets to the decoder.
Uint8List _viewOf(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

/// Ensures native replacement image state matches [selection] before track attach.
Future<void> prepareCameraBackgroundSelectionForTrackCreation(
  CameraBackgroundSelection selection,
) async {
  if (kIsWeb || !selection.isEffectActive) {
    return;
  }
  final effects = ProtonVideoEffects.instance;
  await _applyReplacementImageIfNeeded(effects, selection);
}
