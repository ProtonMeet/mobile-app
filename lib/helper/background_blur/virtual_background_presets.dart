import 'package:flutter/services.dart';

/// Bundled still-image virtual backgrounds shipped with the app.
class VirtualBackgroundPreset {
  const VirtualBackgroundPreset({required this.id, required this.assetPath});

  final String id;
  final String assetPath;
}

/// Preset thumbnails and replacement images loaded from [VirtualBackgroundPreset.assetPath].
class VirtualBackgroundPresets {
  VirtualBackgroundPresets._();

  static const List<VirtualBackgroundPreset> all = [
    VirtualBackgroundPreset(
      id: 'office',
      assetPath: 'assets/images/virtual_backgrounds/office.jpg',
    ),
    VirtualBackgroundPreset(
      id: 'nature',
      assetPath: 'assets/images/virtual_backgrounds/nature.jpg',
    ),
    VirtualBackgroundPreset(
      id: 'abstract',
      assetPath: 'assets/images/virtual_backgrounds/abstract.jpg',
    ),
    VirtualBackgroundPreset(
      id: 'sky',
      assetPath: 'assets/images/virtual_backgrounds/sky.jpg',
    ),
    VirtualBackgroundPreset(
      id: 'warm',
      assetPath: 'assets/images/virtual_backgrounds/warm.jpg',
    ),
    VirtualBackgroundPreset(
      id: 'cool',
      assetPath: 'assets/images/virtual_backgrounds/cool.jpg',
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
