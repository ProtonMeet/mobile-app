import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:meet/helper/background_blur/virtual_background_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider({required this.temporaryPath, required this.supportPath});

  final String temporaryPath;
  final String supportPath;

  @override
  Future<String?> getTemporaryPath() async => temporaryPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryRoot;
  late Directory supportRoot;
  late Directory storeDirectory;

  Uint8List bytes(int fill) => Uint8List.fromList(List.filled(8, fill));

  setUp(() {
    temporaryRoot = Directory.systemTemp.createTempSync('vb_store_tmp');
    supportRoot = Directory.systemTemp.createTempSync('vb_store_support');
    storeDirectory = Directory(p.join(supportRoot.path, 'virtual_background'));
    PathProviderPlatform.instance = _FakePathProvider(
      temporaryPath: temporaryRoot.path,
      supportPath: supportRoot.path,
    );
  });

  tearDown(() {
    for (final directory in [temporaryRoot, supportRoot]) {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
  });

  group('VirtualBackgroundStore', () {
    // The whole point of the store: a picked photo is personal data, so
    // re-picking must not leave the previous one behind.
    test('keeps exactly one file across repeated stores', () async {
      await VirtualBackgroundStore.store(bytes(1), displayName: 'a.jpg');
      await VirtualBackgroundStore.store(bytes(2), displayName: 'b.png');
      await VirtualBackgroundStore.store(bytes(3), displayName: 'c.webp');

      final entries = storeDirectory.listSync();
      expect(entries, hasLength(1));
      expect(p.extension(entries.single.path), '.webp');
      expect(File(entries.single.path).readAsBytesSync(), bytes(3));
    });

    test(
      'derives the extension from the picked name, defaulting to jpg',
      () async {
        final png = await VirtualBackgroundStore.store(
          bytes(1),
          displayName: 'shot.PNG',
        );
        expect(p.extension(png.path), '.png');

        final unknown = await VirtualBackgroundStore.store(
          bytes(1),
          displayName: 'shot.tiff',
        );
        expect(p.extension(unknown.path), '.jpg');

        final unnamed = await VirtualBackgroundStore.store(bytes(1));
        expect(p.extension(unnamed.path), '.jpg');
      },
    );

    test(
      'storeFile copies the image and removes the picker scratch copy',
      () async {
        final scratch = File(p.join(temporaryRoot.path, 'picked.jpg'))
          ..writeAsBytesSync(bytes(7));

        final stored = await VirtualBackgroundStore.storeFile(scratch);

        expect(stored.readAsBytesSync(), bytes(7));
        expect(p.isWithin(storeDirectory.path, stored.path), isTrue);
        expect(scratch.existsSync(), isFalse);
      },
    );

    // On macOS `file_selector` returns the user's original photo in place, so
    // deleting the source after copying would destroy their file.
    test(
      'storeFile never deletes a source outside the temporary directory',
      () async {
        final elsewhere = Directory.systemTemp.createTempSync('vb_store_orig');
        addTearDown(() => elsewhere.deleteSync(recursive: true));
        final original = File(p.join(elsewhere.path, 'IMG_1234.png'))
          ..writeAsBytesSync(bytes(9));

        final stored = await VirtualBackgroundStore.storeFile(original);

        expect(original.existsSync(), isTrue);
        expect(stored.readAsBytesSync(), bytes(9));
        expect(p.extension(stored.path), '.png');
      },
    );

    test(
      'clear removes the stored image and tolerates an empty store',
      () async {
        await VirtualBackgroundStore.store(bytes(1), displayName: 'a.jpg');
        expect(storeDirectory.existsSync(), isTrue);

        await VirtualBackgroundStore.clear();
        expect(storeDirectory.existsSync(), isFalse);

        await VirtualBackgroundStore.clear();
        expect(storeDirectory.existsSync(), isFalse);
      },
    );
  });
}
