import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:proton_video_effects/proton_video_effects.dart';

/// Helper class for creating LocalVideoTrack instances
class LocalVideoTrackHelper {
  static TrackProcessor<VideoProcessorOptions>?
  _processorWithOptionalUnleashBlur(
    TrackProcessor<VideoProcessorOptions>? processor, {
    required bool applyBackgroundBlur,
  }) {
    if (processor != null) {
      return processor;
    }
    if (!applyBackgroundBlur || kIsWeb) {
      return null;
    }
    try {
      final unleash = ManagerFactory()
          .get<DataProviderManager>()
          .unleashDataProvider;
      if (unleash.isMeetCameraBackgroundBlur()) {
        return BackgroundBlurTrackProcessor();
      }
    } catch (_) {}
    return null;
  }

  /// Creates a camera track with optional device or position
  ///
  /// If [device] is provided, uses that device.
  /// If [position] is provided (and device is null), uses that camera position.
  /// Otherwise, uses the default camera.
  ///
  /// When [processor] is null, [applyBackgroundBlur] is true, and Unleash toggle
  /// MeetCameraBackgroundBlur is on (non-web), attaches [BackgroundBlurTrackProcessor].
  static Future<LocalVideoTrack> cameraTrack({
    required VideoParameters parameters,
    MediaDevice? device,
    CameraPosition? position,
    TrackProcessor<VideoProcessorOptions>? processor,
    bool applyBackgroundBlur = false,
  }) async {
    final effectiveProcessor = _processorWithOptionalUnleashBlur(
      processor,
      applyBackgroundBlur: applyBackgroundBlur,
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
