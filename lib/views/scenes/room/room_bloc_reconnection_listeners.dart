import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/views/scenes/room/room_bloc_feature_flags.dart';
import 'package:meet/views/scenes/room/room_bloc_rejoin.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:meet/views/scenes/room/room_state.dart';

/// Mixin for handling reconnection-related listeners and state management
/// This includes MLS sync state monitoring and key rotation subscription management
mixin RoomReconnectionListeners
    on
        Bloc<RoomBlocEvent, RoomState>,
        RoomFeatureFlagsHandlers,
        RoomRejoinHandlers {
  // Subscription for key rotation listener from RoomConnectionHelper
  StreamSubscription<(String, BigInt)?>? _keyRotationSubscription;
  // Subscription for MLS sync state listener
  StreamSubscription<dynamic>? _mlsSyncStateSubscription;
  bool _hasLoggedConnectionLost = false;
  bool _hasTriggeredWebsocketReconnect = false;
  // Watchdog that escalates a stuck LiveKit built-in reconnect to a fresh
  // App-level rejoin (see [handleLiveKitReconnectingChanged]).
  Timer? _livekitReconnectWatchdog;
  // When the current LiveKit built-in reconnect episode started. Used to decide
  // whether a resume that completes late (after the server has likely dropped us
  // and the committer removed us from MLS) should still be escalated to a full
  // reconnection. Null when the transport is healthy.
  DateTime? _livekitReconnectingStartedAt;
  // Consecutive MLS-failure-driven rejoins that have NOT restored MLS sync.
  // Reset to 0 once MLS reaches `success`. Guards against an infinite rejoin
  // loop when a rejoin reconnects the transport but can't re-add us to the MLS
  // group (see [kMaxMlsRecoveryRejoins]).
  int _mlsRecoveryRejoinAttempts = 0;

  /// Set key rotation subscription (called by RoomRejoinHandlers mixin)
  void setKeyRotationSubscription(
    StreamSubscription<(String, BigInt)?>? subscription,
  ) {
    _keyRotationSubscription?.cancel();
    _keyRotationSubscription = subscription;
  }

  /// Setup MLS sync state listener
  /// Public method so it can be called from RoomRejoinHandlers mixin
  void setupMlsSyncStateListener() {
    // Cancel existing subscription if any
    _mlsSyncStateSubscription?.cancel();

    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    _mlsSyncStateSubscription = appCoreManager.mlsSyncStateStream.listen((
      event,
    ) {
      // Emit state update event
      add(MlsSyncStateUpdated(state: event.$1, reason: event.$2));
    });
  }

  /// Handles the MLS sync state update event.
  ///
  /// Updates the room state with the new MLS sync state.
  /// If MLS sync fails, triggers rejoin if conditions are met.
  ///
  /// Parameters:
  /// - [event]: The MLS sync state updated event
  /// - [emit]: State emitter for updating the room state
  Future<void> _onMlsSyncStateUpdated(
    MlsSyncStateUpdated event,
    Emitter<RoomState> emit,
  ) async {
    final now = DateTime.now();
    l.logger.i("[RoomBloc] MLS sync state updated: ${event.state} at $now");
    emit(state.copyWith(mlsSyncState: event.state));

    if (event.state == MlsSyncState.success) {
      _hasLoggedConnectionLost = false;
      // MLS is healthy again — clear the recovery-rejoin budget so a future,
      // unrelated failure starts from a clean slate.
      _mlsRecoveryRejoinAttempts = 0;
      // Connection is healthy: forget any in-flight LiveKit outage timestamp so
      // a later, unrelated short blip isn't mis-measured as a long outage.
      _livekitReconnectingStartedAt = null;
    }

    // If MLS sync failed, log connection lost and trigger rejoin
    if (event.state == MlsSyncState.failed) {
      // Don't trigger rejoin if:
      // 1. Already rejoining
      // 2. Rejoin has already failed (user has seen the failed dialog)
      // 3. Rejoin completed within last 15 seconds (grace period to allow state to recover)
      final rejoinCompletedAt = state.rejoinCompletedAt;
      final isWithinGracePeriod =
          rejoinCompletedAt != null &&
          DateTime.now().difference(rejoinCompletedAt).inSeconds < 15;

      if (!state.isRejoining &&
          state.rejoinStatus != RejoinStatus.error &&
          !isWithinGracePeriod) {
        // Check if auto reconnection feature is enabled
        if (!isMeetAutoReconnectionEnabled()) {
          l.logger.d(
            '[RoomBloc] Auto reconnection feature disabled, skipping rejoin',
          );
          return;
        }
        l.logger.w('[RoomBloc] MLS sync failed, triggering rejoin');
        await _logConnectionLost();
        // Fast path: if the LiveKit transport is ALSO down (currently
        // reconnecting) when MLS fails, a Rust-core websocket reconnect alone
        // can't recover the media session — we'd reconnect MLS only to find
        // LiveKit still broken and rejoin anyway. Skip the gentle
        // websocket-only step and go straight to a full rejoin, which
        // re-establishes both LiveKit and MLS together.
        if (state.isLiveKitReconnecting) {
          l.logger.w(
            '[RoomBloc] MLS failed while LiveKit is also reconnecting — '
            'escalating to full rejoin immediately (skipping websocket-only '
            'reconnect)',
          );
          _hasTriggeredWebsocketReconnect = false;
          _tryStartMlsRecoveryRejoin(emit, event.reason);
          return;
        }
        if (!_hasTriggeredWebsocketReconnect) {
          // trigger websocket reconnect to see if it can automatically reconnect
          add(const TriggerWebsocketReconnect());
          _hasTriggeredWebsocketReconnect = true;
          return;
        }
        // To-do: add correct reason based on the RustCore
        _hasTriggeredWebsocketReconnect = false;
        _tryStartMlsRecoveryRejoin(emit, event.reason);
        return;
      } else if (isWithinGracePeriod) {
        l.logger.d(
          '[RoomBloc] MLS sync failed but within 15s grace period after rejoin completion, skipping rejoin trigger',
        );
      }

      if (state.rejoinStatus == RejoinStatus.error && !state.isRejoining) {
        l.logger.w(
          '[RoomBloc] MLS sync failed and room is in error state, triggering websocket reconnect to see if it can automatically reconnect',
        );
        // try to automatically reconnect websocket after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          add(const TriggerWebsocketReconnect());
        });
      }
    }
  }

  /// Starts an MLS-recovery rejoin unless we've already exhausted the recovery
  /// budget ([kMaxMlsRecoveryRejoins]).
  ///
  /// Each MLS-failure-driven rejoin increments the counter; it is only cleared
  /// when MLS reaches `success`. Once the budget is exhausted we stop the
  /// endless reconnect loop and surface the error dialog so the user can choose
  /// to leave or retry manually, instead of reconnecting forever.
  void _tryStartMlsRecoveryRejoin(
    Emitter<RoomState> emit,
    RejoinReason? reason,
  ) {
    _mlsRecoveryRejoinAttempts++;
    if (_mlsRecoveryRejoinAttempts > kMaxMlsRecoveryRejoins) {
      l.logger.e(
        '[RoomBloc] MLS still out of sync after $kMaxMlsRecoveryRejoins '
        'recovery rejoins — stopping auto-rejoin and surfacing the error state',
      );
      emit(
        state.copyWith(
          isRejoining: false,
          isLiveKitReconnecting: false,
          rejoinStatus: RejoinStatus.error,
          // Set a message so the rejoin-failed dialog actually surfaces: the UI
          // (room_reconnection_listeners.dart) only shows the dialog when
          // `rejoinError != null`. Without this the user would be left stuck on
          // a broken connection with no feedback at all.
          rejoinError:
              'MLS still out of sync after $kMaxMlsRecoveryRejoins '
              'reconnection attempts (reason: ${reason ?? RejoinReason.other})',
        ),
      );
      // Auto-rejoin is now halted by the `rejoinStatus == error` guard, so it is
      // safe to clear the budget: a user-initiated manual retry (which clears the
      // error state) then gets a fresh set of recovery attempts.
      _mlsRecoveryRejoinAttempts = 0;
      return;
    }
    l.logger.w(
      '[RoomBloc] Starting MLS-recovery rejoin '
      '($_mlsRecoveryRejoinAttempts/$kMaxMlsRecoveryRejoins), reason=$reason',
    );
    // A rejoin takes over recovery; drop any watchdog/outage tracking so it
    // can't fire or be mis-measured against this now-superseded episode.
    _livekitReconnectWatchdog?.cancel();
    _livekitReconnectWatchdog = null;
    _livekitReconnectingStartedAt = null;
    requestRejoin(reason);
  }

  /// Log connection lost event for metrics
  Future<void> _logConnectionLost() async {
    if (_hasLoggedConnectionLost) {
      l.logger.d('[RoomBloc] Skipping duplicate connection lost log');
      return;
    }

    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      if (dataProviderManager.unleashDataProvider.isMeetClientMetricsLog()) {
        final appCoreManager = ManagerFactory().get<AppCoreManager>();
        await appCoreManager.appCore.logConnectionLost();
        _hasLoggedConnectionLost = true;
        l.logger.i('[RoomBloc] Logged connection lost');
      }
    } catch (e) {
      l.logger.w('[RoomBloc] Error logging connection lost: $e');
    }
  }

  Future<void> logUserRejoin({
    required BigInt rejoinTimeMs,
    required int incrementalCount,
    required RejoinReason reason,
    required bool success,
  }) async {
    try {
      final dataProviderManager = ManagerFactory().get<DataProviderManager>();
      if (dataProviderManager.unleashDataProvider.isMeetClientMetricsLog()) {
        final appCoreManager = ManagerFactory().get<AppCoreManager>();
        await appCoreManager.appCore.logUserRejoin(
          rejoinTimeMs: rejoinTimeMs,
          incrementalCount: incrementalCount,
          reason: reason,
          success: success,
        );
        l.logger.i(
          '[RoomBloc] Logged user rejoin: time=${rejoinTimeMs}ms, count=$incrementalCount, reason=$reason, success=$success',
        );
      }
    } catch (e) {
      l.logger.w('[RoomBloc] Error logging user rejoin: $e');
    }
  }

  /// React to LiveKit's built-in reconnect (resume / full-restart) starting or
  /// finishing, driven by [SetLiveKitReconnecting].
  ///
  /// LiveKit's internal retry schedule can run for ~44s before giving up, and
  /// on flaky networks a single resume attempt can stall for tens of seconds on
  /// its (enlarged) connection/peer timeouts. That is a worse experience than
  /// simply re-joining from scratch. So when the transport starts reconnecting
  /// we arm a watchdog: if it hasn't recovered within
  /// [livekitReconnectEscalationTimeout] we proactively escalate to a fresh
  /// App-level rejoin, which tears down the stale Room and builds a new one.
  ///
  /// When the transport reconnects on its own quickly (a cheap resume within
  /// [livekitReconnectEscalationTimeout]) the watchdog is cancelled and no
  /// rejoin happens. But if the resume only completes AFTER that window, the
  /// outage lasted long enough that the LiveKit server has very likely dropped
  /// us and the committer has removed us from the MLS group — so the resumed
  /// transport is riding on a dead MLS session. In that case we do not trust the
  /// resume and force a full reconnection anyway (see [_forceFullReconnection]).
  void handleLiveKitReconnectingChanged(bool isReconnecting) {
    if (!isReconnecting) {
      _livekitReconnectWatchdog?.cancel();
      _livekitReconnectWatchdog = null;

      final startedAt = _livekitReconnectingStartedAt;
      _livekitReconnectingStartedAt = null;

      // Feature-gated: when auto reconnection is disabled, keep the legacy
      // behaviour of trusting LiveKit's built-in resume.
      if (!isMeetAutoReconnectionEnabled()) {
        return;
      }
      // A rejoin already in progress (or its error dialog) owns recovery.
      if (state.isRejoining || state.rejoinStatus == RejoinStatus.error) {
        return;
      }
      // The transport resumed. If it took longer than the escalation window the
      // outage was long enough to very likely cost us our MLS membership, so a
      // resume alone can't recover the session — force a full reconnection
      // rather than waiting for the slower MLS-failure path to notice.
      if (startedAt != null) {
        final outage = DateTime.now().difference(startedAt);
        if (outage >= livekitReconnectEscalationTimeout) {
          l.logger.w(
            '[RoomBloc] LiveKit resumed after a ${outage.inSeconds}s outage '
            '(>= ${livekitReconnectEscalationTimeout.inSeconds}s) — MLS '
            'membership was likely dropped, forcing a full reconnection',
          );
          _forceFullReconnection();
        }
      }
      return;
    }

    // Remember when this reconnect episode began so we can measure the total
    // outage when/if the transport resumes. Repeated reconnecting events during
    // the same outage keep the original start time.
    _livekitReconnectingStartedAt ??= DateTime.now();

    // Feature-gated: when auto reconnection is disabled, keep the legacy
    // behaviour of passively waiting for LiveKit's built-in reconnect.
    if (!isMeetAutoReconnectionEnabled()) {
      return;
    }

    // A rejoin already in progress (or its error dialog is up) owns recovery.
    if (state.isRejoining || state.rejoinStatus == RejoinStatus.error) {
      return;
    }

    // Fast path: if MLS is ALREADY down when the LiveKit transport starts
    // reconnecting, don't bother waiting for LiveKit's resume. A resume would
    // reconnect the media transport only to leave us with a dead MLS session
    // that forces a rejoin anyway — so we'd pay the resume cost and then still
    // rejoin. Skip straight to a full rejoin, which re-establishes both the
    // LiveKit connection and the MLS group in one shot.
    if (state.mlsSyncState == MlsSyncState.failed) {
      l.logger.w(
        '[RoomBloc] LiveKit reconnecting while MLS already failed — escalating '
        'to full rejoin immediately (skipping resume wait)',
      );
      _forceFullReconnection();
      return;
    }

    // Re-arm from scratch so repeated reconnecting events don't stack timers.
    _livekitReconnectWatchdog?.cancel();
    _livekitReconnectWatchdog = Timer(livekitReconnectEscalationTimeout, () {
      _livekitReconnectWatchdog = null;
      if (isClosed) {
        return;
      }
      // Bail if the transport already recovered or a rejoin has taken over.
      if (!state.isLiveKitReconnecting ||
          state.isRejoining ||
          state.rejoinStatus == RejoinStatus.error) {
        return;
      }
      if (!isMeetAutoReconnectionEnabled()) {
        return;
      }
      l.logger.w(
        '[RoomBloc] LiveKit still reconnecting after '
        '${livekitReconnectEscalationTimeout.inSeconds}s, forcing a full '
        'reconnection instead of waiting for the resume',
      );
      _forceFullReconnection();
    });
  }

  /// Force a full App-level reconnection ([StartRejoinMeeting]) in response to a
  /// LiveKit outage that has lasted at least [livekitReconnectEscalationTimeout].
  ///
  /// We use [RejoinReason.websocketDisconnected] (rather than
  /// `livekitConnectionTimeout`) on purpose: an outage this long very likely
  /// means the committer has already removed us from the MLS group, so the
  /// rejoin must do a clean re-join (no token reuse) to actually re-establish our
  /// MLS membership — reusing the old session can leave the server treating us
  /// as the still-present old member, so our re-join is never broadcast.
  void _forceFullReconnection() {
    // Any pending watchdog is now redundant.
    _livekitReconnectWatchdog?.cancel();
    _livekitReconnectWatchdog = null;
    _livekitReconnectingStartedAt = null;
    _hasTriggeredWebsocketReconnect = false;
    requestRejoin(RejoinReason.websocketDisconnected);
  }

  /// Register handlers for reconnection-related events
  void registerReconnectionListeners() {
    on<MlsSyncStateUpdated>(_onMlsSyncStateUpdated);
  }

  /// Cleanup reconnection-related subscriptions
  void disposeReconnectionListeners() {
    _keyRotationSubscription?.cancel();
    _mlsSyncStateSubscription?.cancel();
    _livekitReconnectWatchdog?.cancel();
    _livekitReconnectWatchdog = null;
    _livekitReconnectingStartedAt = null;
  }
}
