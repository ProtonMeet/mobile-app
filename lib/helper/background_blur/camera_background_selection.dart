import 'package:equatable/equatable.dart';
import 'package:proton_video_effects/proton_video_effects.dart';

/// Which camera background effect the user selected.
enum CameraBackgroundEffectKind { none, blur, preset, custom }

/// User-facing camera background choice for prejoin and in-call video.
class CameraBackgroundSelection extends Equatable {
  const CameraBackgroundSelection._({
    required this.kind,
    this.presetId,
    this.customImagePath,
  });

  const CameraBackgroundSelection.none()
    : this._(kind: CameraBackgroundEffectKind.none);

  const CameraBackgroundSelection.blur()
    : this._(kind: CameraBackgroundEffectKind.blur);

  const CameraBackgroundSelection.preset(String id)
    : this._(kind: CameraBackgroundEffectKind.preset, presetId: id);

  const CameraBackgroundSelection.custom(String path)
    : this._(kind: CameraBackgroundEffectKind.custom, customImagePath: path);

  final CameraBackgroundEffectKind kind;
  final String? presetId;
  final String? customImagePath;

  bool get isEffectActive => kind != CameraBackgroundEffectKind.none;

  BackgroundBlurConfig toBlurConfig({String? replacementImagePath}) {
    switch (kind) {
      case CameraBackgroundEffectKind.none:
        return const BackgroundBlurConfig();
      case CameraBackgroundEffectKind.blur:
        return const BackgroundBlurConfig(mode: CameraBackgroundMode.blur);
      case CameraBackgroundEffectKind.preset:
      case CameraBackgroundEffectKind.custom:
        final path = replacementImagePath ?? customImagePath;
        return BackgroundBlurConfig(
          mode: CameraBackgroundMode.replacementImage,
          replacementImagePath: path,
        );
    }
  }

  CameraBackgroundSelection copyWith({
    CameraBackgroundEffectKind? kind,
    String? presetId,
    String? customImagePath,
    bool clearPresetId = false,
    bool clearCustomImagePath = false,
  }) {
    return CameraBackgroundSelection._(
      kind: kind ?? this.kind,
      presetId: clearPresetId ? null : presetId ?? this.presetId,
      customImagePath: clearCustomImagePath
          ? null
          : customImagePath ?? this.customImagePath,
    );
  }

  @override
  List<Object?> get props => [kind, presetId, customImagePath];
}
