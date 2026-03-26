import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/pip/android_pip_manager.dart';
import 'package:meet/managers/pip/pip_manager_interface.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:meet/views/scenes/room/room_state.dart';

mixin RoomPipHandlers on Bloc<RoomBlocEvent, RoomState> {
  PipManagerInterface? _pipManager;
  StreamSubscription<bool>? _pipStateSubscription;
  bool _justExitedPip = false;

  void registerPipHandlers() {
    on<InitializePip>(_onInitializePip);
    on<EnterPipMode>(_onEnterPipMode);
    on<ExitPipMode>(_onExitPipMode);
    on<PipStateChanged>(_onPipStateChanged);
  }

  Future<void> _onInitializePip(
    InitializePip event,
    Emitter<RoomState> emit,
  ) async {
    // the manager will be implemented by platform
    if (android) {
      try {
        _pipManager = AndroidPipManager();
        await _pipManager!.initialize(
          roomName: event.roomName,
          onPipEntered: () async {
            add(PipStateChanged(isPipActive: true));
          },
          onPipExited: () async {
            _justExitedPip = true;
            add(PipStateChanged(isPipActive: false));
          },
          onNotificationTap: () async {
            add(ExitPipMode());
          },
        );

        final available = await _pipManager!.isPipAvailable();
        emit(state.copyWith(pipInitialized: true, pipAvailable: available));

        // Listen to PIP state changes
        _pipStateSubscription?.cancel();
        _pipStateSubscription = _pipManager!.pipStateStream.listen((isActive) {
          add(PipStateChanged(isPipActive: isActive));
        });
      } catch (e, stackTrace) {
        l.logger.e('[RoomBloc] PIP initialization failed: $e');
        l.logger.e('[RoomBloc] Stack trace: $stackTrace');
        emit(state.copyWith(pipInitialized: true, pipAvailable: false));
      }
    } else {
      // For non-Android platforms, mark as initialized but unavailable
      emit(state.copyWith(pipInitialized: true, pipAvailable: false));
    }
  }

  Future<void> _onEnterPipMode(
    EnterPipMode event,
    Emitter<RoomState> emit,
  ) async {
    if (_pipManager == null || !state.pipInitialized) {
      l.logger.w('[RoomBloc] PIP not initialized, initializing now...');
      await _onInitializePip(
        InitializePip(roomName: state.meetInfo.meetName),
        emit,
      );
    }

    if (state.isPipMode) {
      return;
    }

    if (_justExitedPip) {
      l.logger.d('[RoomBloc] Just exited PIP, skipping re-entry');
      return;
    }

    try {
      if (_pipManager != null && state.pipAvailable == true) {
        final success = await _pipManager!.enterPipMode();
        if (success) {
          emit(state.copyWith(isPipMode: true));
        }
      }
    } catch (e) {
      l.logger.e('[RoomBloc] Error entering PIP mode: $e');
    }
  }

  Future<void> _onExitPipMode(
    ExitPipMode event,
    Emitter<RoomState> emit,
  ) async {
    if (!state.isPipMode) {
      return;
    }

    try {
      await _pipManager?.exitPipMode();
      emit(state.copyWith(isPipMode: false));
    } catch (e) {
      l.logger.e('[RoomBloc] Error exiting PIP mode: $e');
      emit(state.copyWith(isPipMode: false));
    }
  }

  void _onPipStateChanged(PipStateChanged event, Emitter<RoomState> emit) {
    emit(state.copyWith(isPipMode: event.isPipActive));
    if (!event.isPipActive) {
      _justExitedPip = true;
      // Reset the flag after a delay to avoid immediate re-entry
      Future.delayed(const Duration(seconds: 3), () {
        _justExitedPip = false;
      });
    }
  }

  Future<void> disposePip() async {
    await _pipStateSubscription?.cancel();
    await _pipManager?.dispose();
    _pipManager = null;
  }
}
