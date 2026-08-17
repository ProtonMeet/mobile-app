import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:proton_denoise/deepfilter_config.dart';
import 'package:proton_denoise/denoise_models.dart';
import 'package:proton_denoise/denoise_type.dart';
import 'package:proton_denoise/src/denoise_platform.dart';

/// Channel name for native mic denoise on flutter_webrtc local audio tracks.
@internal
const String kProtonDenoiseEffectsChannelName = 'me.proton.meet/denoise';

/// Internal method-channel client; use [ProtonDenoiseEffects] from app code.
@internal
class ProtonDenoiseChannel {
  ProtonDenoiseChannel()
    : _channel = const MethodChannel(kProtonDenoiseEffectsChannelName);

  final MethodChannel _channel;

  static String? _stringField(Object? value) => value?.toString();

  static bool _boolField(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return false;
  }

  static Map<String, dynamic> _detailsMap(Object? raw) {
    if (raw is! Map) {
      return const {};
    }
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<DenoiseDiagnosticEntry> _parseDiagnosticEntries(
    List<dynamic> raw,
  ) {
    final out = <DenoiseDiagnosticEntry>[];
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final map = entry.map((key, value) => MapEntry(key.toString(), value));
      final type = DenoiseType.fromId(_stringField(map['id']));
      if (type == null || type == DenoiseType.none) {
        continue;
      }
      out.add(
        DenoiseDiagnosticEntry(
          type: type,
          displayName: _stringField(map['displayName']) ?? type.displayName,
          isReady: _boolField(map['isReady']),
          details: _detailsMap(map['details']),
        ),
      );
    }
    return out;
  }

