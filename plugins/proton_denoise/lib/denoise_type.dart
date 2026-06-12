/// Native audio denoise algorithms exposed to the UI.
enum DenoiseType {
  /// No processing (detach only).
  none('none', 'Off'),

  /// RNNoise — iOS, macOS, Android, Linux, Windows when native lib is linked.
  rnnoise('rnnoise', 'RNNoise'),

  /// DeepFilterNet3 — iOS when prebuilt framework is vendored.
  deepfilter('deepfilter', 'DeepFilter 3'),

  /// DeepFilterNet2 — requires libDF v0.3.1; not shipped on iOS yet.
  deepfilter2('deepfilter2', 'DeepFilter 2'),

  /// DTLN (dtln-rs) — TFLite model; native lib must be linked per platform.
  dtlnRs('dtln-rs', 'DTLN');

  const DenoiseType(this.id, this.displayName);

  /// Wire format for native attach (`me.proton.meet/denoise`).
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
    DenoiseType.dtlnRs,
  ];
}
