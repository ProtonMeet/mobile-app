import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/bridge_error.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/meet.user.settings.data.provider.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';

import 'app_settings_event.dart';
import 'app_settings_state.dart';

/// Feature flags that decide which settings rows are visible.
typedef _FeatureFlags = ({bool waitingRoom, bool recording, bool preview});

const _FeatureFlags _allFlagsOff = (
  waitingRoom: false,
  recording: false,
  preview: false,
);

/// Owns app-level settings state so the settings sheet stays presentational.
class AppSettingsBloc extends Bloc<AppSettingsEvent, AppSettingsState> {
  AppSettingsBloc({
    required DataProviderManager dataProviderManager,
    required MeetUserSettingsDataProvider meetUserSettingsDataProvider,
  }) : _dataProviderManager = dataProviderManager,
       _meetUserSettingsDataProvider = meetUserSettingsDataProvider,
       super(const AppSettingsState()) {
    on<AppSettingsInitialized>(_onInitialized);
    on<AppSettingsWaitingRoomToggled>(_onWaitingRoomToggled);
    on<AppSettingsMeetUserSettingsChanged>(_onMeetUserSettingsChanged);
    on<AppSettingsFeatureFlagsChanged>(_onFeatureFlagsChanged);

    _meetUserSettingsSubscription = _meetUserSettingsDataProvider.stream.listen(
      (dataState) {
        if (dataState is MeetUserSettingsLoaded && !isClosed) {
          add(AppSettingsMeetUserSettingsChanged(settings: dataState.settings));
        }
      },
    );

    _bindUnleashProvider(refresh: false);
    _unleashReplacedSubscription = _dataProviderManager
        .onUnleashDataProviderReplaced
        .listen((_) => _bindUnleashProvider());
  }

  final DataProviderManager _dataProviderManager;
  final MeetUserSettingsDataProvider _meetUserSettingsDataProvider;
  late final StreamSubscription<DataState> _meetUserSettingsSubscription;
  late final StreamSubscription<void> _unleashReplacedSubscription;
  StreamSubscription<DataState>? _unleashSubscription;

  void _bindUnleashProvider({bool refresh = true}) {
    unawaited(_unleashSubscription?.cancel());
    _unleashSubscription = _dataProviderManager.unleashDataProvider.stream
        .listen((dataState) {
          if (dataState is UnleashFeatureFlagsUpdated && !isClosed) {
            add(AppSettingsFeatureFlagsChanged());
          }
        });
    if (!isClosed && refresh) {
      add(AppSettingsFeatureFlagsChanged());
    }
  }

  @override
  Future<void> close() {
    unawaited(_meetUserSettingsSubscription.cancel());
    unawaited(_unleashReplacedSubscription.cancel());
    unawaited(_unleashSubscription?.cancel());
    return super.close();
  }

  Future<void> _onInitialized(
    AppSettingsInitialized event,
    Emitter<AppSettingsState> emit,
  ) async {
    emit(state.copyWith(isPaidUser: event.isPaidUser));
    await _applyFeatureFlagVisibility(emit);
  }

  Future<void> _onFeatureFlagsChanged(
    AppSettingsFeatureFlagsChanged event,
    Emitter<AppSettingsState> emit,
  ) async {
    await _applyFeatureFlagVisibility(emit);
  }

  Future<void> _applyFeatureFlagVisibility(
    Emitter<AppSettingsState> emit,
  ) async {
    final flags = _readFeatureFlags();

    emit(
      state.copyWith(
        showRecordingSettings: flags.recording,
        showPreviewSettings: flags.preview,
      ),
    );

    if (!flags.waitingRoom || state.isWaitingRoomBusy) {
      return;
    }

    final settings = await _meetUserSettingsDataProvider.ensureLoaded();
    if (state.isWaitingRoomBusy) {
      return;
    }

    emit(
      state.copyWith(
        waitingRoomEnabled: settings?.waitingRoom ?? false,
        waitingRoomStatus: WaitingRoomStatus.ready,
      ),
    );
  }

  /// Reads go through the Unleash client, which throws if it is not ready yet.
  /// Hiding a row is a safer fallback than failing to open the settings sheet,
  /// so a failed read is treated as every flag being off.
  _FeatureFlags _readFeatureFlags() {
    final unleash = _dataProviderManager.unleashDataProvider;
    try {
      final recordingSupported = !web && (iOS || macOS || android);
      return (
        waitingRoom: unleash.isMeetWaitingRoom(),
        recording: recordingSupported && unleash.isMeetMeetingRecordingNative(),
        preview: unleash.isMeetSettingsPreview(),
      );
    } catch (e, stackTrace) {
      logBridgeError(
        'AppSettingsBloc',
        'Feature flag read failed',
        e,
        stackTrace: stackTrace,
        isWarning: true,
      );
      return _allFlagsOff;
    }
  }

  Future<void> _onWaitingRoomToggled(
    AppSettingsWaitingRoomToggled event,
    Emitter<AppSettingsState> emit,
  ) async {
    if (!event.isPaidUser || state.isWaitingRoomBusy) {
      return;
    }

    final previous = state.waitingRoomEnabled;
    emit(
      state.copyWith(
        waitingRoomEnabled: event.enabled,
        waitingRoomStatus: WaitingRoomStatus.updating,
        clearWaitingRoomError: true,
      ),
    );

    try {
      final settings = await _meetUserSettingsDataProvider.updateWaitingRoom(
        enable: event.enabled,
      );
      emit(
        state.copyWith(
          waitingRoomEnabled: settings.waitingRoom,
          waitingRoomStatus: WaitingRoomStatus.ready,
        ),
      );
    } catch (e, stackTrace) {
      logBridgeError(
        'AppSettingsBloc',
        'Waiting room update failed',
        e,
        stackTrace: stackTrace,
        isWarning: true,
      );
      emit(
        state.copyWith(
          waitingRoomEnabled: previous,
          waitingRoomStatus: WaitingRoomStatus.ready,
          waitingRoomError: extractErrorMessage(e),
        ),
      );
    }
  }

  void _onMeetUserSettingsChanged(
    AppSettingsMeetUserSettingsChanged event,
    Emitter<AppSettingsState> emit,
  ) {
    if (state.isWaitingRoomBusy) {
      return;
    }

    emit(
      state.copyWith(
        waitingRoomEnabled: event.settings.waitingRoom,
        waitingRoomStatus: WaitingRoomStatus.ready,
        clearWaitingRoomError: true,
      ),
    );
  }
}
