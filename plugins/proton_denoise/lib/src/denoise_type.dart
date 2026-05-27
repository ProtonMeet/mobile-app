/// Native audio denoise algorithms exposed to the UI.
enum DenoiseType {
  /// No processing (detach only).
  none('none', 'Off'),

  /// RNNoise — implemented on iOS/macOS (Android when native lib is linked).
  rnnoise('rnnoise', 'RNNoise'),

  /// DeepFilter — compiles and pass-through until the model ships.
  deepfilter('deepfilter', 'DeepFilter');

  const DenoiseType(this.id, this.displayName);

  /// Wire format for [ProtonDenoiseChannel] / native attach.
  final String id;

  /// Human-readable label for settings UI.
  final String displayName;

  static DenoiseType? fromId(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final type in DenoiseType.values) {
      if (type.id == id) {
        return type;
      }
    }
    return null;
  }

  /// Types the UI may list (excludes [none]).
  static List<DenoiseType> get selectableTypes => [
    DenoiseType.rnnoise,
    DenoiseType.deepfilter,
  ];
}

/// @deprecated Use [DenoiseType].
typedef DenoiseBackend = DenoiseType;
