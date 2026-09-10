import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_bloc.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_event.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_state.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_transport.dart';
import 'package:mockito/mockito.dart';
import 'package:proton_denoise/proton_denoise.dart';

class StubUnleashDataProvider extends Mock implements UnleashDataProvider {
  StubUnleashDataProvider(this.streamController);

  final StreamController<DataState> streamController;

  bool waitingRoom = false;
  bool recordingNative = false;
  bool preview = false;
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
      UnleashFeature.meetMeetingRecordingNative => recordingNative,
      UnleashFeature.meetSettingsPreview => preview,
      _ => false,
    };
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

class FakeHostTransport implements InRoomHostSettingsTransport {
  final lockResults = <bool>[];
  final waitingRoomResults = <bool>[];
  var nextLockResult = true;
  var nextWaitingRoomResult = true;
  Completer<void>? holdLock;
  Completer<void>? holdWaitingRoom;

  @override
  Future<bool> toggleLockMeeting({required bool value}) async {
    lockResults.add(value);
    if (holdLock != null) {
      await holdLock!.future;
    }
    return nextLockResult;
  }

  @override
  Future<bool> toggleWaitingRoom({required bool value}) async {
    waitingRoomResults.add(value);
    if (holdWaitingRoom != null) {
      await holdWaitingRoom!.future;
    }
    return nextWaitingRoomResult;
  }
}

InRoomSettingsBindingsUpdated bindingsEvent({
  bool isHost = false,
  bool isPaidUser = false,
  bool incomingVideoEnabled = true,
  bool selfViewEnabled = true,
  bool showAudioDenoise = false,
  bool audioDenoiseEnabled = false,
  List<DenoiseTypeUiOption> audioDenoiseTypes = const [],
  DenoiseType? selectedAudioDenoiseType,
  bool showCameraBackground = false,
  CameraBackgroundSelection cameraBackgroundSelection =
      const CameraBackgroundSelection.none(),
  bool showConnectionSettings = false,
  bool isRejoining = false,
  bool forceShowConnectionStatusBanner = false,
}) {
  return InRoomSettingsBindingsUpdated(
    isHost: isHost,
    isPaidUser: isPaidUser,
    incomingVideoEnabled: incomingVideoEnabled,
    selfViewEnabled: selfViewEnabled,
    showAudioDenoise: showAudioDenoise,
    audioDenoiseEnabled: audioDenoiseEnabled,
    audioDenoiseTypes: audioDenoiseTypes,
    selectedAudioDenoiseType: selectedAudioDenoiseType,
    showCameraBackground: showCameraBackground,
    cameraBackgroundSelection: cameraBackgroundSelection,
    showConnectionSettings: showConnectionSettings,
    isRejoining: isRejoining,
    forceShowConnectionStatusBanner: forceShowConnectionStatusBanner,
  );
}

