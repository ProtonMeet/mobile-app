import 'camera_background_mode.dart';
import 'mask_edge_tuning.dart';

/// Tunable parameters for native camera background blur.
///
/// iOS and macOS use Gaussian blur (σ); Android maps σ to box-blur radius.
class BackgroundBlurConfig {
  const BackgroundBlurConfig({
    this.mode = CameraBackgroundMode.blur,
    this.blurSigma = defaultBlurSigma,
    this.backgroundObscureOpacity = defaultObscureOpacity,
    this.maskEdge = MaskEdgeTuning.standard,
    this.synchronousSegmentation = false,
    this.replacementImagePath,
  });

  static const double defaultBlurSigma = 128;
  static const double defaultObscureOpacity = 0.1;
  static const double minBlurSigma = 4;
  static const double maxBlurSigma = 256;

  /// Still-image virtual backgrounds (bundled presets + user gallery).
  static const bool replacementBackgroundEnabled = true;

  final CameraBackgroundMode mode;
  final double blurSigma;
  final double backgroundObscureOpacity;

  /// How the segmentation mask is shaped before blending. Apple platforms only.
  final MaskEdgeTuning maskEdge;

  /// Segment inline on the capture thread so each frame gets its own mask. Apple platforms only.
  ///
  /// Removes the roughly one-frame lag that makes a waving arm tear a hole in the background,
  /// because the mask no longer describes an older frame. In exchange, inference blocks video
  /// capture, so any spike past the frame period drops captured frames. Debug/experimental —
  /// leave off in production until the latency headroom is proven on the slowest target device.
  final bool synchronousSegmentation;

  final String? replacementImagePath;

  static double clampBlurSigma(double sigma) =>
      sigma.clamp(minBlurSigma, maxBlurSigma);

  static double clampObscureOpacity(double opacity) => opacity.clamp(0, 1);

  BackgroundBlurConfig copyWith({
    CameraBackgroundMode? mode,
    double? blurSigma,
    double? backgroundObscureOpacity,
    MaskEdgeTuning? maskEdge,
    bool? synchronousSegmentation,
    String? replacementImagePath,
    bool clearReplacementImagePath = false,
  }) {
    return BackgroundBlurConfig(
      mode: mode ?? this.mode,
      blurSigma: blurSigma ?? this.blurSigma,
      backgroundObscureOpacity:
          backgroundObscureOpacity ?? this.backgroundObscureOpacity,
      maskEdge: maskEdge ?? this.maskEdge,
      synchronousSegmentation:
          synchronousSegmentation ?? this.synchronousSegmentation,
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
      'synchronousSegmentation': synchronousSegmentation,
      ...maskEdge.toMethodChannelArgs(),
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
      maskEdge: MaskEdgeTuning.fromMethodChannelArgs(args),
      synchronousSegmentation: args['synchronousSegmentation'] == true,
      replacementImagePath: path is String && path.isNotEmpty ? path : null,
    );
  }
}
