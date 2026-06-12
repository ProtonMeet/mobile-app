/// Segmentation backend for camera background blur.
enum SegmentationModelPreference {
  /// Apple Vision — default on iOS and macOS.
  vision,

  /// MediaPipe landscape model — default on Android. (medium)
  landscape,

  /// MediaPipe square selfie model. (light)
  single,

  /// MediaPipe multiclass model (legacy; not exposed in production UI). (heavy)
  multiclass,
}

extension SegmentationModelPreferenceX on SegmentationModelPreference {
  String get channelId => name;
}

SegmentationModelPreference? segmentationModelPreferenceFromChannelId(
  String? id,
) => SegmentationModelPreference.values.asNameMap()[id];
