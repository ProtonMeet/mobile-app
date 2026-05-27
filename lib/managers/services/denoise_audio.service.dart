import 'package:flutter/foundation.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:proton_denoise/proton_denoise.dart';

/// App-level noise cancellation for local microphone capture.
class DenoiseAudioService {
  DenoiseAudioService._();
  static final DenoiseAudioService instance = DenoiseAudioService._();

  UnleashDataProvider get _unleash =>
      ManagerFactory().get<DataProviderManager>().unleashDataProvider;

  DenoiseType _type = DenoiseType.rnnoise;
  bool _enabled = false;
  String? _attachedTrackId;

  bool get isEnabled => _enabled;
  DenoiseType get type => _type;

  /// iOS / macOS / Android when Unleash parent flag is on (not Windows/Linux yet).
  bool get isAvailable =>
      ProtonDenoiseEffects.isSupported && _unleash.isMeetAudioDenoise();

  /// Denoise algorithms the UI may show (respects Unleash sub-flags + native readiness).
  Future<List<DenoiseTypeInfo>> listAvailableTypesForUi() async {
    if (!isAvailable) {
      return const [];
    }
    final native = await ProtonDenoiseEffects.instance.listDenoiseTypes();
    return native.where((info) {
      switch (info.type) {
        case DenoiseType.rnnoise:
          return _unleash.isMeetAudioDenoiseRnnoise();
        case DenoiseType.deepfilter:
          return _unleash.isMeetAudioDenoiseDeepfilter();
        case DenoiseType.none:
          return false;
      }
    }).toList();
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
