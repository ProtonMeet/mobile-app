import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:proton_denoise/proton_denoise.dart';

/// Attaches or detaches native mic denoise for the local audio track.
Future<void> syncLocalAudioDenoise({
  required Room room,
  required bool enabled,
  DenoiseType type = DenoiseType.rnnoise,
}) async {
  if (!ProtonDenoiseEffects.isSupported) {
    return;
  }
  try {
    final unleash = ManagerFactory()
        .get<DataProviderManager>()
        .unleashDataProvider;
    if (!unleash.isMeetAudioDenoise()) {
      return;
    }
    if (!_isTypeAllowedByFlags(unleash, type)) {
      return;
    }
  } catch (_) {
    return;
  }

  final lp = room.localParticipant;
  if (lp == null) {
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
    return;
  }

  final id = mic.mediaStreamTrack.id;
  if (id == null || id.isEmpty) {
    return;
  }

  final effects = ProtonDenoiseEffects.instance;
  final ready = await effects.isTypeReady(type);
  if (!ready) {
    return;
  }

  try {
    if (!enabled) {
      await effects.detachDenoise(trackId: id);
      return;
    }
    await effects.attachDenoise(trackId: id, type: type);
  } catch (e, st) {
    l.logger.e('[AudioDenoise] sync failed: $e', error: e, stackTrace: st);
  }
}

bool _isTypeAllowedByFlags(UnleashDataProvider unleash, DenoiseType type) {
  switch (type) {
    case DenoiseType.rnnoise:
      return unleash.isMeetAudioDenoiseRnnoise();
    case DenoiseType.deepfilter:
      return unleash.isMeetAudioDenoiseDeepfilter();
    case DenoiseType.none:
      return false;
  }
}