  static List<DenoiseTypeInfo> _parseTypeInfos(List<dynamic> raw) {
    final out = <DenoiseTypeInfo>[];
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final map = entry.map((key, value) => MapEntry(key.toString(), value));
      final type = DenoiseType.fromId(_stringField(map['id']));
      if (type == null || type == DenoiseType.none) {
        continue;
      }
      out.add(DenoiseTypeInfo(type: type, isReady: _boolField(map['isReady'])));
    }
    return out;
  }

  Future<List<DenoiseTypeInfo>> listDenoiseTypes() async {
    if (!isProtonDenoisePlatformSupported) {
      return const [];
    }
    try {
      final raw = await _channel.invokeMethod('listDenoiseTypes');
      if (raw is! List) {
        return const [];
      }
      return _parseTypeInfos(raw);
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      debugPrint('[ProtonDenoise] listDenoiseTypes failed: $e');
      return const [];
    }
  }

  Future<DenoiseDiagnosticsResult> diagnoseDenoiseWithStatus() async {
    if (!isProtonDenoisePlatformSupported) {
      return const DenoiseDiagnosticsResult(entries: []);
    }

    var note = 'diagnoseDenoise unavailable';
    try {
      final raw = await _channel.invokeMethod('diagnoseDenoise');
      if (raw is List) {
        final parsed = _parseDiagnosticEntries(raw);
        if (parsed.isNotEmpty) {
          return DenoiseDiagnosticsResult(entries: parsed);
        }
        note = 'diagnoseDenoise returned an empty list';
      } else if (raw == null) {
        note = 'diagnoseDenoise returned null';
      } else {
        note = 'diagnoseDenoise returned unexpected type ${raw.runtimeType}';
      }
    } on MissingPluginException {
      note =
          'diagnoseDenoise not registered — run a full native rebuild (not hot reload)';
    } on PlatformException catch (e) {
      note = 'diagnoseDenoise failed: ${e.code} ${e.message ?? ''}'.trim();
      debugPrint('[ProtonDenoise] $note');
    }

    final fallback = await listDenoiseTypes();
    if (fallback.isEmpty) {
      return DenoiseDiagnosticsResult(
        entries: const [],
        note: '$note; listDenoiseTypes also empty',
      );
    }

    return DenoiseDiagnosticsResult(
      entries: fallback
          .map(
            (info) => DenoiseDiagnosticEntry(
              type: info.type,
              displayName: info.type.displayName,
              isReady: info.isReady,
              details: {
                'source': 'listDenoiseTypes fallback',
                'diagnoseNote': note,
              },
            ),
          )
          .toList(),
      note: note,
      usedFallback: true,
    );
  }

  Future<List<DenoiseDiagnosticEntry>> diagnoseDenoise() async {
    final result = await diagnoseDenoiseWithStatus();
    return result.entries;
  }

  static DenoiseWarmUpResult? _parseWarmUpMap(Map<dynamic, dynamic> map) {
    final type = DenoiseType.fromId(_stringField(map['id']));
    if (type == null || type == DenoiseType.none) {
      return null;
    }
    return DenoiseWarmUpResult(
      type: type,
      warmUpOk: _boolField(map['warmUpOk']),
      warmUpMs: map['warmUpMs'] is num ? (map['warmUpMs'] as num).toInt() : 0,
      details: _detailsMap(map)
        ..remove('id')
        ..remove('warmUpOk')
        ..remove('warmUpMs'),
    );
  }

  Future<List<DenoiseWarmUpResult>> warmUpDenoise({DenoiseType? type}) async {
    if (!isProtonDenoisePlatformSupported) {
      return const [];
    }
    try {
      final args = type != null ? <String, dynamic>{'type': type.id} : null;
      final raw = await _channel.invokeMethod('warmUpDenoise', args);
      if (raw is Map) {
        final map = raw.map((key, value) => MapEntry(key.toString(), value));
        final one = _parseWarmUpMap(map);
        return one == null ? const [] : [one];
      }
      if (raw is List) {
        final out = <DenoiseWarmUpResult>[];
        for (final entry in raw) {
          if (entry is! Map) {
            continue;
          }
          final map = entry.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          final parsed = _parseWarmUpMap(map);
          if (parsed != null) {
            out.add(parsed);
          }
        }
        return out;
      }
      debugPrint(
        '[ProtonDenoise] warmUpDenoise unexpected response: ${raw.runtimeType}',
      );
      return const [];
    } on MissingPluginException {
      debugPrint(
        '[ProtonDenoise] warmUpDenoise not registered — rebuild native app',
      );
      return const [];
    } on PlatformException catch (e) {
      debugPrint('[ProtonDenoise] warmUpDenoise failed: $e');
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

  Future<void> attachDenoise({
    required String trackId,
    required DenoiseType type,
    double? deepFilterAttenLimDb,
  }) async {
    await _invokeAttachDetach(
      'attach',
      trackId,
      type,
      deepFilterAttenLimDb: deepFilterAttenLimDb,
    );
  }

  Future<void> setDeepFilterAttenLim({
    required String trackId,
    required double attenLimDb,
  }) async {
    if (!isProtonDenoisePlatformSupported) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setDeepFilterAttenLim', {
        'trackId': trackId,
        'attenLimDb': attenLimDb,
      });
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      debugPrint('[ProtonDenoise] setDeepFilterAttenLim failed: $e');
      rethrow;
    }
  }

  Future<void> detachDenoise({required String trackId}) async {
    await _invokeAttachDetach('detach', trackId, null);
  }

  Future<void> _invokeAttachDetach(
    String method,
    String trackId,
    DenoiseType? type, {
    double? deepFilterAttenLimDb,
  }) async {
    if (!isProtonDenoisePlatformSupported) {
      return;
    }
    final args = <String, dynamic>{'trackId': trackId};
    if (type != null) {
      args['type'] = type.id;
    }
    if (deepFilterAttenLimDb != null &&
        (type == DenoiseType.deepfilter || type == DenoiseType.deepfilter2)) {
      args['deepFilterAttenLimDb'] = deepFilterAttenLimDb.clamp(
        kDeepFilterMinAttenLimDb,
        kDeepFilterMaxAttenLimDb,
      );
    }
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      if (e.code == 'WEBRTC_NOT_READY') {
        debugPrint(
          '[ProtonDenoise] $method WEBRTC_NOT_READY for trackId=$trackId',
        );
        rethrow;
      }
      debugPrint('[ProtonDenoise] $method failed: $e');
      rethrow;
    }
  }
}
