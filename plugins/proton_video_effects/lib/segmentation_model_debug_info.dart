import 'segmentation_model_preference.dart';

/// Native segmenter state for debug UI.
class SegmentationModelDebugInfo {
  const SegmentationModelDebugInfo({
    required this.model,
    required this.backend,
    required this.forced,
    required this.supported,
    this.reason,
  });

  final SegmentationModelPreference? model;
  final String backend;
  final bool forced;
  final bool supported;

  /// Why effects are unusable, as reported by the native side.
  ///
  /// Null or empty when they work, or on platforms that do not report it.
  /// Diagnostic text, so it is deliberately not localised.
  final String? reason;

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
      reason: switch (map['reason']) {
        final String r when r.isNotEmpty => r,
        _ => null,
      },
    );
  }
}
