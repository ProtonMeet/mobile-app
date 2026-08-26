import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:meet/helper/extension/platform.extension.dart';

/// Result of picking a custom virtual background image.
class VirtualBackgroundPickResult {
  const VirtualBackgroundPickResult({
    this.filePath,
    this.bytes,
    this.displayName,
  });

  final String? filePath;
  final Uint8List? bytes;
  final String? displayName;

  bool get isEmpty =>
      (filePath == null || filePath!.isEmpty) &&
      (bytes == null || bytes!.isEmpty);
}

/// Cross-platform image picker for custom virtual backgrounds.
class VirtualBackgroundImagePicker {
  VirtualBackgroundImagePicker._();

  static final ImagePicker _imagePicker = ImagePicker();
  static const _imageTypeGroup = XTypeGroup(
    label: 'images',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic'],
  );

  static Future<VirtualBackgroundPickResult?> pick() async {
    if (kIsWeb) {
      return null;
    }
    if (macOS) {
      return _pickWithFileSelector();
    }
    return _pickWithImagePicker();
  }

  static Future<VirtualBackgroundPickResult?> _pickWithImagePicker() async {
    try {
      final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (picked == null) {
        return null;
      }
      final path = picked.path;
      if (path.isNotEmpty) {
        return VirtualBackgroundPickResult(
          filePath: path,
          displayName: picked.name,
        );
      }
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      return VirtualBackgroundPickResult(
        bytes: bytes,
        displayName: picked.name,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<VirtualBackgroundPickResult?> _pickWithFileSelector() async {
    try {
      final file = await openFile(acceptedTypeGroups: const [_imageTypeGroup]);
      if (file == null) {
        return null;
      }
      final path = file.path;
      if (path.isNotEmpty) {
        return VirtualBackgroundPickResult(
          filePath: path,
          displayName: file.name,
        );
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      return VirtualBackgroundPickResult(
        bytes: bytes,
        displayName: file.name,
      );
    } catch (_) {
      return null;
    }
  }
}
