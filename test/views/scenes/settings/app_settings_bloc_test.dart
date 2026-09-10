import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/meet.user.settings.data.provider.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/rust/proton_meet/models/user_settings.dart';
import 'package:meet/views/scenes/settings/app_settings_bloc.dart';
import 'package:meet/views/scenes/settings/app_settings_event.dart';
import 'package:meet/views/scenes/settings/app_settings_state.dart';
import 'package:mockito/mockito.dart';

import '../../../support/data_provider_manager_test_support.dart';

class StubUnleashDataProvider extends Mock implements UnleashDataProvider {
  StubUnleashDataProvider(this.streamController);

  final StreamController<DataState> streamController;

  bool waitingRoom = false;
  bool preview = false;
  bool recordingNative = false;
  bool throwOnFeatureRead = false;

  @override
  Stream<DataState> get stream => streamController.stream;

  @override
  bool isFeatureEnabled(UnleashFeature feature) {
    if (throwOnFeatureRead) {
      throw StateError('boom');
    }
    return switch (feature) {
      UnleashFeature.meetWaitingRoom => waitingRoom,
      UnleashFeature.meetSettingsPreview => preview,
      UnleashFeature.meetMeetingRecordingNative => recordingNative,
      _ => false,
    };
  }
}

class StubMeetUserSettingsDataProvider extends Mock
    implements MeetUserSettingsDataProvider {
  StubMeetUserSettingsDataProvider(this.streamController);

  final StreamController<DataState> streamController;

  FrbUserSettings? loadedSettings;
  Object? updateError;
  FrbUserSettings? updateResult;
  int ensureLoadedCalls = 0;
  Duration ensureLoadedDelay = Duration.zero;
  Completer<void>? holdUpdate;
  final List<bool> updateWaitingRoomCalls = [];

  @override
  Stream<DataState> get stream => streamController.stream;

  @override
  Future<FrbUserSettings?> ensureLoaded() async {
    ensureLoadedCalls++;
    if (ensureLoadedDelay > Duration.zero) {
      await Future<void>.delayed(ensureLoadedDelay);
    }
    return loadedSettings;
  }

  @override
  Future<FrbUserSettings> updateWaitingRoom({required bool enable}) async {
    updateWaitingRoomCalls.add(enable);
    if (updateError != null) {
      throw updateError!;
    }
    if (holdUpdate != null) {
      await holdUpdate!.future;
    }
    return updateResult ??
        FrbUserSettings(addressId: 'meeting-1', waitingRoom: enable);
  }
}

class TestDataProviderManager implements DataProviderManager {
  TestDataProviderManager(this._unleash);

  UnleashDataProvider _unleash;
  final _unleashReplacedController = StreamController<void>.broadcast();

  @override
  UnleashDataProvider get unleashDataProvider => _unleash;

  @override
  Stream<void> get onUnleashDataProviderReplaced =>
      _unleashReplacedController.stream;

  void replaceUnleash(UnleashDataProvider next) {
    _unleash = next;
    _unleashReplacedController.add(null);
  }

