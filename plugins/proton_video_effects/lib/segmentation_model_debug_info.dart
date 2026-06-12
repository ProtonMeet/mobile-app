import 'segmentation_model_preference.dart';

/// Native segmenter state for debug UI.
class SegmentationModelDebugInfo {
  const SegmentationModelDebugInfo({
    required this.model,
    required this.backend,
    required this.forced,
    required this.supported,
  });

  final SegmentationModelPreference? model;
  final String backend;
  final bool forced;
  final bool supported;

  static SegmentationModelDebugInfo fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const SegmentationModelDebugInfo(
        model: null,
        backend: 'unknown',
        forced: false,
        supported: false,
      );
    }
    return SegmentationModelDebugInfo(
      model: segmentationModelPreferenceFromChannelId(map['model'] as String?),
      backend: map['backend'] as String? ?? 'unknown',
      forced: map['forced'] as bool? ?? false,
      supported: map['supported'] as bool? ?? false,
    );
  }
}
