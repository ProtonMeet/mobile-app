import 'package:flutter_test/flutter_test.dart';
import 'package:meet/helper/background_blur/virtual_background_presets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VirtualBackgroundPresets', () {
    test('ids are unique', () {
      final ids = VirtualBackgroundPresets.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('byId round-trips every preset and rejects unknown ids', () {
      for (final preset in VirtualBackgroundPresets.all) {
        expect(VirtualBackgroundPresets.byId(preset.id), same(preset));
      }
      expect(VirtualBackgroundPresets.byId('not-a-preset'), isNull);
      expect(VirtualBackgroundPresets.byId(null), isNull);
      expect(VirtualBackgroundPresets.byId(''), isNull);
    });

    // loadPresetBytes swallows bundle errors and returns null, which would make
    // a renamed or unbundled asset silently fall back to an unchanged
    // background instead of failing loudly.
    test('every preset asset is bundled and decodable', () async {
      for (final preset in VirtualBackgroundPresets.all) {
        final bytes = await VirtualBackgroundPresets.loadPresetBytes(preset.id);
        expect(
          bytes,
          isNotNull,
          reason: 'missing asset for "${preset.id}": ${preset.assetPath}',
        );
        expect(bytes!.lengthInBytes, greaterThan(0));
      }
    });

    test('loadPresetBytes returns null for an unknown id', () async {
      expect(await VirtualBackgroundPresets.loadPresetBytes('nope'), isNull);
    });
  });
}
