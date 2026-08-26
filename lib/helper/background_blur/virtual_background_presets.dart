import 'package:flutter/services.dart';
import 'package:meet/constants/assets.gen.dart';

/// Bundled still-image virtual backgrounds shipped with the app.
class VirtualBackgroundPreset {
  const VirtualBackgroundPreset({required this.id, required this.asset});

  final String id;
  final AssetGenImage asset;

  String get assetPath => asset.path;
}

/// Preset thumbnails and replacement images loaded from [VirtualBackgroundPreset.asset].
class VirtualBackgroundPresets {
  VirtualBackgroundPresets._();

  static final List<VirtualBackgroundPreset> all = [
    VirtualBackgroundPreset(
      id: 'proton',
      asset: Assets.images.virtualBackgrounds.a00Proton,
    ),
    VirtualBackgroundPreset(
      id: 'office',
      asset: Assets.images.virtualBackgrounds.a01ModernOfficeV2WorkingOffice,
    ),
    VirtualBackgroundPreset(
      id: 'mountain',
      asset: Assets.images.virtualBackgrounds.a02MountainLandscape,
    ),
    VirtualBackgroundPreset(
      id: 'abstract',
      asset: Assets.images.virtualBackgrounds.a03AbstractNaturalTexture,
    ),
    VirtualBackgroundPreset(
      id: 'beach',
      asset: Assets.images.virtualBackgrounds.a04BeachLandscapeV2Happy,
    ),
    VirtualBackgroundPreset(
      id: 'coffee',
      asset: Assets.images.virtualBackgrounds.a05CoffeePlaceV2Furnished,
    ),
  ];

  static VirtualBackgroundPreset? byId(String? id) {
    if (id == null || id.isEmpty) {
      return null;
    }
    for (final preset in all) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  static Future<ByteData?> loadPresetBytes(String presetId) async {
    final preset = byId(presetId);
    if (preset == null) {
      return null;
    }
    try {
      return await rootBundle.load(preset.assetPath);
    } catch (_) {
      return null;
    }
  }
}
