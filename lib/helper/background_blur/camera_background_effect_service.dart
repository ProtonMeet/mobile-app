import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/helper/background_blur/virtual_background_presets.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
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

    await _applyReplacementImageIfNeeded(effects, selection);

    final config = selection.toBlurConfig(
      replacementImagePath: selection.kind == CameraBackgroundEffectKind.custom
          ? selection.customImagePath
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

  await applyCameraBackgroundSelectionToTrack(trackId: id, selection: selection);
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
      await effects.setReplacementBackgroundImageBytes(
        bytes.buffer.asUint8List(),
      );
      return;
  }
}

/// Loads preset bytes for track processor creation when a bundled image is selected.
Future<Uint8List?> presetReplacementBytes(String? presetId) async {
  if (presetId == null || presetId.isEmpty) {
    return null;
  }
  final bytes = await VirtualBackgroundPresets.loadPresetBytes(presetId);
  return bytes?.buffer.asUint8List();
}

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