  @override
  Future<void> dispose() => _unleashReplacedController.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Matcher appSettings({
  bool? showRecordingSettings,
  bool? showPreviewSettings,
  bool? isPaidUser,
  bool? waitingRoomEnabled,
  WaitingRoomStatus? waitingRoomStatus,
  String? waitingRoomError,
}) {
  return predicate<AppSettingsState>((state) {
    if (showRecordingSettings != null &&
        state.showRecordingSettings != showRecordingSettings) {
      return false;
    }
    if (showPreviewSettings != null &&
        state.showPreviewSettings != showPreviewSettings) {
      return false;
    }
    if (isPaidUser != null && state.isPaidUser != isPaidUser) {
      return false;
    }
    if (waitingRoomEnabled != null &&
        state.waitingRoomEnabled != waitingRoomEnabled) {
      return false;
    }
    if (waitingRoomStatus != null &&
        state.waitingRoomStatus != waitingRoomStatus) {
      return false;
    }
    if (waitingRoomError != null &&
        state.waitingRoomError != waitingRoomError) {
      return false;
    }
    return true;
  }, 'AppSettingsState matches expected fields');
}

void main() {
  late StubUnleashDataProvider unleash;
  late StubMeetUserSettingsDataProvider meetUserSettings;
  late TestDataProviderManager dataProviderManager;
  late StreamController<DataState> unleashStreamController;
  late StreamController<DataState> meetUserSettingsStreamController;

  AppSettingsBloc buildBloc() {
    return AppSettingsBloc(
      dataProviderManager: dataProviderManager,
      meetUserSettingsDataProvider: meetUserSettings,
    );
  }

  void configureFlags({
    bool waitingRoom = false,
    bool preview = false,
    bool recordingNative = false,
    bool throwOnFeatureRead = false,
  }) {
    unleash.waitingRoom = waitingRoom;
    unleash.preview = preview;
    unleash.recordingNative = recordingNative;
    unleash.throwOnFeatureRead = throwOnFeatureRead;
  }

  setUp(() {
    unleashStreamController = StreamController<DataState>.broadcast();
    meetUserSettingsStreamController = StreamController<DataState>.broadcast();
    unleash = StubUnleashDataProvider(unleashStreamController);
    meetUserSettings = StubMeetUserSettingsDataProvider(
      meetUserSettingsStreamController,
    );
    dataProviderManager = TestDataProviderManager(unleash);
    configureFlags();
  });

  tearDown(() async {
    await unleashStreamController.close();
    await meetUserSettingsStreamController.close();
  });

  group('AppSettingsBloc', () {
    test('starts with default state', () {
      final bloc = buildBloc();
      expect(bloc.state, const AppSettingsState());
      bloc.close();
    });

    blocTest<AppSettingsBloc, AppSettingsState>(
      'initialized hides gated rows when flags are off',
      build: buildBloc,
      act: (bloc) => bloc.add(AppSettingsInitialized()),
      expect: () => [appSettings()],
      verify: (_) {
        expect(meetUserSettings.ensureLoadedCalls, 0);
      },
    );

    blocTest<AppSettingsBloc, AppSettingsState>(
      'initialized loads waiting room when flag is on',
      build: () {
        configureFlags(waitingRoom: true, preview: true);
        meetUserSettings.loadedSettings = testUserSettings;
        return buildBloc();
      },
      act: (bloc) => bloc.add(AppSettingsInitialized()),
      expect: () => [
        appSettings(isPaidUser: false),
        appSettings(showPreviewSettings: true),
        appSettings(
          showPreviewSettings: true,
          waitingRoomEnabled: true,
          waitingRoomStatus: WaitingRoomStatus.ready,
        ),
      ],
      verify: (_) {
        expect(meetUserSettings.ensureLoadedCalls, 1);
      },
    );

    blocTest<AppSettingsBloc, AppSettingsState>(
      'feature flags changed loads settings when waiting room flag is on',
      build: () {
        configureFlags(waitingRoom: true);
        meetUserSettings.loadedSettings = testUserSettings;
        return buildBloc();
      },
      act: (bloc) => bloc.add(AppSettingsFeatureFlagsChanged()),
      expect: () => [
        appSettings(),
        appSettings(
          waitingRoomEnabled: true,
          waitingRoomStatus: WaitingRoomStatus.ready,
        ),
      ],
      verify: (_) {
        expect(meetUserSettings.ensureLoadedCalls, 1);
      },
    );

    blocTest<AppSettingsBloc, AppSettingsState>(
      'treats feature flag read failures as disabled',
      build: () {
        configureFlags(throwOnFeatureRead: true);
        return buildBloc();
      },
      act: (bloc) => bloc.add(AppSettingsInitialized()),
      expect: () => [appSettings()],
    );

    blocTest<AppSettingsBloc, AppSettingsState>(
      'waiting room toggle updates server value on success',
      build: () {
        meetUserSettings.updateResult = testUserSettings;
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        AppSettingsWaitingRoomToggled(enabled: true, isPaidUser: true),
      ),
      expect: () => [
        appSettings(
          waitingRoomEnabled: true,
          waitingRoomStatus: WaitingRoomStatus.updating,
        ),
        appSettings(
          waitingRoomEnabled: true,
          waitingRoomStatus: WaitingRoomStatus.ready,
        ),
      ],
      verify: (_) {
        expect(meetUserSettings.updateWaitingRoomCalls, [true]);
      },
    );

    blocTest<AppSettingsBloc, AppSettingsState>(
      'waiting room toggle reverts and surfaces bridge errors',
      build: () {
        meetUserSettings.updateError = const BridgeError_ApiResponse(
          ResponseError(code: 500, error: 'Server error', details: ''),
        );
        return buildBloc();
      },
      seed: () => const AppSettingsState(waitingRoomEnabled: true),
      act: (bloc) => bloc.add(
        AppSettingsWaitingRoomToggled(enabled: false, isPaidUser: true),
      ),
      expect: () => [
        appSettings(
          waitingRoomEnabled: false,
          waitingRoomStatus: WaitingRoomStatus.updating,
        ),
        appSettings(
          waitingRoomEnabled: true,
          waitingRoomStatus: WaitingRoomStatus.ready,
          waitingRoomError: 'Server error',
        ),
      ],
    );

    blocTest<AppSettingsBloc, AppSettingsState>(
      'waiting room toggle is ignored for unpaid users',
      build: buildBloc,
      act: (bloc) => bloc.add(
        AppSettingsWaitingRoomToggled(enabled: true, isPaidUser: false),
      ),
      expect: () => const <AppSettingsState>[],
      verify: (_) {
        expect(meetUserSettings.updateWaitingRoomCalls, isEmpty);
      },
    );

    blocTest<AppSettingsBloc, AppSettingsState>(
      'meet user settings stream updates waiting room when idle',
      build: buildBloc,
      seed: () => const AppSettingsState(),
      act: (bloc) async {
        meetUserSettingsStreamController.add(
          MeetUserSettingsLoaded(testUserSettings),
        );
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => [
        appSettings(
          waitingRoomEnabled: true,
          waitingRoomStatus: WaitingRoomStatus.ready,
        ),
      ],
    );

    blocTest<AppSettingsBloc, AppSettingsState>(
      'meet user settings stream is ignored while waiting room is updating',
      build: buildBloc,
      seed: () =>
          const AppSettingsState(waitingRoomStatus: WaitingRoomStatus.updating),
      act: (bloc) async {
        meetUserSettingsStreamController.add(
          MeetUserSettingsLoaded(
            const FrbUserSettings(addressId: 'meeting-1', waitingRoom: true),
          ),
        );
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => const <AppSettingsState>[],
    );

    blocTest<AppSettingsBloc, AppSettingsState>(
      'feature flag refresh does not clobber in-flight waiting room toggle',
      build: () {
        configureFlags(waitingRoom: true);
        meetUserSettings.loadedSettings = testUserSettings;
        meetUserSettings.ensureLoadedDelay = const Duration(milliseconds: 50);
        meetUserSettings.holdUpdate = Completer<void>();
        return buildBloc();
      },
      act: (bloc) async {
        bloc.add(
          AppSettingsWaitingRoomToggled(enabled: true, isPaidUser: true),
        );
        await Future<void>.delayed(Duration.zero);
        bloc.add(AppSettingsFeatureFlagsChanged());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
      verify: (bloc) {
        expect(bloc.state.waitingRoomStatus, WaitingRoomStatus.updating);
        expect(bloc.state.waitingRoomEnabled, isTrue);
      },
    );

    blocTest<AppSettingsBloc, AppSettingsState>(
      'unleash stream refresh reapplies feature flag visibility',
      build: () {
        configureFlags(waitingRoom: true);
        meetUserSettings.loadedSettings = testUserSettings;
        return buildBloc();
      },
      act: (bloc) async {
        final emissions = bloc.stream.take(2).toList();
        unleashStreamController.add(UnleashFeatureFlagsUpdated(1));
        await emissions;
      },
      expect: () => [
        appSettings(),
        appSettings(waitingRoomEnabled: true),
      ],
    );

    test('rebinds unleash subscription when provider is replaced', () async {
      final secondController = StreamController<DataState>.broadcast();
      final secondUnleash = StubUnleashDataProvider(secondController);
      secondUnleash.waitingRoom = true;
      meetUserSettings.loadedSettings = testUserSettings;

      final bloc = buildBloc();
      await Future<void>.delayed(Duration.zero);

      dataProviderManager.replaceUnleash(secondUnleash);
      secondController.add(UnleashFeatureFlagsUpdated(1));

      await bloc.stream.firstWhere((state) => state.waitingRoomEnabled);
      expect(bloc.state.waitingRoomEnabled, isTrue);
      await bloc.close();
      await secondController.close();
    });
  });
}
