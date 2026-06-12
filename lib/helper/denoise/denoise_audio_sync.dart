import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/managers/services/denoise_audio.service.dart';
import 'package:proton_denoise/proton_denoise.dart';

/// Attaches or detaches native mic denoise for the local audio track.
Future<void> syncLocalAudioDenoise({
  required Room room,
  required bool enabled,
  DenoiseType type = DenoiseType.rnnoise,
}) async {
  if (!ProtonDenoiseEffects.isSupported) {
    l.logger.d('[AudioDenoise] skipped: platform not supported');
    return;
  }
  try {
    final unleash = ManagerFactory()
        .get<DataProviderManager>()
        .unleashDataProvider;
    if (!unleash.isMeetAudioDenoise()) {
      l.logger.d('[AudioDenoise] skipped: parent feature flag off');
      return;
    }
    if (!_isTypeAllowedByFlags(unleash, type)) {
      l.logger.w('[AudioDenoise] skipped: ${type.id} disabled by flags');
      return;
    }
  } catch (e, st) {
    l.logger.w(
      '[AudioDenoise] skipped: unleash lookup failed',
      error: e,
      stackTrace: st,
    );
    return;
  }

  final lp = room.localParticipant;
  if (lp == null) {
    l.logger.d('[AudioDenoise] skipped: no local participant');
    return;
  }

  LocalAudioTrack? mic;
  for (final pub in lp.audioTrackPublications) {
    final t = pub.track;
    if (t is LocalAudioTrack) {
      mic = t;
      break;
    }
  }
  if (mic == null) {
    l.logger.d('[AudioDenoise] skipped: no local mic track');
    return;
  }

  final id = mic.mediaStreamTrack.id;
  if (id == null || id.isEmpty) {
    l.logger.d('[AudioDenoise] skipped: mic track id missing');
    return;
  }

  final effects = ProtonDenoiseEffects.instance;
  final ready = await effects.isTypeReady(type);
  if (!ready) {
    l.logger.w('[AudioDenoise] skipped: ${type.id} native not ready');
    return;
  }

  try {
    if (!enabled) {
      await effects.detachDenoise(trackId: id);
      l.logger.d('[AudioDenoise] detached trackId=$id');
      return;
    }
    if (DenoiseAudioService.isDeepFilterType(type)) {
      await DenoiseAudioService.instance.warmUpDeepFilterIfNeeded(type: type);
    }
    const maxAttempts = 5;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await effects.attachDenoise(trackId: id, type: type);
        l.logger.d(
          '[AudioDenoise] attached trackId=$id type=${type.id} '
          '(attempt $attempt)',
        );
        return;
      } on PlatformException catch (e) {
        if (e.code != 'WEBRTC_NOT_READY' || attempt == maxAttempts) {
          rethrow;
        }
        l.logger.d(
          '[AudioDenoise] attach WEBRTC_NOT_READY, retry $attempt/$maxAttempts',
        );
        await Future<void>.delayed(Duration(milliseconds: 80 * attempt));
      }
    }
  } catch (e, st) {
    l.logger.e('[AudioDenoise] sync failed: $e', error: e, stackTrace: st);
  }
}

bool _isTypeAllowedByFlags(UnleashDataProvider unleash, DenoiseType type) {
  switch (type) {
    case DenoiseType.rnnoise:
      return unleash.isMeetAudioDenoiseRnnoise();
    case DenoiseType.deepfilter:
    case DenoiseType.deepfilter2:
      return unleash.isMeetAudioDenoiseDeepfilter();
    case DenoiseType.dtlnRs:
      return unleash.isMeetAudioDenoiseDtlnRs();
    case DenoiseType.none:
      return false;
  }
}
