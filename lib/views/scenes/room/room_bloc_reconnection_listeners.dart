import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/views/scenes/room/room_bloc_feature_flags.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:meet/views/scenes/room/room_state.dart';

/// Mixin for handling reconnection-related listeners and state management
/// This includes MLS sync state monitoring and key rotation subscription management
mixin RoomReconnectionListeners on Bloc<RoomBlocEvent, RoomState> {
  // Subscription for key rotation listener from RoomConnectionHelper
  StreamSubscription<(String, BigInt)?>? _keyRotationSubscription;
  // Subscription for MLS sync state listener
  StreamSubscription<dynamic>? _mlsSyncStateSubscription;
  bool _hasLoggedConnectionLost = false;
  bool _hasTriggeredWebsocketReconnect = false;

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
        if (this is RoomFeatureFlagsHandlers) {
          final featureFlagsHandler = this as RoomFeatureFlagsHandlers;
          if (!featureFlagsHandler.isMeetAutoReconnectionEnabled()) {
            l.logger.d(
              '[RoomBloc] Auto reconnection feature disabled, skipping rejoin',
            );
            return;
          }
        }
        l.logger.w('[RoomBloc] MLS sync failed, triggering rejoin');
        await _logConnectionLost();
        if (!_hasTriggeredWebsocketReconnect) {
          // trigger websocket reconnect to see if it can automatically reconnect
          add(const TriggerWebsocketReconnect());
          _hasTriggeredWebsocketReconnect = true;
          return;
        }
        // To-do: add correct reason based on the RustCore
        add(StartRejoinMeeting(reason: event.reason));
        _hasTriggeredWebsocketReconnect = false;
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

  /// Register handlers for reconnection-related events
  void registerReconnectionListeners() {
    on<MlsSyncStateUpdated>(_onMlsSyncStateUpdated);
  }

  /// Cleanup reconnection-related subscriptions
  void disposeReconnectionListeners() {
    _keyRotationSubscription?.cancel();
    _mlsSyncStateSubscription?.cancel();
  }
}
