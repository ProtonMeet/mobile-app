import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import 'src/denoise_platform.dart';
import 'src/denoise_type.dart';

/// Method channel for native mic denoise on flutter_webrtc local audio tracks.
const String kProtonDenoiseEffectsChannelName = 'me.proton.meet/denoise';

/// Metadata for a denoise algorithm shown in settings UI.
class DenoiseTypeInfo {
  const DenoiseTypeInfo({required this.type, required this.isReady});

  final DenoiseType type;
  final bool isReady;
}

class ProtonDenoiseChannel {
  ProtonDenoiseChannel()
    : _channel = const MethodChannel(kProtonDenoiseEffectsChannelName);

  final MethodChannel _channel;

  /// Denoise kinds the native layer knows about (ready or not).
  Future<List<DenoiseTypeInfo>> listDenoiseTypes() async {
    if (!isProtonDenoisePlatformSupported) {
      return const [];
    }
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'listDenoiseTypes',
      );
      if (raw == null) {
        return const [];
      }
      final out = <DenoiseTypeInfo>[];
      for (final entry in raw) {
        if (entry is! Map) {
          continue;
        }
        final id = entry['id'] as String?;
        final type = DenoiseType.fromId(id);
        if (type == null || type == DenoiseType.none) {
          continue;
        }
        out.add(
          DenoiseTypeInfo(
            type: type,
            isReady: entry['isReady'] as bool? ?? false,
          ),
        );
      }
      return out;
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      debugPrint('[ProtonDenoise] listDenoiseTypes failed: $e');
      return const [];
    }
  }

  Future<bool> isTypeReady(DenoiseType type) async {
    if (!isProtonDenoisePlatformSupported || type == DenoiseType.none) {
      return false;
    }
    try {
      final ready = await _channel.invokeMethod<bool>('isTypeReady', {
        'type': type.id,
      });
      return ready ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> attach({
    required String trackId,
    required DenoiseType type,
  }) async {
    await _invokeAttachDetach('attach', trackId, type);
  }

  Future<void> detach({required String trackId}) async {
    await _invokeAttachDetach('detach', trackId, null);
  }

  Future<void> _invokeAttachDetach(
    String method,
    String trackId,
    DenoiseType? type,
  ) async {
    if (!isProtonDenoisePlatformSupported) {
      return;
    }
    final args = <String, dynamic>{'trackId': trackId};
    if (type != null) {
      args['type'] = type.id;
    }
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      if (e.code == 'WEBRTC_NOT_READY') {
        return;
      }
      debugPrint('[ProtonDenoise] $method failed: $e');
      rethrow;
    }
  }
}