void main() {
  late StubUnleashDataProvider unleash;
  late TestDataProviderManager dataProviderManager;
  late FakeHostTransport transport;
  late StreamController<DataState> unleashStreamController;

  InRoomSettingsBloc buildBloc() {
    return InRoomSettingsBloc(
      dataProviderManager: dataProviderManager,
      transport: transport,
    );
  }

  void configureFlags({
    bool waitingRoom = false,
    bool recordingNative = false,
    bool preview = false,
    bool throwOnFeatureRead = false,
  }) {
    unleash.waitingRoom = waitingRoom;
    unleash.recordingNative = recordingNative;
    unleash.preview = preview;
    unleash.throwOnFeatureRead = throwOnFeatureRead;
  }

  setUp(() {
    unleashStreamController = StreamController<DataState>.broadcast();
    unleash = StubUnleashDataProvider(unleashStreamController);
    dataProviderManager = TestDataProviderManager(unleash);
    transport = FakeHostTransport();
    configureFlags();
  });

  tearDown(() async {
    await unleashStreamController.close();
    await dataProviderManager.dispose();
  });

  group('InRoomSettingsBloc', () {
    test('starts with default state', () {
      final bloc = buildBloc();
      expect(bloc.state, const InRoomSettingsState());
      bloc.close();
    });

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'initialized seeds host toggles and applies feature flags',
      build: () {
        unleash.preview = true;
        unleash.waitingRoom = true;
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        InRoomSettingsInitialized(lockMeeting: true, waitingRoomEnabled: false),
      ),
      expect: () => [
        const InRoomSettingsState(
          lockMeeting: true,
          showPreviewSettings: true,
          showWaitingRoom: true,
        ),
      ],
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'treats feature flag read failures as disabled',
      build: () {
        configureFlags(throwOnFeatureRead: true);
        return buildBloc();
      },
      act: (bloc) => bloc.add(
        InRoomSettingsInitialized(
          lockMeeting: false,
          waitingRoomEnabled: false,
        ),
      ),
      expect: () => [const InRoomSettingsState()],
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'bindings update clears stale audio denoise callback',
      build: buildBloc,
      seed: () => InRoomSettingsState(
        showAudioDenoise: true,
        audioDenoiseEnabled: true,
        audioDenoiseTypes: const [
          DenoiseTypeUiOption(type: DenoiseType.deepfilter),
          DenoiseTypeUiOption(type: DenoiseType.rnnoise),
        ],
        onAudioDenoiseTypeSelected: (_) {},
      ),
      act: (bloc) => bloc.add(
        bindingsEvent(
          showAudioDenoise: true,
          audioDenoiseEnabled: true,
          audioDenoiseTypes: const [
            DenoiseTypeUiOption(type: DenoiseType.deepfilter),
          ],
        ),
      ),
      verify: (bloc) {
        expect(bloc.state.onAudioDenoiseTypeSelected, isNull);
        expect(bloc.state.showAudioDenoiseTypes, isFalse);
      },
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'feature flags changed updates gated row visibility',
      build: () {
        configureFlags(waitingRoom: true, preview: true);
        return buildBloc();
      },
      seed: () => const InRoomSettingsState(isHost: true),
      act: (bloc) => bloc.add(InRoomSettingsFeatureFlagsChanged()),
      expect: () => [
        const InRoomSettingsState(
          isHost: true,
          showWaitingRoom: true,
          showPreviewSettings: true,
        ),
      ],
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'lock meeting toggle updates value and clears pending state',
      build: buildBloc,
      seed: () => const InRoomSettingsState(isHost: true),
      act: (bloc) => bloc.add(InRoomLockMeetingToggled(enabled: true)),
      expect: () => [
        const InRoomSettingsState(
          isHost: true,
          pendingToggles: {InRoomPendingToggle.lockMeeting},
        ),
        const InRoomSettingsState(
          isHost: true,
          lockMeeting: true,
          pendingToggles: {InRoomPendingToggle.lockMeeting},
        ),
        const InRoomSettingsState(isHost: true, lockMeeting: true),
      ],
      verify: (_) {
        expect(transport.lockResults, [true]);
      },
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'waiting room toggle is ignored for free users',
      build: buildBloc,
      seed: () => const InRoomSettingsState(isHost: true),
      act: (bloc) => bloc.add(InRoomWaitingRoomToggled(enabled: true)),
      expect: () => const <InRoomSettingsState>[],
      verify: (_) {
        expect(transport.waitingRoomResults, isEmpty);
      },
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'bindings update copies paid user status',
      build: buildBloc,
      act: (bloc) => bloc.add(bindingsEvent(isHost: true, isPaidUser: true)),
      expect: () => [
        const InRoomSettingsState(
          isHost: true,
          isPaidUser: true,
          bindingsRevision: 1,
        ),
      ],
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'waiting room toggle updates value and clears pending state',
      build: buildBloc,
      seed: () => const InRoomSettingsState(isHost: true, isPaidUser: true),
      act: (bloc) => bloc.add(InRoomWaitingRoomToggled(enabled: true)),
      expect: () => [
        const InRoomSettingsState(
          isHost: true,
          isPaidUser: true,
          pendingToggles: {InRoomPendingToggle.waitingRoom},
        ),
        const InRoomSettingsState(
          isHost: true,
          isPaidUser: true,
          waitingRoomEnabled: true,
          pendingToggles: {InRoomPendingToggle.waitingRoom},
        ),
        const InRoomSettingsState(
          isHost: true,
          isPaidUser: true,
          waitingRoomEnabled: true,
        ),
      ],
      verify: (_) {
        expect(transport.waitingRoomResults, [true]);
      },
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'rejected host toggle keeps previous value',
      build: () {
        transport.nextLockResult = false;
        return buildBloc();
      },
      seed: () => const InRoomSettingsState(isHost: true),
      act: (bloc) => bloc.add(InRoomLockMeetingToggled(enabled: true)),
      expect: () => [
        const InRoomSettingsState(
          isHost: true,
          pendingToggles: {InRoomPendingToggle.lockMeeting},
        ),
        const InRoomSettingsState(isHost: true),
      ],
      verify: (_) {
        expect(transport.lockResults, [true]);
      },
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'host toggle is ignored when user is not host',
      build: buildBloc,
      seed: () => const InRoomSettingsState(),
      act: (bloc) => bloc.add(InRoomLockMeetingToggled(enabled: true)),
      expect: () => const <InRoomSettingsState>[],
      verify: (_) {
        expect(transport.lockResults, isEmpty);
      },
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'host toggle is ignored while pending',
      build: buildBloc,
      seed: () => const InRoomSettingsState(
        isHost: true,
        pendingToggles: {InRoomPendingToggle.lockMeeting},
      ),
      act: (bloc) => bloc.add(InRoomLockMeetingToggled(enabled: false)),
      expect: () => const <InRoomSettingsState>[],
      verify: (_) {
        expect(transport.lockResults, isEmpty);
      },
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'host toggle sets pending before transport resolves',
      build: () {
        transport.holdLock = Completer<void>();
        return buildBloc();
      },
      seed: () => const InRoomSettingsState(isHost: true),
      act: (bloc) async {
        bloc.add(InRoomLockMeetingToggled(enabled: true));
        await bloc.stream.firstWhere(
          (state) => state.isPending(InRoomPendingToggle.lockMeeting),
        );
        expect(transport.lockResults, [true]);
        transport.holdLock?.complete();
        await bloc.stream.firstWhere(
          (state) => !state.isPending(InRoomPendingToggle.lockMeeting),
        );
      },
      verify: (_) {
        expect(transport.lockResults, [true]);
      },
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'bindings update exposes recording rows for hosts when flag is on',
      build: () {
        configureFlags(recordingNative: true);
        return buildBloc();
      },
      act: (bloc) => bloc.add(bindingsEvent(isHost: true)),
      expect: () => [
        const InRoomSettingsState(
          isHost: true,
          showRecordingRows: true,
          bindingsRevision: 1,
        ),
      ],
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'bindings update hides recording rows for non-hosts',
      build: () {
        configureFlags(recordingNative: true);
        return buildBloc();
      },
      act: (bloc) => bloc.add(bindingsEvent()),
      expect: () => [const InRoomSettingsState(bindingsRevision: 1)],
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'bindings update copies media settings and increments revision',
      build: buildBloc,
      seed: () => const InRoomSettingsState(bindingsRevision: 2),
      act: (bloc) => bloc.add(
        bindingsEvent(
          incomingVideoEnabled: false,
          selfViewEnabled: false,
          showAudioDenoise: true,
          audioDenoiseEnabled: true,
          audioDenoiseTypes: const [
            DenoiseTypeUiOption(type: DenoiseType.rnnoise),
          ],
          selectedAudioDenoiseType: DenoiseType.rnnoise,
          showCameraBackground: true,
          cameraBackgroundSelection: const CameraBackgroundSelection.blur(),
          showConnectionSettings: true,
          isRejoining: true,
          forceShowConnectionStatusBanner: true,
        ),
      ),
      expect: () => [
        const InRoomSettingsState(
          incomingVideoEnabled: false,
          selfViewEnabled: false,
          showAudioDenoise: true,
          audioDenoiseEnabled: true,
          audioDenoiseTypes: [DenoiseTypeUiOption(type: DenoiseType.rnnoise)],
          selectedAudioDenoiseType: DenoiseType.rnnoise,
          showCameraBackground: true,
          cameraBackgroundSelection: CameraBackgroundSelection.blur(),
          showConnectionSettings: true,
          isRejoining: true,
          forceShowConnectionStatusBanner: true,
          bindingsRevision: 3,
        ),
      ],
    );

    blocTest<InRoomSettingsBloc, InRoomSettingsState>(
      'unleash stream refresh reapplies feature flag visibility',
      build: () {
        configureFlags(waitingRoom: true, preview: true);
        return buildBloc();
      },
      seed: () => const InRoomSettingsState(isHost: true),
      act: (bloc) async {
        final emissions = bloc.stream.take(1).toList();
        unleashStreamController.add(UnleashFeatureFlagsUpdated(1));
        await emissions;
      },
      expect: () => [
        const InRoomSettingsState(
          isHost: true,
          showWaitingRoom: true,
          showPreviewSettings: true,
        ),
      ],
    );

    test('rebinds unleash subscription when provider is replaced', () async {
      final secondController = StreamController<DataState>.broadcast();
      final secondUnleash = StubUnleashDataProvider(secondController);
      secondUnleash.waitingRoom = true;
      secondUnleash.preview = true;

      final bloc = buildBloc();
      await Future<void>.delayed(Duration.zero);

      dataProviderManager.replaceUnleash(secondUnleash);
      secondController.add(UnleashFeatureFlagsUpdated(1));

      await bloc.stream.firstWhere((state) => state.showWaitingRoom);
      expect(bloc.state.showWaitingRoom, isTrue);
      expect(bloc.state.showPreviewSettings, isTrue);
      await bloc.close();
      await secondController.close();
    });

    test(
      'close cancels only this bloc unleash replacement subscription',
      () async {
        var replacementEvents = 0;
        final subscription = dataProviderManager.onUnleashDataProviderReplaced
            .listen((_) => replacementEvents++);

        final bloc = buildBloc();
        await bloc.close();

        dataProviderManager.replaceUnleash(
          StubUnleashDataProvider(StreamController<DataState>.broadcast()),
        );
        await Future<void>.delayed(Duration.zero);

        expect(replacementEvents, 1);
        await subscription.cancel();
        await dataProviderManager.dispose();
      },
    );
  });
}
