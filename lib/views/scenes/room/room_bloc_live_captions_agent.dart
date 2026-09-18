import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/live_captions_constants.dart';
import 'package:meet/helper/extension/live_caption_participant_attributes.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/meet_join_link_parser.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/models/live_captions/live_caption_agent.dart';
import 'package:meet/models/live_captions/live_captions_models.dart';
import 'package:sentry/sentry.dart';

import 'room_bloc_feature_flags.dart';
import 'room_bloc_live_captions_transcriptions.dart';
import 'room_event.dart';
import 'room_state.dart';

/// Observes room-wide caption demand (`wanters`) and summons or removes the STT
/// agent via FRB (`requestClosedCaptions` / `stopClosedCaptions`).
///
/// Also registers MLS admission callbacks (`setAgentPendingCallback`) and calls
/// `admitAgent` when an agent uploads its KeyPackage — any joined client with
/// the meeting password may admit (meet-core rank-stagger deduplicates).
mixin RoomLiveCaptionsAgentHandlers
    on
        Bloc<RoomBlocEvent, RoomState>,
        RoomFeatureFlagsHandlers,
        RoomLiveCaptionsTranscriptionHandlers {
  Timer? _liveCaptionsAgentGraceTimer;
  Timer? _liveCaptionsAgentRetryTimer;
  Timer? _liveCaptionsAgentTeardownTimer;
  int _liveCaptionsAgentRetryIndex = 0;
  int _liveCaptionsAgentTeardownAttempts = 0;
  bool _liveCaptionsAgentSummonInFlight = false;
  bool _liveCaptionsAgentTeardownPending = false;

  /// Tracks recent successful admits to avoid duplicate reconcile sweeps.
  final Map<String, DateTime> _liveCaptionsAdmittedAgentAt = {};
  Timer? _liveCaptionsAgentReconcileTimer;
  bool _liveCaptionsAgentAdmissionCallbacksRegistered = false;

  static const Duration _agentReconcileDelay = Duration(seconds: 2);
  static const Duration _agentAdmissionSettle = Duration(seconds: 15);

  AppCoreManager get _appCoreManager => ManagerFactory().get<AppCoreManager>();

  void registerLiveCaptionsAgentHandlers() {
    on<EvaluateLiveCaptionsAgentLifecycle>(
      _onEvaluateLiveCaptionsAgentLifecycle,
    );
    on<LiveCaptionsAgentGraceElapsed>(_onLiveCaptionsAgentGraceElapsed);
    on<LiveCaptionsAgentSummonRetry>(_onLiveCaptionsAgentSummonRetry);
    on<LiveCaptionsAgentTeardownCheck>(_onLiveCaptionsAgentTeardownCheck);
    on<LiveCaptionsCaptionAgentConnected>(_onLiveCaptionsCaptionAgentConnected);
    on<LiveCaptionsCaptionAgentDisconnected>(
      _onLiveCaptionsCaptionAgentDisconnected,
    );
    on<LiveCaptionsAgentSummonFailed>(_onLiveCaptionsAgentSummonFailed);
  }

  /// Re-run the wanters → summon / grace → remove state machine.
  void scheduleLiveCaptionsAgentEvaluation() {
    if (isClosed) {
      return;
    }
    add(const EvaluateLiveCaptionsAgentLifecycle());
  }

  /// Cancel timers and reset in-flight lifecycle flags (leave / dispose).
  void teardownLiveCaptionsAgentLifecycle() {
    _cancelLiveCaptionsAgentTimers();
    _cancelAgentReconcileTimer();
    _liveCaptionsAdmittedAgentAt.clear();
    _liveCaptionsAgentRetryIndex = 0;
    _liveCaptionsAgentTeardownAttempts = 0;
    _liveCaptionsAgentSummonInFlight = false;
    _liveCaptionsAgentTeardownPending = false;
  }

  /// Register Rust to Dart callbacks for MLS agent admission (room join).
  Future<void> registerLiveCaptionsAgentAdmissionCallbacks() async {
    if (!isMeetLiveCaptionsEnabled()) {
      return;
    }
    if (_liveCaptionsAgentAdmissionCallbacksRegistered) {
      _schedulePendingAgentReconcile();
      return;
    }

    final appCore = _appCoreManager.appCore;
    try {
      await appCore.setAgentPendingCallback(
        callback: (deviceId) {
          if (isClosed) {
            return;
          }
          l.logger.i('[LiveCaptions] AgentPending received deviceId=$deviceId');
          unawaited(_admitAgentWithRetry(deviceId));
        },
      );
      await appCore.setAgentLeftCallback(
        callback: (deviceId) {
          _liveCaptionsAdmittedAgentAt.remove(deviceId);
        },
      );
      _liveCaptionsAgentAdmissionCallbacksRegistered = true;
      _schedulePendingAgentReconcile();
    } catch (e, stackTrace) {
      l.logger.w(
        '[LiveCaptions] failed to register agent admission callbacks: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> clearLiveCaptionsAgentAdmissionCallbacks() async {
    _cancelAgentReconcileTimer();
    _liveCaptionsAdmittedAgentAt.clear();
    if (!_liveCaptionsAgentAdmissionCallbacksRegistered) {
      return;
    }

    final appCore = _appCoreManager.appCore;
    try {
      await appCore.clearAgentPendingCallback();
      await appCore.clearAgentLeftCallback();
    } catch (e) {
      l.logger.w(
        '[LiveCaptions] failed to clear agent admission callbacks: $e',
      );
    } finally {
      _liveCaptionsAgentAdmissionCallbacksRegistered = false;
    }
  }

  void _schedulePendingAgentReconcile() {
    _cancelAgentReconcileTimer();
    _liveCaptionsAgentReconcileTimer = Timer(_agentReconcileDelay, () {
      if (!isClosed) {
        unawaited(_reconcilePendingAgents());
      }
    });
  }

  Future<void> _reconcilePendingAgents() async {
    if (!_canAdmitAgents()) {
      return;
    }

    final meetLinkName = _meetLinkName;
    if (meetLinkName.isEmpty) {
      return;
    }

    try {
      final pending = await _appCoreManager.appCore.listPendingAgents(
        meetLinkName: meetLinkName,
      );
      for (final deviceId in pending) {
        if (_recentlyAdmitted(deviceId)) {
          continue;
        }
        l.logger.i('[LiveCaptions] reconcile pending agent deviceId=$deviceId');
        unawaited(_admitAgentWithRetry(deviceId));
      }
    } catch (e, stackTrace) {
      l.logger.w(
        '[LiveCaptions] listPendingAgents failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _admitAgentWithRetry(String deviceId) async {
    if (!_shouldAdmitAgent(deviceId)) {
      return;
    }

    final password = _meetingPassword();
    if (password == null || password.isEmpty) {
      l.logger.d(
        '[LiveCaptions] admitAgent skipped: no meeting password '
        '(deviceId=$deviceId)',
      );
      return;
    }

    final meetLinkName = _meetLinkName;
    if (meetLinkName.isEmpty) {
      return;
    }

    for (final delay in LiveCaptionsConstants.agentRetryDelays) {
      if (!_shouldAdmitAgent(deviceId)) {
        return;
      }
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }

      try {
        await _appCoreManager.appCore.admitAgent(
          meetLinkName: meetLinkName,
          agentDeviceId: deviceId,
          meetingPassword: password,
        );
        _liveCaptionsAdmittedAgentAt[deviceId] = DateTime.now();
        l.logger.i('[LiveCaptions] admitAgent succeeded deviceId=$deviceId');
        return;
      } catch (e, stackTrace) {
        l.logger.w(
          '[LiveCaptions] admitAgent failed deviceId=$deviceId: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    l.logger.w(
      '[LiveCaptions] admitAgent retries exhausted deviceId=$deviceId',
    );
  }

  bool _canAdmitAgents() {
    if (!isMeetLiveCaptionsEnabled() || !_isJoinedRoom()) {
      return false;
    }
    final password = _meetingPassword();
    return password != null && password.isNotEmpty;
  }

  bool _shouldAdmitAgent(String deviceId) {
    if (!_canAdmitAgents()) {
      return false;
    }
    if (!state.room.hasLiveCaptionsWanters) {
      return false;
    }
    if (_recentlyAdmitted(deviceId)) {
      return false;
    }
    return true;
  }

  bool _recentlyAdmitted(String deviceId) {
    final admittedAt = _liveCaptionsAdmittedAgentAt[deviceId];
    if (admittedAt == null) {
      return false;
    }
    return DateTime.now().difference(admittedAt) < _agentAdmissionSettle;
  }

  String? _meetingPassword() {
    final link = state.meetingLink;
    if (link.isEmpty) {
      return null;
    }
    return parseMeetJoinLink(link).passcode;
  }

  void _cancelAgentReconcileTimer() {
    _liveCaptionsAgentReconcileTimer?.cancel();
    _liveCaptionsAgentReconcileTimer = null;
  }

  void _onEvaluateLiveCaptionsAgentLifecycle(
    EvaluateLiveCaptionsAgentLifecycle event,
    Emitter<RoomState> emit,
  ) {
    if (!isMeetLiveCaptionsEnabled()) {
      teardownLiveCaptionsAgentLifecycle();
      return;
    }

    if (!_isJoinedRoom()) {
      teardownLiveCaptionsAgentLifecycle();
      return;
    }

    final hasWanters = state.room.hasLiveCaptionsWanters;
    final agentPresent = _isCaptionAgentPresent();

    if (hasWanters) {
      _cancelGraceTimer();

      if (agentPresent && !_liveCaptionsAgentTeardownPending) {
        _cancelSummonRetry();
        _liveCaptionsAgentSummonInFlight = false;
        return;
      }

      if (_liveCaptionsAgentTeardownPending) {
        _clearTeardownTracking();
      }

      if (!_liveCaptionsAgentSummonInFlight) {
        _startSummonRetryLoop();
      }
      _schedulePendingAgentReconcile();
      return;
    }

    if (_liveCaptionsAgentSummonInFlight) {
      _cancelSummonRetry();
      _liveCaptionsAgentSummonInFlight = false;
      unawaited(_stopClosedCaptions());
      return;
    }

    if (!agentPresent) {
      _cancelGraceTimer();
      if (_liveCaptionsAgentTeardownPending) {
        _clearTeardownTracking();
      }
      return;
    }

    if (_liveCaptionsAgentTeardownPending) {
      return;
    }

    if (_liveCaptionsAgentGraceTimer?.isActive ?? false) {
      return;
    }

    _liveCaptionsAgentGraceTimer = Timer(
      LiveCaptionsConstants.agentDisableGrace,
      () {
        if (!isClosed) {
          add(const LiveCaptionsAgentGraceElapsed());
        }
      },
    );
  }

  void _onLiveCaptionsAgentGraceElapsed(
    LiveCaptionsAgentGraceElapsed event,
    Emitter<RoomState> emit,
  ) {
    _liveCaptionsAgentGraceTimer = null;

    if (!isMeetLiveCaptionsEnabled() || !_isJoinedRoom()) {
      return;
    }
    if (state.room.hasLiveCaptionsWanters) {
      return;
    }
    if (!_isCaptionAgentPresent()) {
      return;
    }

    unawaited(_beginTeardown());
  }

  Future<void> _onLiveCaptionsAgentSummonRetry(
    LiveCaptionsAgentSummonRetry event,
    Emitter<RoomState> emit,
  ) async {
    if (!_stillNeedsAgent()) {
      _cancelSummonRetry();
      _liveCaptionsAgentSummonInFlight = false;
      return;
    }

    await _requestClosedCaptions();

    if (_isCaptionAgentPresent()) {
      _cancelSummonRetry();
      _liveCaptionsAgentSummonInFlight = false;
      return;
    }

    _scheduleNextSummonAttempt();
  }

  void _onLiveCaptionsAgentTeardownCheck(
    LiveCaptionsAgentTeardownCheck event,
    Emitter<RoomState> emit,
  ) {
    _liveCaptionsAgentTeardownTimer = null;

    if (!_liveCaptionsAgentTeardownPending) {
      return;
    }

    if (!_isCaptionAgentPresent()) {
      _clearTeardownTracking();
      return;
    }

    if (_liveCaptionsAgentTeardownAttempts >=
        LiveCaptionsConstants.teardownMaxAttempts) {
      l.logger.e(
        '[LiveCaptions] agent teardown failed after '
        '${LiveCaptionsConstants.teardownMaxAttempts} attempts',
      );
      unawaited(
        Sentry.captureMessage(
          'Live captions agent teardown failed after max attempts',
        ),
      );
      _clearTeardownTracking();
      return;
    }

    unawaited(_beginTeardown());
  }

  void _onLiveCaptionsCaptionAgentConnected(
    LiveCaptionsCaptionAgentConnected event,
    Emitter<RoomState> emit,
  ) {
    if (!isMeetLiveCaptionsEnabled()) {
      return;
    }

    _cancelSummonRetry();
    _liveCaptionsAgentSummonInFlight = false;

    _schedulePendingAgentReconcile();

    if (_liveCaptionsAgentTeardownPending &&
        !state.room.hasLiveCaptionsWanters) {
      scheduleLiveCaptionsAgentEvaluation();
    }

    onLiveCaptionsCaptionAgentConnectedForTranscription(emit);
  }

  void _onLiveCaptionsCaptionAgentDisconnected(
    LiveCaptionsCaptionAgentDisconnected event,
    Emitter<RoomState> emit,
  ) {
    if (!isMeetLiveCaptionsEnabled()) {
      return;
    }

    _clearTeardownTracking();
    scheduleLiveCaptionsAgentEvaluation();
  }

  Future<void> _onLiveCaptionsAgentSummonFailed(
    LiveCaptionsAgentSummonFailed event,
    Emitter<RoomState> emit,
  ) async {
    if (!isMeetLiveCaptionsEnabled() || isClosed) {
      return;
    }
    if (!state.liveCaptionsWanted || _isCaptionAgentPresent()) {
      return;
    }

    _cancelSummonRetry();
    _liveCaptionsAgentSummonInFlight = false;

    l.logger.w(
      '[LiveCaptions] agent summon failed — auto-disabling local preference',
    );

    unawaited(
      Sentry.captureMessage(
        'Live captions agent summon failed after max retries',
        level: SentryLevel.warning,
      ),
    );

    final local = state.room.localParticipant;
    if (local != null) {
      try {
        await local.setLiveCaptionsWanted(enabled: false);
      } catch (e, stackTrace) {
        l.logger.w(
          '[LiveCaptions] auto-disable setLiveCaptionsWanted failed: $e',
          error: e,
          stackTrace: stackTrace,
        );
      }
    }

    add(const ClearLiveCaptionsTranscriptions());
    emit(
      state.copyWith(
        liveCaptionsWanted: false,
        liveCaptionsTranscriptions: Transcriptions.empty,
        isLiveCaptionsPreferenceWriteInFlight: false,
        shouldShowLiveCaptionsSummonFailedError: true,
        liveCaptionsAttributesGeneration:
            state.liveCaptionsAttributesGeneration + 1,
      ),
    );
  }

  bool _isJoinedRoom() =>
      state.isRoomInitialized && state.room.localParticipant != null;

  bool _isCaptionAgentPresent() =>
      state.room.remoteParticipants.values.any(isCaptionAgent);

  bool _stillNeedsAgent() {
    if (isClosed || !_isJoinedRoom()) {
      return false;
    }
    return state.room.hasLiveCaptionsWanters &&
        (!_isCaptionAgentPresent() || _liveCaptionsAgentTeardownPending);
  }

  String get _meetLinkName => state.meetInfo.meetLinkName;

  void _startSummonRetryLoop() {
    _liveCaptionsAgentSummonInFlight = true;
    _liveCaptionsAgentRetryIndex = 0;
    _scheduleNextSummonAttempt();
  }

  void _scheduleNextSummonAttempt() {
    if (!_stillNeedsAgent()) {
      _cancelSummonRetry();
      _liveCaptionsAgentSummonInFlight = false;
      return;
    }

    if (_liveCaptionsAgentRetryIndex >=
        LiveCaptionsConstants.agentRetryDelays.length) {
      l.logger.w(
        '[LiveCaptions] agent summon retries exhausted after '
        '${LiveCaptionsConstants.agentWait.inSeconds}s',
      );
      _liveCaptionsAgentSummonInFlight = false;
      if (state.liveCaptionsWanted && !_isCaptionAgentPresent()) {
        add(const LiveCaptionsAgentSummonFailed());
      }
      return;
    }

    final delay =
        LiveCaptionsConstants.agentRetryDelays[_liveCaptionsAgentRetryIndex];
    _liveCaptionsAgentRetryIndex++;

    _liveCaptionsAgentRetryTimer?.cancel();
    _liveCaptionsAgentRetryTimer = Timer(delay, () {
      if (!isClosed) {
        add(const LiveCaptionsAgentSummonRetry());
      }
    });
  }

  Future<void> _beginTeardown() async {
    if (_liveCaptionsAgentTeardownPending &&
        _liveCaptionsAgentTeardownAttempts >=
            LiveCaptionsConstants.teardownMaxAttempts) {
      return;
    }

    _liveCaptionsAgentTeardownPending = true;
    _liveCaptionsAgentTeardownAttempts++;

    await _stopClosedCaptions();

    if (!_isCaptionAgentPresent()) {
      _clearTeardownTracking();
      return;
    }

    _scheduleTeardownTimeout();
  }

  void _scheduleTeardownTimeout() {
    _liveCaptionsAgentTeardownTimer?.cancel();
    _liveCaptionsAgentTeardownTimer = Timer(
      LiveCaptionsConstants.teardownTimeout,
      () {
        if (!isClosed) {
          add(const LiveCaptionsAgentTeardownCheck());
        }
      },
    );
  }

  Future<void> _requestClosedCaptions() async {
    final meetLinkName = _meetLinkName;
    if (meetLinkName.isEmpty) {
      l.logger.w('[LiveCaptions] requestClosedCaptions skipped: empty link');
      return;
    }

    try {
      await _appCoreManager.appCore.requestClosedCaptions(
        meetLinkName: meetLinkName,
      );
    } catch (e, stackTrace) {
      l.logger.w(
        '[LiveCaptions] requestClosedCaptions failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _stopClosedCaptions() async {
    final meetLinkName = _meetLinkName;
    if (meetLinkName.isEmpty) {
      l.logger.w('[LiveCaptions] stopClosedCaptions skipped: empty link');
      return;
    }

    try {
      await _appCoreManager.appCore.stopClosedCaptions(
        meetLinkName: meetLinkName,
      );
    } catch (e, stackTrace) {
      l.logger.w(
        '[LiveCaptions] stopClosedCaptions failed: $e',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _cancelLiveCaptionsAgentTimers() {
    _cancelGraceTimer();
    _cancelSummonRetry();
    _cancelTeardownTimeout();
  }

  void _cancelGraceTimer() {
    _liveCaptionsAgentGraceTimer?.cancel();
    _liveCaptionsAgentGraceTimer = null;
  }

  void _cancelSummonRetry() {
    _liveCaptionsAgentRetryTimer?.cancel();
    _liveCaptionsAgentRetryTimer = null;
    _liveCaptionsAgentRetryIndex = 0;
  }

  void _cancelTeardownTimeout() {
    _liveCaptionsAgentTeardownTimer?.cancel();
    _liveCaptionsAgentTeardownTimer = null;
  }

  void _clearTeardownTracking() {
    _cancelTeardownTimeout();
    _liveCaptionsAgentTeardownPending = false;
    _liveCaptionsAgentTeardownAttempts = 0;
  }
}
