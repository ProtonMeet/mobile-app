import 'package:flutter/foundation.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:proton_denoise/proton_denoise.dart';

/// App-level noise cancellation for local microphone capture.
class DenoiseAudioService {
  DenoiseAudioService._();
  static final DenoiseAudioService instance = DenoiseAudioService._();

  static const _deepFilterWarmupMinInterval = Duration(minutes: 30);

  UnleashDataProvider get _unleash =>
      ManagerFactory().get<DataProviderManager>().unleashDataProvider;

  DenoiseType _type = DenoiseType.rnnoise;
  bool _enabled = false;
  String? _attachedTrackId;
  Future<void>? _deepFilterWarmupInFlight;
  DateTime? _lastDeepFilterWarmupSuccess;

  bool get isEnabled => _enabled;
  DenoiseType get type => _type;

  /// iOS / macOS / Android when Unleash parent flag is on (not Windows/Linux yet).
  bool get isAvailable =>
      ProtonDenoiseEffects.isSupported && _unleash.isMeetAudioDenoise();

  /// Denoise algorithms the UI may show (Unleash sub-flags + native [isReady]).
  Future<List<DenoiseTypeInfo>> listAvailableTypesForUi() async {
    if (!isAvailable) {
      return const [];
    }
    final native = await ProtonDenoiseEffects.instance.listDenoiseTypes();
    return native.where((info) {
      if (!info.isReady) {
        return false;
      }
      switch (info.type) {
        case DenoiseType.rnnoise:
          return _unleash.isMeetAudioDenoiseRnnoise();
        case DenoiseType.deepfilter:
          return _unleash.isMeetAudioDenoiseDeepfilter();
        case DenoiseType.dtlnRs:
          return _unleash.isMeetAudioDenoiseDtlnRs();
        case DenoiseType.none:
          return false;
      }
    }).toList();
  }

  static bool isDeepFilterType(DenoiseType type) =>
      type == DenoiseType.deepfilter;

  /// Loads DeepFilter ONNX + runs df_create off the mic-attach critical path.
  /// Coalesces concurrent callers and skips if a recent warmup already succeeded.
  Future<void> warmUpDeepFilterIfNeeded({DenoiseType? type}) async {
    if (!isAvailable || !_unleash.isMeetAudioDenoiseDeepfilter()) {
      return;
    }
    final types = _deepFilterWarmupTargets(type);
    if (types.isEmpty) {
      return;
    }
    if (_deepFilterWarmupInFlight != null) {
      await _deepFilterWarmupInFlight;
      return;
    }
    final last = _lastDeepFilterWarmupSuccess;
    if (last != null &&
        DateTime.now().difference(last) < _deepFilterWarmupMinInterval) {
      return;
    }

    final future = _runDeepFilterWarmup(types);
    _deepFilterWarmupInFlight = future;
    try {
      await future;
    } finally {
      _deepFilterWarmupInFlight = null;
    }
  }

  List<DenoiseType> _deepFilterWarmupTargets(DenoiseType? type) {
    if (type != null) {
      if (!isDeepFilterType(type) || !_isTypeAllowedByFlags(type)) {
        return const [];
      }
      return [type];
    }
    if (!_isTypeAllowedByFlags(DenoiseType.deepfilter)) {
      return const [];
    }
    return const [DenoiseType.deepfilter];
  }

  Future<void> _runDeepFilterWarmup(List<DenoiseType> types) async {
    for (final denoiseType in types) {
      if (!await ProtonDenoiseEffects.instance.isTypeReady(denoiseType)) {
        continue;
      }
      try {
        final results = await ProtonDenoiseEffects.instance.warmUpDenoise(
          type: denoiseType,
        );
        final result = results.isNotEmpty ? results.first : null;
        if (result?.warmUpOk == true) {
          _lastDeepFilterWarmupSuccess = DateTime.now();
          l.logger.d(
            '[DenoiseAudioService] DeepFilter warmup ok '
            'type=${denoiseType.id} ms=${result!.warmUpMs}',
          );
        } else {
          l.logger.w(
            '[DenoiseAudioService] DeepFilter warmup failed type=${denoiseType.id}',
          );
        }
      } catch (e, st) {
        l.logger.w(
          '[DenoiseAudioService] DeepFilter warmup error: $e',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  /// Default in-call preference: enabled with [DenoiseType.rnnoise] when Unleash + native allow it.
  Future<({bool enabled, DenoiseType type})>
  resolveDefaultInCallPreference() async {
    const preferred = DenoiseType.rnnoise;
    if (!isAvailable) {
      return (enabled: false, type: preferred);
    }
    final resolved = await resolveTypeForAttach(preferred);
    if (resolved == null) {
      return (enabled: false, type: preferred);
    }
    return (enabled: true, type: resolved);
  }

  /// Picks [preferred] when allowed + ready, otherwise the first UI-visible type.
  Future<DenoiseType?> resolveTypeForAttach(DenoiseType preferred) async {
    final available = await listAvailableTypesForUi();
    if (available.isEmpty) {
      return null;
    }
    for (final info in available) {
      if (info.type == preferred) {
        return preferred;
      }
    }
    return available.first.type;
  }

  void setType(DenoiseType type) {
    _type = type;
  }

  /// Attach denoise on the local mic [trackId] (flutter_webrtc / LiveKit).
  Future<void> setEnabled({
    required bool enabled,
    String? trackId,
    DenoiseType? type,
  }) async {
    if (!isAvailable) {
      debugPrint('[DenoiseAudioService] Denoise not supported or flag off');
      return;
    }
    if (type != null) {
      _type = type;
    }
    if (enabled && (trackId == null || trackId.isEmpty)) {
      debugPrint('[DenoiseAudioService] trackId required to enable denoise');
      return;
    }
    final typeUnchanged = type == null;
    if (_enabled == enabled && _attachedTrackId == trackId && typeUnchanged) {
      return;
    }

    if (_enabled && _attachedTrackId != null) {
      await _detachCurrent();
    }

    if (!enabled) {
      _enabled = false;
      _attachedTrackId = null;
      return;
    }

    if (!_isTypeAllowedByFlags(_type)) {
      debugPrint(
        '[DenoiseAudioService] Denoise type ${_type.id} disabled by flags',
      );
      return;
    }

    final ready = await ProtonDenoiseEffects.instance.isTypeReady(_type);
    if (!ready) {
      debugPrint(
        '[DenoiseAudioService] ${_type.displayName} not ready on this platform',
      );
      return;
    }

    await ProtonDenoiseEffects.instance.attachDenoise(
      trackId: trackId!,
      type: _type,
    );
    _enabled = true;
    _attachedTrackId = trackId;
  }

  bool _isTypeAllowedByFlags(DenoiseType type) {
    switch (type) {
      case DenoiseType.rnnoise:
        return _unleash.isMeetAudioDenoiseRnnoise();
      case DenoiseType.deepfilter:
        return _unleash.isMeetAudioDenoiseDeepfilter();
      case DenoiseType.dtlnRs:
        return _unleash.isMeetAudioDenoiseDtlnRs();
      case DenoiseType.none:
        return false;
    }
  }

  Future<void> _detachCurrent() async {
    final id = _attachedTrackId;
    if (id != null) {
      await ProtonDenoiseEffects.instance.detachDenoise(trackId: id);
    }
    _enabled = false;
    _attachedTrackId = null;
  }

  Future<void> dispose() async {
    await _detachCurrent();
  }
}
