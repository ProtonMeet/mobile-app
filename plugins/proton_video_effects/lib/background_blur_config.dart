import 'camera_background_mode.dart';

/// Tunable parameters for native camera background blur.
///
/// iOS and macOS use Gaussian blur (σ); Android maps σ to box-blur radius.
class BackgroundBlurConfig {
  const BackgroundBlurConfig({
    this.mode = CameraBackgroundMode.blur,
    this.blurSigma = defaultBlurSigma,
    this.backgroundObscureOpacity = defaultObscureOpacity,
    this.replacementImagePath,
  });

  static const double defaultBlurSigma = 128;
  static const double defaultObscureOpacity = 0.1;
  static const double minBlurSigma = 4;
  static const double maxBlurSigma = 256;

  /// Still-image virtual backgrounds are not enabled yet.
  static const bool replacementBackgroundEnabled = false;

  final CameraBackgroundMode mode;
  final double blurSigma;
  final double backgroundObscureOpacity;
  final String? replacementImagePath;

  static double clampBlurSigma(double sigma) =>
      sigma.clamp(minBlurSigma, maxBlurSigma);

  static double clampObscureOpacity(double opacity) => opacity.clamp(0, 1);

  BackgroundBlurConfig copyWith({
    CameraBackgroundMode? mode,
    double? blurSigma,
    double? backgroundObscureOpacity,
    String? replacementImagePath,
    bool clearReplacementImagePath = false,
  }) {
    return BackgroundBlurConfig(
      mode: mode ?? this.mode,
      blurSigma: blurSigma ?? this.blurSigma,
      backgroundObscureOpacity:
          backgroundObscureOpacity ?? this.backgroundObscureOpacity,
      replacementImagePath: clearReplacementImagePath
          ? null
          : replacementImagePath ?? this.replacementImagePath,
    );
  }

  Map<String, dynamic> toMethodChannelArgs() {
    final effectiveMode = replacementBackgroundEnabled
        ? mode
        : CameraBackgroundMode.blur;
    final args = <String, dynamic>{
      'blurSigma': clampBlurSigma(blurSigma),
      'backgroundObscureOpacity': clampObscureOpacity(backgroundObscureOpacity),
      'backgroundMode': effectiveMode.channelId,
    };
    final path = replacementImagePath;
    if (effectiveMode == CameraBackgroundMode.replacementImage &&
        path != null &&
        path.isNotEmpty) {
      args['replacementImagePath'] = path;
    }
    return args;
  }

  static BackgroundBlurConfig? fromMethodChannelArgs(
    Map<dynamic, dynamic>? args,
  ) {
    if (args == null) {
      return null;
    }
    final sigma = args['blurSigma'];
    final obscure = args['backgroundObscureOpacity'];
    if (sigma is! num && obscure is! num) {
      return null;
    }
    final path = args['replacementImagePath'];
    return BackgroundBlurConfig(
      mode: cameraBackgroundModeFromChannelId(
        args['backgroundMode'] as String?,
      ),
      blurSigma: sigma is num
          ? clampBlurSigma(sigma.toDouble())
          : defaultBlurSigma,
      backgroundObscureOpacity: obscure is num
          ? clampObscureOpacity(obscure.toDouble())
          : defaultObscureOpacity,
      replacementImagePath: path is String && path.isNotEmpty ? path : null,
    );
  }
}
