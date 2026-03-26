import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:meet/views/scenes/room/room_state.dart';

/// Mixin for handling connection status checks
///
/// This mixin listens to connectivity changes and triggers reconnection when needed.
/// If the connection is not reconnecting and MLS is not up-to-date, it sets
/// connectionLost to true in the state.
mixin RoomConnectionCheckHandlers on Bloc<RoomBlocEvent, RoomState> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _mlsCheckTimer;
  Timer? _epochHealthCheckTimer;
  bool _startHealthCheck = false;
  bool _hasNetwork = true;

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

    // Set up connectivity listener
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    _checkConnectionWithDelay();
    _logUserEpochHealth();
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

  /// Handle connectivity changes and trigger reconnection if needed
  Future<void> _onConnectivityChanged(List<ConnectivityResult> result) async {
    if (!_startHealthCheck || isClosed) {
      return;
    }

    final isNetworkAvailable = _isNetworkAvailable(result);

    if (isNetworkAvailable) {
      _hasNetwork = true;
      // Network is available, check connection status and reconnect if needed
      await _checkConnection();
    } else {
      // Network is not available
      _hasNetwork = false;
    }
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
