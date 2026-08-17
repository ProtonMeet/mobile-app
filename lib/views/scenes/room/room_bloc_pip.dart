import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/pip/android_pip_manager.dart';
import 'package:meet/managers/pip/ios_pip_manager.dart';
import 'package:meet/managers/pip/ios_pip_presentation.dart'
    show IosPipPresentation, resolveIosPipPresentationFromState;
import 'package:meet/managers/pip/pip_manager_interface.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:meet/views/scenes/room/room_state.dart';

mixin RoomPipHandlers on Bloc<RoomBlocEvent, RoomState> {
  PipManagerInterface? _pipManager;
  StreamSubscription<bool>? _pipStateSubscription;
  bool _justExitedPip = false;
  IosPipPresentation? _lastIosPipPresentation;
  Timer? _iosPipSyncDebounce;

  /// Coalesces rapid LiveKit events (speaking, mute) into a single native PiP refresh.
  void scheduleIosPipSync({bool immediate = false}) {
    if (!iOS || !state.pipInitialized) {
      return;
    }

    void fire() => add(SyncIosPipTrack());

    _iosPipSyncDebounce?.cancel();
    if (immediate) {
      fire();
      return;
    }

    final debounceMs = state.isPipMode ? 50 : 120;
    _iosPipSyncDebounce = Timer(Duration(milliseconds: debounceMs), fire);
  }

  /// Keep this remote's camera subscribed while iOS PiP may show them off-grid.
  String _iosPipCameraSubscriptionIdentity(RoomState s, IosPipPresentation? p) {
    if (!iOS || p == null) {
      return '';
    }
    if (s.isRemoteScreenSharing || s.isLocalScreenSharing) {
      return '';
    }
    final localId = s.room.localParticipant?.identity;
    if (localId != null && p.participantIdentity == localId) {
      return '';
    }
    return p.participantIdentity;
  }

  void _emitPipCameraSubscriptionIfChanged(
    Emitter<RoomState> emit,
    IosPipPresentation? p,
  ) {
    final next = _iosPipCameraSubscriptionIdentity(state, p);
    if (next != state.iosPipRemoteCameraSubscriptionIdentity) {
      emit(state.copyWith(iosPipRemoteCameraSubscriptionIdentity: next));
    }
  }

  void registerPipHandlers() {
    on<InitializePip>(_onInitializePip);
    on<EnterPipMode>(_onEnterPipMode);
    on<SyncIosPipTrack>(_onSyncIosPipTrack);
    on<ExitPipMode>(_onExitPipMode);
    on<PipStateChanged>(_onPipStateChanged);
  }

  Future<void> _onInitializePip(
    InitializePip event,
    Emitter<RoomState> emit,
  ) async {
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

        _pipStateSubscription?.cancel();
        _pipStateSubscription = _pipManager!.pipStateStream.listen((isActive) {
          add(PipStateChanged(isPipActive: isActive));
        });
      } catch (e, stackTrace) {
        l.logger.e('[RoomBloc] PIP initialization failed: $e');
        l.logger.e('[RoomBloc] Stack trace: $stackTrace');
        emit(state.copyWith(pipInitialized: true, pipAvailable: false));
      }
    } else if (iOS) {
      try {
        _pipManager = IosPipManager();
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

        _pipStateSubscription?.cancel();
        _pipStateSubscription = _pipManager!.pipStateStream.listen((isActive) {
          add(PipStateChanged(isPipActive: isActive));
        });

        final pipPresentation = resolveIosPipPresentationFromState(state);
        _emitPipCameraSubscriptionIfChanged(emit, pipPresentation);
      } catch (e, stackTrace) {
        l.logger.e('[RoomBloc] iOS PIP initialization failed: $e');
        l.logger.e('[RoomBloc] Stack trace: $stackTrace');
        emit(state.copyWith(pipInitialized: true, pipAvailable: false));
      }
    } else {
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
      final pipPresentation = await _applyIosPipPresentationIfNeeded(
        force: true,
      );
      if (pipPresentation == null) {
        if (iOS) {
          l.logger.w('[RoomBloc] iOS PiP: no participant for PiP content');
          return;
        }
      }

      if (_pipManager != null && state.pipAvailable == true) {
        final success = await _pipManager!.enterPipMode();
        if (success) {
          final subId = _iosPipCameraSubscriptionIdentity(
            state,
            pipPresentation,
          );
          emit(
            state.copyWith(
              isPipMode: true,
              iosPipRemoteCameraSubscriptionIdentity: subId,
            ),
          );
        }
      }
    } catch (e) {
      l.logger.e('[RoomBloc] Error entering PIP mode: $e');
    }
  }

  Future<void> _onSyncIosPipTrack(
    SyncIosPipTrack event,
    Emitter<RoomState> emit,
  ) async {
    if (!iOS || !state.pipInitialized || _pipManager == null) {
      return;
    }

    final pipPresentation = await _applyIosPipPresentationIfNeeded(
      force: state.isPipMode,
    );
    _emitPipCameraSubscriptionIfChanged(emit, pipPresentation);
  }

  Future<IosPipPresentation?> _applyIosPipPresentationIfNeeded({
    bool force = false,
  }) async {
    final pip = _pipManager;
    if (!iOS || pip is! IosPipManager) {
      return null;
    }

    final presentation = resolveIosPipPresentationFromState(state);
    if (presentation == null) {
      return null;
    }

    final changed = _lastIosPipPresentation != presentation;
    final trackBecameAvailable =
        _lastIosPipPresentation?.trackIds == null &&
        presentation.trackIds != null;
    if (!changed && !force && !trackBecameAvailable) {
      return presentation;
    }

    _lastIosPipPresentation = presentation;
    await pip.setPresentation(presentation);
    return presentation;
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
      _lastIosPipPresentation = null;
      emit(
        state.copyWith(
          isPipMode: false,
          iosPipRemoteCameraSubscriptionIdentity: '',
        ),
      );
    } catch (e) {
      l.logger.e('[RoomBloc] Error exiting PIP mode: $e');
      emit(
        state.copyWith(
          isPipMode: false,
          iosPipRemoteCameraSubscriptionIdentity: '',
        ),
      );
    }
  }

  void _onPipStateChanged(PipStateChanged event, Emitter<RoomState> emit) {
    emit(
      state.copyWith(
        isPipMode: event.isPipActive,
        iosPipRemoteCameraSubscriptionIdentity: event.isPipActive
            ? state.iosPipRemoteCameraSubscriptionIdentity
            : '',
      ),
    );
    if (!event.isPipActive) {
      _lastIosPipPresentation = null;
      _justExitedPip = true;
      Future.delayed(const Duration(seconds: 3), () {
        _justExitedPip = false;
      });
    }
  }

  Future<void> disposePip() async {
    _iosPipSyncDebounce?.cancel();
    _iosPipSyncDebounce = null;
    await _pipStateSubscription?.cancel();
    await _pipManager?.dispose();
    _pipManager = null;
    _lastIosPipPresentation = null;
  }
}
