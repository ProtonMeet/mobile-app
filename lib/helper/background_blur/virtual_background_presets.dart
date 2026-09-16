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
      id: 'virtualBg01',
      asset: Assets.images.virtualBackgrounds.virtualBg01,
    ),
    VirtualBackgroundPreset(
      id: 'virtualBg02',
      asset: Assets.images.virtualBackgrounds.virtualBg02,
    ),
    VirtualBackgroundPreset(
      id: 'virtualBg03',
      asset: Assets.images.virtualBackgrounds.virtualBg03,
    ),
    VirtualBackgroundPreset(
      id: 'virtualBg04',
      asset: Assets.images.virtualBackgrounds.virtualBg04,
    ),
    VirtualBackgroundPreset(
      id: 'virtualBg05',
      asset: Assets.images.virtualBackgrounds.virtualBg05,
    ),
    VirtualBackgroundPreset(
      id: 'virtualBg06',
      asset: Assets.images.virtualBackgrounds.virtualBg06,
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
