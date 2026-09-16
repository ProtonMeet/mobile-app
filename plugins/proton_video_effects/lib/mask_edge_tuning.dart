/// Shape of the segmentation mask before it is used to blend subject over background.
///
/// Honoured by the Apple and Android engines alike. Apple shapes the mask at frame resolution in
/// Core Image; Android shapes it in mask space and converts these frame-height fractions to mask
/// pixels, which is equivalent because the mask is a scaled copy of the frame. The practical
/// difference is quantisation: one Android mask pixel is a few frame pixels, so sub-pixel erode
/// radii round away instead of nudging the outline.
///
/// The pipeline applies these in a fixed order — upscale, erode, solidify, feather, gamma — and
/// the order is what keeps the knobs independent. Erosion moves the outline without reshaping the
/// ramp; solidify fixes interior translucency while leaving a narrow boundary ramp; the feather
/// then widens that ramp into the visible soft edge.
///
/// Defaults mirror `MeetBackgroundBlurMediaPipeEngine`; keep the two in sync.
class MaskEdgeTuning {
  const MaskEdgeTuning({
    this.featherHeightFraction = defaultFeatherHeightFraction,
    this.erodeHeightFraction = defaultErodeHeightFraction,
    this.solidifySlope = defaultSolidifySlope,
    this.solidifyMidpoint = defaultSolidifyMidpoint,
    this.foregroundGamma = defaultForegroundGamma,
  });

  static const MaskEdgeTuning standard = MaskEdgeTuning();

  static const double defaultFeatherHeightFraction = 0.010;
  static const double defaultErodeHeightFraction = 0.002;
  static const double defaultSolidifySlope = 6;
  static const double defaultSolidifyMidpoint = 0.55;
  static const double defaultForegroundGamma = 1;

  /// Past ~5% of frame height the edge stops reading as an edge at all.
  static const double maxEdgeFraction = 0.05;
  static const double minSolidifySlope = 1;
  static const double maxSolidifySlope = 16;
  static const double minSolidifyMidpoint = 0.2;
  static const double maxSolidifyMidpoint = 0.8;
  static const double minForegroundGamma = 0.5;
  static const double maxForegroundGamma = 3;

  /// Width of the soft fade at the outline, as a fraction of frame height. Higher is softer.
  final double featherHeightFraction;

  /// How far the outline is pulled inward, as a fraction of frame height.
  ///
  /// Also the main lever against motion artefacts: the mask lags the camera by roughly a frame,
  /// so a fast-moving limb leaves the mask claiming foreground where the limb no longer is, and
  /// the real background shows through there. Eroding harder trims that ghost, at the cost of
  /// thin detail like stray hair.
  final double erodeHeightFraction;

  /// Steepness of the confidence-to-coverage response. 1.0 disables the step.
  ///
  /// Vision reports confidence rather than coverage, so the interior of the subject can sit below
  /// 1.0 and blend as translucent. Raising this makes the body opaque sooner; too high starts
  /// pulling in the uncertain fringe around it.
  final double solidifySlope;

  /// Confidence treated as the silhouette boundary. Lower grows the subject, higher shrinks it.
  final double solidifyMidpoint;

  /// Gamma on the finished mask. Above 1.0 pushes uncertain values toward background so objects
  /// leak in less, at the cost of steepening the ramp and eating some of the feather's softness.
  final double foregroundGamma;

  static double _clamp(double value, double min, double max) =>
      value.clamp(min, max);

  MaskEdgeTuning copyWith({
    double? featherHeightFraction,
    double? erodeHeightFraction,
    double? solidifySlope,
    double? solidifyMidpoint,
    double? foregroundGamma,
  }) {
    return MaskEdgeTuning(
      featherHeightFraction:
          featherHeightFraction ?? this.featherHeightFraction,
      erodeHeightFraction: erodeHeightFraction ?? this.erodeHeightFraction,
      solidifySlope: solidifySlope ?? this.solidifySlope,
      solidifyMidpoint: solidifyMidpoint ?? this.solidifyMidpoint,
      foregroundGamma: foregroundGamma ?? this.foregroundGamma,
    );
  }

  Map<String, dynamic> toMethodChannelArgs() {
    return <String, dynamic>{
      'maskFeatherHeightFraction': _clamp(
        featherHeightFraction,
        0,
        maxEdgeFraction,
      ),
      'maskErodeHeightFraction': _clamp(
        erodeHeightFraction,
        0,
        maxEdgeFraction,
      ),
      'maskSolidifySlope': _clamp(
        solidifySlope,
        minSolidifySlope,
        maxSolidifySlope,
      ),
      'maskSolidifyMidpoint': _clamp(
        solidifyMidpoint,
        minSolidifyMidpoint,
        maxSolidifyMidpoint,
      ),
      'maskForegroundGamma': _clamp(
        foregroundGamma,
        minForegroundGamma,
        maxForegroundGamma,
      ),
    };
  }

  static MaskEdgeTuning fromMethodChannelArgs(Map<dynamic, dynamic> args) {
    double read(String key, double fallback) {
      final value = args[key];
      return value is num ? value.toDouble() : fallback;
    }

    return MaskEdgeTuning(
      featherHeightFraction: read(
        'maskFeatherHeightFraction',
        defaultFeatherHeightFraction,
      ),
      erodeHeightFraction: read(
        'maskErodeHeightFraction',
        defaultErodeHeightFraction,
      ),
      solidifySlope: read('maskSolidifySlope', defaultSolidifySlope),
      solidifyMidpoint: read('maskSolidifyMidpoint', defaultSolidifyMidpoint),
      foregroundGamma: read('maskForegroundGamma', defaultForegroundGamma),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MaskEdgeTuning &&
        other.featherHeightFraction == featherHeightFraction &&
        other.erodeHeightFraction == erodeHeightFraction &&
        other.solidifySlope == solidifySlope &&
        other.solidifyMidpoint == solidifyMidpoint &&
        other.foregroundGamma == foregroundGamma;
  }

  @override
  int get hashCode => Object.hash(
    featherHeightFraction,
    erodeHeightFraction,
    solidifySlope,
    solidifyMidpoint,
    foregroundGamma,
  );

  @override
  String toString() {
    return 'MaskEdgeTuning(feather: $featherHeightFraction, '
        'erode: $erodeHeightFraction, solidifySlope: $solidifySlope, '
        'solidifyMidpoint: $solidifyMidpoint, gamma: $foregroundGamma)';
  }
}
