import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/views/scenes/room/room_bloc_feature_flags.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:meet/views/scenes/room/room_state.dart';

/// Mixin for handling connection status checks
///
/// This mixin listens to connectivity changes and triggers reconnection when needed.
/// While the device has no network, auto-rejoin and websocket reconnect are deferred.
mixin RoomConnectionCheckHandlers on Bloc<RoomBlocEvent, RoomState> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _mlsCheckTimer;
  Timer? _epochHealthCheckTimer;
  Timer? _networkRestoreGraceTimer;
  bool _startHealthCheck = false;
  bool _hasNetwork = true;
  RejoinReason? _deferredRejoinReason;
  bool _deferredWebsocketReconnect = false;

  /// Whether connectivity_plus reports a usable network interface.
  bool get hasMeetingNetwork => _hasNetwork;

  /// True while waiting after network restore before escalating to App rejoin.
  bool get isNetworkRestoreRejoinGraceActive =>
      _networkRestoreGraceTimer?.isActive ?? false;

  /// Clears the post-outage grace timer (e.g. MLS/LiveKit recovered).
  void cancelNetworkRestoreRejoinGrace() {
    _networkRestoreGraceTimer?.cancel();
    _networkRestoreGraceTimer = null;
    _deferredRejoinReason = null;
  }

  void cancelNetworkRestoreRejoinGraceIfHealthy() {
    if (!_isMeetingConnectionHealthy()) {
      return;
    }
    cancelNetworkRestoreRejoinGrace();
  }

  void deferAutoRejoinUntilNetwork(RejoinReason reason) {
    _deferredRejoinReason ??= reason;
    l.logger.i(
      '[RoomConnectionCheck] Deferred rejoin until network returns (reason=$reason)',
    );
  }

  void deferWebsocketReconnectUntilNetwork() {
    _deferredWebsocketReconnect = true;
    l.logger.i(
      '[RoomConnectionCheck] Deferred websocket reconnect until network returns',
    );
  }

  void registerConnectionCheckHandlers() {
    on<StartConnectionHealthCheck>(_onStartConnectionHealthCheck);
    on<StopConnectionHealthCheck>(_onStopConnectionHealthCheck);
    on<CheckConnectionStatus>(_onCheckConnectionStatus);
  }

  void startConnectionHealthCheck() {
    if (_connectivitySubscription != null) {
      return; // Already started
    }
    _startHealthCheck = true;

    unawaited(_syncInitialNetworkState());

    // Set up connectivity listener
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    _checkConnectionWithDelay();
    _logUserEpochHealth();
  }

  Future<void> _syncInitialNetworkState() async {
    try {
      final result = await Connectivity().checkConnectivity();
      _applyNetworkAvailability(_isNetworkAvailable(result));
    } catch (e) {
      l.logger.w('[RoomConnectionCheck] Initial connectivity check failed: $e');
    }
  }

  /// Check connection and schedule next check after completion
  /// This ensures we wait 10 seconds after each check completes before checking again
  Future<void> _checkConnectionWithDelay() async {
    if (!_startHealthCheck || isClosed) {
      return;
    }

    await _checkConnection();

    if (!isClosed && _startHealthCheck) {
      await Future.delayed(const Duration(seconds: 5));
      if (!isClosed && _startHealthCheck) {
        _checkConnectionWithDelay();
      }
    }
  }

  void stopConnectionHealthCheck() {
    _startHealthCheck = false;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _mlsCheckTimer?.cancel();
    _mlsCheckTimer = null;
    _epochHealthCheckTimer?.cancel();
    _epochHealthCheckTimer = null;
    _networkRestoreGraceTimer?.cancel();
    _networkRestoreGraceTimer = null;
    _deferredRejoinReason = null;
    _deferredWebsocketReconnect = false;
  }

  Future<void> _onStartConnectionHealthCheck(
    StartConnectionHealthCheck event,
    Emitter<RoomState> emit,
  ) async {
    startConnectionHealthCheck();
  }

  Future<void> _onStopConnectionHealthCheck(
    StopConnectionHealthCheck event,
    Emitter<RoomState> emit,
  ) async {
    stopConnectionHealthCheck();
  }

  Future<void> _onCheckConnectionStatus(
    CheckConnectionStatus event,
    Emitter<RoomState> emit,
  ) async {
    await _checkConnection();
  }

  /// Check if network is available from connectivity result
  bool _isNetworkAvailable(List<ConnectivityResult> connectivityResult) {
    return connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi) ||
        connectivityResult.contains(ConnectivityResult.ethernet);
  }

  void _applyNetworkAvailability(bool isAvailable) {
    if (_hasNetwork == isAvailable) {
      /// nothing to do when network is off
      /// or network was ok and is still ok
      return;
    }

    if (isAvailable) {
      /// network is back, trigger reconnection and mark network as ok
      _hasNetwork = true;
      add(const MeetingNetworkAvailabilityChanged(isAvailable: true));
      _onNetworkRestored();
    } else {
      /// network is off, mark network as off
      _hasNetwork = false;
      _networkRestoreGraceTimer?.cancel();
      _networkRestoreGraceTimer = null;
      add(const MeetingNetworkAvailabilityChanged(isAvailable: false));
    }
  }

  /// Handle connectivity changes and trigger reconnection if needed
  Future<void> _onConnectivityChanged(List<ConnectivityResult> result) async {
    if (!_startHealthCheck || isClosed) {
      return;
    }

    _applyNetworkAvailability(_isNetworkAvailable(result));
  }

  void _onNetworkRestored() {
    _resumeReconnectionAfterNetworkRestore();
  }

  bool _isMeetingConnectionHealthy() {
    final isLivekitConnected =
        state.room.localParticipant != null && !state.isLiveKitReconnecting;
    final isMlsSynced = state.mlsSyncState == MlsSyncState.success;
    return isLivekitConnected && isMlsSynced;
  }

  /// LiveKit may resume on its own after a short radio outage if the Room
  /// object is still alive (local participant present or SDK already reconnecting).
  bool _livekitTransportMayRecoverAfterNetworkRestore() {
    return state.isLiveKitReconnecting || state.room.localParticipant != null;
  }

  void _scheduleNetworkRestoreRejoinEscalation() {
    _networkRestoreGraceTimer?.cancel();
    _networkRestoreGraceTimer = Timer(livekitReconnectEscalationTimeout, () {
      _networkRestoreGraceTimer = null;
      if (isClosed || !_hasNetwork || state.isRejoining) {
        return;
      }
      if (_isMeetingConnectionHealthy()) {
        _deferredRejoinReason = null;
        return;
      }

      final reason =
          _deferredRejoinReason ?? RejoinReason.websocketDisconnected;
      _deferredRejoinReason = null;

      l.logger.w(
        '[RoomConnectionCheck] Network restore grace '
        '(${livekitReconnectEscalationTimeout.inSeconds}s) elapsed — '
        'starting App rejoin (reason=$reason)',
      );

      if (state.rejoinStatus == RejoinStatus.error) {
        add(const CancelRejoinMeeting());
      }
      add(StartRejoinMeeting(reason: reason));
    });
  }

  /// Recovery when connectivity returns after an outage.
  void _resumeReconnectionAfterNetworkRestore() {
    if (isClosed) {
      return;
    }

    if (_deferredWebsocketReconnect && !state.isRejoining) {
      _deferredWebsocketReconnect = false;
      add(const TriggerWebsocketReconnect());
    }

    if (this is RoomFeatureFlagsHandlers &&
        !(this as RoomFeatureFlagsHandlers).isMeetAutoReconnectionEnabled()) {
      _deferredRejoinReason = null;
      _networkRestoreGraceTimer?.cancel();
      _networkRestoreGraceTimer = null;
      return;
    }

    if (state.isRejoining) {
      return;
    }

    if (_isMeetingConnectionHealthy()) {
      _deferredRejoinReason = null;
      _networkRestoreGraceTimer?.cancel();
      _networkRestoreGraceTimer = null;
      return;
    }

    // Short Wi‑Fi drops: prefer LiveKit built-in reconnect + MLS websocket
    // before tearing down the Room (full App rejoin hides the meeting UI).
    if (_livekitTransportMayRecoverAfterNetworkRestore()) {
      l.logger.i(
        '[RoomConnectionCheck] Network restored while session may recover via '
        'LiveKit (livekitReconnecting=${state.isLiveKitReconnecting}, '
        'localParticipant=${state.room.localParticipant != null}, '
        'mls=${state.mlsSyncState}) — deferring App rejoin for '
        '${livekitReconnectEscalationTimeout.inSeconds}s',
      );

      if (state.mlsSyncState != MlsSyncState.success) {
        add(const TriggerWebsocketReconnect());
      }

      _deferredRejoinReason ??= RejoinReason.websocketDisconnected;
      _scheduleNetworkRestoreRejoinEscalation();
      return;
    }

    _networkRestoreGraceTimer?.cancel();
    _networkRestoreGraceTimer = null;

    final reason = _deferredRejoinReason ?? RejoinReason.websocketDisconnected;
    _deferredRejoinReason = null;

    l.logger.w(
      '[RoomConnectionCheck] Network restored but LiveKit session is gone '
      '(livekitReconnecting=${state.isLiveKitReconnecting}, '
      'localParticipant=${state.room.localParticipant != null}) — '
      'starting App rejoin (reason=$reason)',
    );

    if (state.rejoinStatus == RejoinStatus.error) {
      add(const CancelRejoinMeeting());
    }
    add(StartRejoinMeeting(reason: reason));
  }

  /// Check connection status, trigger reconnection if disconnected, and check MLS status
  Future<void> _checkConnection() async {
    if (!_startHealthCheck || isClosed || !_hasNetwork) {
      return;
    }

    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();

      final isMlsUpToDate = await appCoreManager.appCore.isMlsUpToDate();
      l.logger.i('[RoomConnectionCheck] MLS status: $isMlsUpToDate');
    } catch (error) {
      l.logger.e('[RoomConnectionCheck] Failed to check MLS status: $error');
    }
  }

  /// Log user epoch health metrics periodically
  /// This function checks if health check is enabled and epoch/displayCode are available,
  /// then calls appCore to log the metrics and schedules itself again after 30 seconds
  Future<void> _logUserEpochHealth() async {
    if (isClosed) {
      return;
    }

    if (_startHealthCheck &&
        state.epoch.isNotEmpty &&
        state.displayCode.isNotEmpty) {
      try {
        final appCoreManager = ManagerFactory().get<AppCoreManager>();
        final epochInt = int.tryParse(state.epoch);
        if (epochInt != null) {
          await appCoreManager.appCore.logUserEpochHealth(
            currentEpoch: epochInt,
            epochDisplayCode: state.displayCode,
          );
        }
      } catch (error) {
        l.logger.e(
          '[RoomConnectionCheck] Failed to log user epoch health: $error',
        );
      }
    }

    // Schedule next check after 30 seconds
    _epochHealthCheckTimer?.cancel();
    _epochHealthCheckTimer = Timer(
      const Duration(seconds: 30),
      _logUserEpochHealth,
    );
  }
}
