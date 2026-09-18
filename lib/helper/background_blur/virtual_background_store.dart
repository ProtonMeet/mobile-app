import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk home for the user's custom virtual background.
///
/// A picked photo is personal data, so exactly one copy is kept and it lives in
/// a directory this class owns: storing a new background erases the previous
/// one, and [clear] removes it outright. Without this the platform picker's
/// cache copies pile up unbounded — nothing else deletes them.
///
/// Application support rather than the temporary directory: iOS reaps `tmp/`
/// under memory pressure and between launches, and the picker hands back a
/// `tmp/` path. Losing the file mid-call degrades the effect to blur with
/// nothing to explain why, so the copy is kept somewhere the system will not
/// delete behind us and this class does the deleting instead.
class VirtualBackgroundStore {
  VirtualBackgroundStore._();

  static const _directoryName = 'virtual_background';
  static const _fileStem = 'background';
  static const _allowedExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.heic'};

  /// Distinguishes one stored background from the next; see [store].
  static int _storeSequence = 0;

  /// Stores [bytes] as the custom background, replacing any previous one.
  ///
  /// The name carries a sequence number because the path is the whole identity
  /// of a custom selection: `CameraBackgroundSelection` compares by value, so
  /// with a fixed name picking a *different* photo produced a selection equal
  /// to the current one and every caller that skips no-op changes dropped it —
  /// the user picked an image and nothing happened. Only one file is ever on
  /// disk regardless, since [_resetDirectory] empties the directory first.
  static Future<File> store(Uint8List bytes, {String? displayName}) async {
    final directory = await _resetDirectory();
    final name =
        '${_fileStem}_${_storeSequence++}${_extensionFor(displayName)}';
    final file = File(p.join(directory.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Copies [source] into the store, then removes the picker's scratch copy.
  static Future<File> storeFile(File source, {String? displayName}) async {
    final bytes = await source.readAsBytes();
    final stored = await store(
      bytes,
      displayName: displayName ?? p.basename(source.path),
    );
    await _deletePickerScratchCopy(source);
    return stored;
  }

  /// Removes the stored background. Safe to call when nothing is stored.
  static Future<void> clear() async {
    try {
      final directory = await _directory();
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[VirtualBackgroundStore] clear failed: $e');
    }
  }

  static Future<Directory> _directory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, _directoryName));
  }

  static Future<Directory> _resetDirectory() async {
    final directory = await _directory();
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
    await directory.create(recursive: true);
    return directory;
  }

  /// Deletes the file the picker copied into our sandbox so it is not left
  /// behind alongside our own copy.
  ///
  /// Only ever touches paths inside the temporary directory, which is where
  /// both `image_picker_ios` and `image_picker_android` stage their copies. On
  /// macOS `file_selector` returns the user's original photo where it sits, and
  /// deleting that would destroy their file.
  static Future<void> _deletePickerScratchCopy(File source) async {
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      final root = p.normalize(temporaryDirectory.absolute.path);
      final path = p.normalize(source.absolute.path);
      if (!p.isWithin(root, path)) {
        return;
      }
      if (source.existsSync()) {
        await source.delete();
      }
    } catch (e) {
      debugPrint('[VirtualBackgroundStore] scratch cleanup failed: $e');
    }
  }

  /// Preserves the real container format so the native decoder is not handed a
  /// PNG or HEIC behind a `.jpg` name.
  static String _extensionFor(String? displayName) {
    if (displayName == null) {
      return '.jpg';
    }
    final extension = p.extension(displayName).toLowerCase();
    return _allowedExtensions.contains(extension) ? extension : '.jpg';
  }
}
