import 'dart:async';

import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/managers/services/denoise_audio.service.dart';
import 'package:proton_denoise/proton_denoise.dart';

/// Why a denoise attach is being scheduled — controls settle delay (web parity).
enum DenoiseAttachReason {
  /// Mute/unmute or first attach after mic enable.
  toggle,

  /// Mic input device changed — longer settle for track replacement.
  deviceChange,

  /// User toggled denoise in settings — attach immediately.
  settings,
}

/// Manages native mic denoise attach/detach lifecycle (mirrors web `useAudioToggle`).
///
/// Key behaviors:
/// - Schedules attach after mic toggle / device change so the WebRTC track is live.
/// - Tracks attached track id to skip redundant re-attaches.
/// - Generation counter invalidates in-flight attaches after abandon.
/// - Does not detach on mute — only on explicit disable or track replacement.
class DenoiseAudioLifecycle {
  DenoiseAudioLifecycle._();
  static final DenoiseAudioLifecycle instance = DenoiseAudioLifecycle._();

  static const _settleDelay = Duration(milliseconds: 600);
  static const _deviceChangeDelay = Duration(milliseconds: 1500);
  static const _attachTimeout = Duration(milliseconds: 3000);
  static const _maxAttachAttempts = 5;

  int _generation = 0;
  Timer? _pendingAttach;
  String? _attachedTrackId;
  bool _syncInProgress = false;

  String? get attachedTrackId => _attachedTrackId;

  void cancelPendingAttach() {
    _pendingAttach?.cancel();
    _pendingAttach = null;
  }

  /// Clears refs without detaching — used when the track is about to be replaced.
  void abandon() {
    _generation++;
    cancelPendingAttach();
    l.logger.d(
      '[AudioDenoise] abandon generation=$_generation trackId=$_attachedTrackId',
    );
    _attachedTrackId = null;
  }

  void dispose() {
    abandon();
    _syncInProgress = false;
  }

  Duration _delayFor(DenoiseAttachReason reason) => switch (reason) {
    DenoiseAttachReason.toggle => _settleDelay,
    DenoiseAttachReason.deviceChange => _deviceChangeDelay,
    DenoiseAttachReason.settings => Duration.zero,
  };

