import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/background_blur/camera_background_effect_service.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:proton_video_effects/proton_video_effects.dart';

/// Helper class for creating LocalVideoTrack instances
class LocalVideoTrackHelper {
  static CameraBackgroundSelection _effectiveSelection({
    required bool applyBackgroundBlur,
    required CameraBackgroundSelection backgroundSelection,
  }) {
    if (backgroundSelection.isEffectActive) {
      return backgroundSelection;
    }
    if (applyBackgroundBlur) {
      return const CameraBackgroundSelection.blur();
    }
    return const CameraBackgroundSelection.none();
  }

  static TrackProcessor<VideoProcessorOptions>?
  _processorWithOptionalUnleashBlur(
    TrackProcessor<VideoProcessorOptions>? processor, {
    required CameraBackgroundSelection selection,
  }) {
    if (processor != null) {
      return processor;
    }
    if (!selection.isEffectActive || kIsWeb) {
      return null;
    }
    try {
      final unleash = ManagerFactory()
          .get<DataProviderManager>()
          .unleashDataProvider;
      if (unleash.isMeetCameraBackgroundBlur()) {
        return ProtonVideoEffects.instance.createBlurTrackProcessor(
          config: resolveCameraBackgroundBlurConfig(selection),
        );
      }
    } catch (_) {}
    return null;
  }

  /// Creates a camera track with optional device or position.
  ///
  /// When [processor] is null, [backgroundSelection] or legacy [applyBackgroundBlur]
  /// controls native background effects when MeetCameraBackgroundBlur is enabled.
  static Future<LocalVideoTrack> cameraTrack({
    required VideoParameters parameters,
    MediaDevice? device,
    CameraPosition? position,
    TrackProcessor<VideoProcessorOptions>? processor,
    bool applyBackgroundBlur = false,
    CameraBackgroundSelection backgroundSelection =
        const CameraBackgroundSelection.none(),
  }) async {
    final selection = _effectiveSelection(
      applyBackgroundBlur: applyBackgroundBlur,
      backgroundSelection: backgroundSelection,
    );
    if (selection.isEffectActive) {
      await prepareCameraBackgroundSelectionForTrackCreation(selection);
    }
    final effectiveProcessor = _processorWithOptionalUnleashBlur(
      processor,
      selection: selection,
    );
    if (device != null) {
      return LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(
          deviceId: device.deviceId,
          params: parameters,
          processor: effectiveProcessor,
        ),
      );
    } else if (position != null) {
      return LocalVideoTrack.createCameraTrack(
        CameraCaptureOptions(
          cameraPosition: position,
          params: parameters,
          processor: effectiveProcessor,
        ),
      );
    }
    return LocalVideoTrack.createCameraTrack(
      CameraCaptureOptions(params: parameters, processor: effectiveProcessor),
    );
  }
}
