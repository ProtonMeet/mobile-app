import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_state.dart';

import 'in_room_settings_event.dart';
import 'in_room_settings_transport.dart';

typedef _FeatureFlags = ({bool waitingRoom, bool recording, bool preview});

const _FeatureFlags _allFlagsOff = (
  waitingRoom: false,
  recording: false,
  preview: false,
);

/// Owns in-meeting settings state for the room side panel.
class InRoomSettingsBloc
    extends Bloc<InRoomSettingsEvent, InRoomSettingsState> {
  InRoomSettingsBloc({
    required DataProviderManager dataProviderManager,
    required InRoomHostSettingsTransport transport,
  }) : _dataProviderManager = dataProviderManager,
       _transport = transport,
       super(const InRoomSettingsState()) {
    on<InRoomSettingsInitialized>(_onInitialized);
    on<InRoomSettingsFeatureFlagsChanged>(_onFeatureFlagsChanged);
    on<InRoomSettingsBindingsUpdated>(_onBindingsUpdated);
    on<InRoomLockMeetingToggled>(_onLockMeetingToggled);
    on<InRoomWaitingRoomToggled>(_onWaitingRoomToggled);
    on<InRoomIncomingVideoToggled>(_onIncomingVideoToggled);
    on<InRoomSelfViewToggled>(_onSelfViewToggled);
    on<InRoomHostStatusUpdated>(_onHostStatusUpdated);

    _bindUnleashProvider(refresh: false);
    _unleashReplacedSubscription = _dataProviderManager
        .onUnleashDataProviderReplaced
        .listen((_) => _bindUnleashProvider());
  }

  final DataProviderManager _dataProviderManager;
  final InRoomHostSettingsTransport _transport;
  late final StreamSubscription<void> _unleashReplacedSubscription;
  StreamSubscription<DataState>? _unleashSubscription;

  void _bindUnleashProvider({bool refresh = true}) {
    unawaited(_unleashSubscription?.cancel());
    _unleashSubscription = _dataProviderManager.unleashDataProvider.stream
        .listen((dataState) {
          if (dataState is UnleashFeatureFlagsUpdated && !isClosed) {
            add(InRoomSettingsFeatureFlagsChanged());
          }
        });
    if (!isClosed && refresh) {
      add(InRoomSettingsFeatureFlagsChanged());
    }
  }

  @override
  Future<void> close() {
    unawaited(_unleashReplacedSubscription.cancel());
    unawaited(_unleashSubscription?.cancel());
    return super.close();
  }

  void _onInitialized(
    InRoomSettingsInitialized event,
    Emitter<InRoomSettingsState> emit,
  ) {
    final flags = _readFeatureFlags();
    emit(
      state.copyWith(
        lockMeeting: event.lockMeeting,
        waitingRoomEnabled: event.waitingRoomEnabled,
        showPreviewSettings: flags.preview,
        showWaitingRoom: flags.waitingRoom,
        showRecordingRows: flags.recording && state.isHost,
      ),
    );
  }

  void _onFeatureFlagsChanged(
    InRoomSettingsFeatureFlagsChanged event,
    Emitter<InRoomSettingsState> emit,
  ) {
    _applyFeatureFlagVisibility(emit);
  }

  void _applyFeatureFlagVisibility(Emitter<InRoomSettingsState> emit) {
    final flags = _readFeatureFlags();
    emit(
      state.copyWith(
        showPreviewSettings: flags.preview,
        showWaitingRoom: flags.waitingRoom,
        showRecordingRows: flags.recording && state.isHost,
      ),
    );
  }

  _FeatureFlags _readFeatureFlags() {
    final unleash = _dataProviderManager.unleashDataProvider;
    try {
      final recordingSupported = !web && (iOS || macOS || android);
      return (
        waitingRoom: unleash.isMeetWaitingRoom(),
        recording: recordingSupported && unleash.isMeetMeetingRecordingNative(),
        preview: unleash.isMeetSettingsPreview(),
      );
    } catch (_) {
      return _allFlagsOff;
    }
  }

  void _onBindingsUpdated(
    InRoomSettingsBindingsUpdated event,
    Emitter<InRoomSettingsState> emit,
  ) {
    emit(
      state.withBindings(
        event,
        showRecordingRows: _readFeatureFlags().recording && event.isHost,
      ),
    );
  }

  Future<void> _onLockMeetingToggled(
    InRoomLockMeetingToggled event,
    Emitter<InRoomSettingsState> emit,
  ) async {
    await _runHostToggle(
      toggle: InRoomPendingToggle.lockMeeting,
      value: event.enabled,
      action: () => _transport.toggleLockMeeting(value: event.enabled),
      emit: emit,
      onSuccess: ({required bool value}) => state.copyWith(lockMeeting: value),
    );
  }

  void _onIncomingVideoToggled(
    InRoomIncomingVideoToggled event,
    Emitter<InRoomSettingsState> emit,
  ) {
    emit(state.copyWith(incomingVideoEnabled: event.enabled));
  }

  void _onSelfViewToggled(
    InRoomSelfViewToggled event,
    Emitter<InRoomSettingsState> emit,
  ) {
    emit(state.copyWith(selfViewEnabled: event.enabled));
  }

  void _onHostStatusUpdated(
    InRoomHostStatusUpdated event,
    Emitter<InRoomSettingsState> emit,
  ) {
    final flags = _readFeatureFlags();
    emit(
      state.copyWith(
        isHost: event.isHost,
        showRecordingRows: flags.recording && event.isHost,
      ),
    );
  }

  Future<void> _onWaitingRoomToggled(
    InRoomWaitingRoomToggled event,
    Emitter<InRoomSettingsState> emit,
  ) async {
    if (!state.canEditWaitingRoom) {
      return;
    }

    await _runHostToggle(
      toggle: InRoomPendingToggle.waitingRoom,
      value: event.enabled,
      action: () => _transport.toggleWaitingRoom(value: event.enabled),
      emit: emit,
      onSuccess: ({required bool value}) =>
          state.copyWith(waitingRoomEnabled: value),
    );
  }

  Future<void> _runHostToggle({
    required InRoomPendingToggle toggle,
    required bool value,
    required Future<bool> Function() action,
    required Emitter<InRoomSettingsState> emit,
    required InRoomSettingsState Function({required bool value}) onSuccess,
  }) async {
    if (!state.canEditHostToggles || state.isPending(toggle)) {
      return;
    }

    final pending = Set<InRoomPendingToggle>.from(state.pendingToggles)
      ..add(toggle);
    emit(state.copyWith(pendingToggles: pending));

    try {
      final accepted = await action();
      if (accepted && !isClosed) {
        emit(onSuccess(value: value));
      }
    } finally {
      if (!isClosed) {
        final cleared = Set<InRoomPendingToggle>.from(state.pendingToggles)
          ..remove(toggle);
        emit(state.copyWith(pendingToggles: cleared));
      }
    }
  }
}