  /// Schedule or run denoise attach. Pass [enabled: false] to detach immediately.
  Future<void> sync({
    required Room room,
    required bool enabled,
    DenoiseType type = DenoiseType.rnnoise,
    DenoiseAttachReason reason = DenoiseAttachReason.settings,
  }) async {
    if (!enabled) {
      cancelPendingAttach();
      await _detachCurrent(room);
      return;
    }

    final delay = _delayFor(reason);
    if (delay == Duration.zero) {
      cancelPendingAttach();
      await _attachNow(room: room, type: type);
      return;
    }

    cancelPendingAttach();
    final gen = _generation;
    l.logger.d(
      '[AudioDenoise] schedule attach delay=${delay.inMilliseconds}ms',
    );
    final completer = Completer<void>();
    _pendingAttach = Timer(delay, () async {
      _pendingAttach = null;
      if (_generation != gen) {
        completer.complete();
        return;
      }
      try {
        await _attachNow(room: room, type: type);
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
    });
    return completer.future;
  }

  /// After mic unmute or device change: attach only if track id changed or not attached.
  Future<void> syncIfNeeded({
    required Room room,
    required bool enabled,
    required DenoiseType type,
    DenoiseAttachReason reason = DenoiseAttachReason.toggle,
  }) async {
    if (!enabled) {
      return;
    }
    final mic = _findLocalMic(room);
    final trackId = mic?.mediaStreamTrack.id;
    if (trackId != null && trackId.isNotEmpty && trackId == _attachedTrackId) {
      l.logger.d('[AudioDenoise] processor survived trackId=$trackId');
      return;
    }
    if (_attachedTrackId != null && trackId != _attachedTrackId) {
      abandon();
    }
    await sync(room: room, enabled: true, type: type, reason: reason);
  }

  Future<void> _detachCurrent(Room room) async {
    final id = _attachedTrackId;
    if (id == null) {
      return;
    }
    try {
      await ProtonDenoiseEffects.instance.detachDenoise(trackId: id);
      l.logger.d('[AudioDenoise] detached trackId=$id');
    } catch (e, st) {
      l.logger.e('[AudioDenoise] detach failed: $e', error: e, stackTrace: st);
    } finally {
      _attachedTrackId = null;
    }
  }

  Future<void> _attachNow({
    required Room room,
    required DenoiseType type,
  }) async {
    if (_syncInProgress) {
      l.logger.d('[AudioDenoise] attach skipped: sync in progress');
      return;
    }
    if (!ProtonDenoiseEffects.isSupported) {
      return;
    }
    if (!_flagsAllow(type)) {
      return;
    }

    final mic = _findLocalMic(room);
    if (mic == null) {
      l.logger.d('[AudioDenoise] attach skipped: no mic track');
      return;
    }

    final mediaTrack = mic.mediaStreamTrack;
    if (mediaTrack.id == null || mediaTrack.id!.isEmpty) {
      l.logger.d('[AudioDenoise] attach skipped: missing track id');
      return;
    }

    final id = mediaTrack.id!;

    if (id == _attachedTrackId) {
      l.logger.d('[AudioDenoise] attach skipped: already on trackId=$id');
      return;
    }

    final gen = ++_generation;
    _syncInProgress = true;
    try {
      if (DenoiseAudioService.isDeepFilterType(type)) {
        await DenoiseAudioService.instance.warmUpDeepFilterIfNeeded(type: type);
      }

      final ready = await ProtonDenoiseEffects.instance.isTypeReady(type);
      if (!ready) {
        l.logger.w('[AudioDenoise] attach skipped: ${type.id} not ready');
        return;
      }

      if (_attachedTrackId != null && _attachedTrackId != id) {
        await _detachCurrent(room);
      }

      if (_generation != gen) {
        l.logger.d('[AudioDenoise] attach aborted: stale generation');
        return;
      }

      for (var attempt = 1; attempt <= _maxAttachAttempts; attempt++) {
        try {
          await ProtonDenoiseEffects.instance
              .attachDenoise(trackId: id, type: type)
              .timeout(_attachTimeout);
          if (_generation != gen) {
            l.logger.d('[AudioDenoise] attach aborted post-call: stale');
            return;
          }
          _attachedTrackId = id;
          l.logger.d(
            '[AudioDenoise] attached trackId=$id type=${type.id} '
            'attempt=$attempt',
          );
          return;
        } on PlatformException catch (e) {
          if (e.code != 'WEBRTC_NOT_READY' || attempt == _maxAttachAttempts) {
            rethrow;
          }
          l.logger.d(
            '[AudioDenoise] WEBRTC_NOT_READY retry $attempt/$_maxAttachAttempts',
          );
          await Future<void>.delayed(Duration(milliseconds: 80 * attempt));
        }
      }
    } on TimeoutException {
      l.logger.w('[AudioDenoise] attach timed out type=${type.id}');
    } catch (e, st) {
      l.logger.e('[AudioDenoise] attach failed: $e', error: e, stackTrace: st);
    } finally {
      _syncInProgress = false;
    }
  }

  LocalAudioTrack? _findLocalMic(Room room) {
    final lp = room.localParticipant;
    if (lp == null) {
      return null;
    }
    for (final pub in lp.audioTrackPublications) {
      final t = pub.track;
      if (t is LocalAudioTrack && t.source != TrackSource.screenShareAudio) {
        return t;
      }
    }
    return null;
  }

  bool _flagsAllow(DenoiseType type) {
    try {
      final unleash = ManagerFactory()
          .get<DataProviderManager>()
          .unleashDataProvider;
      if (!unleash.isMeetAudioDenoise()) {
        return false;
      }
      return _isTypeAllowedByFlags(unleash, type);
    } catch (e, st) {
      l.logger.w('[AudioDenoise] flag lookup failed', error: e, stackTrace: st);
      return false;
    }
  }
}

bool _isTypeAllowedByFlags(UnleashDataProvider unleash, DenoiseType type) {
  switch (type) {
    case DenoiseType.rnnoise:
      return unleash.isMeetAudioDenoiseRnnoise();
    case DenoiseType.deepfilter:
      return unleash.isMeetAudioDenoiseDeepfilter();
    case DenoiseType.dtlnRs:
      return unleash.isMeetAudioDenoiseDtlnRs();
    case DenoiseType.none:
      return false;
  }
}
