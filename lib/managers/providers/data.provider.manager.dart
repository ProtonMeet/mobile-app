import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/env.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';

import 'package:meet/managers/manager.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/managers/providers/event.loop.syncable.dart';
import 'package:meet/managers/providers/feature.flag.aware.dart';
import 'package:meet/managers/providers/meet.user.settings.data.provider.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/managers/secure.storage/secure.storage.manager.dart';
import 'package:meet/rust/proton_meet/models/event.dart';

/// data state
abstract class DataState extends Equatable {}

class DataInitial extends DataState {
  @override
  List<Object?> get props => [];
}

abstract class DataLoading extends DataState {}

abstract class DataLoaded extends DataState {
  final String data;

  DataLoaded(this.data);
}

abstract class DataCreated extends DataState {}

enum UpdateType { inserted, updated, deleted }

class DataUpdated<T> extends DataState {
  final T updatedData;

  DataUpdated(this.updatedData);

  @override
  List<Object?> get props => [updatedData];
}

abstract class DataDeleted extends DataState {}

class DataError extends DataState {
  final String message;

  DataError(this.message);

  @override
  List<Object?> get props => [message];
}

///
abstract class DataEvent extends Equatable {}

abstract class DataLoad extends DataEvent {}

abstract class DataCreate extends DataEvent {}

abstract class DataUpdate extends DataEvent {}

abstract class DataDelete extends DataEvent {}

class DirectEmitEvent extends DataEvent {
  final DataState state;

  DirectEmitEvent(this.state);

  @override
  List<Object?> get props => [state];
}

abstract class DataProvider extends Bloc<DataEvent, DataState> {
  DataProvider() : super(DataInitial()) {
    on<DirectEmitEvent>((event, emit) => emit(event.state));
  }

  void emitState(DataState state) {
    if (isClosed) {
      return;
    }
    add(DirectEmitEvent(state));
  }

  Future<void> clear();

  /// reload data
  Future<void> reload();
}

/// Owns app-wide [DataProvider] instances (orchestrator) and their lifecycle ([init], [login],
/// [logout], [reload]).
///
/// Fans out remote updates to providers that opt in via [EventLoopSyncable] or
/// [FeatureFlagAware].
class DataProviderManager extends Manager {
  final SecureStorageManager storage;
  final PreferencesManager shared;
  final ApiEnv apiEnv;
  final AppCoreManager appCoreManager;

  /// data providers
  late UnleashDataProvider unleashDataProvider;
  late MeetUserSettingsDataProvider meetUserSettingsDataProvider;

  /// List of providers that need to be synced from the event loop.
  late List<EventLoopSyncable> _eventLoopSyncables;

  /// List of providers that need to be synced from feature flags.
  late List<FeatureFlagAware> _featureFlagAwares;

  /// When true, [init]/[login]/[logout] keep the injected provider instances.
  bool _usesInjectedProviders = false;

  /// Notified after [unleashDataProvider] is replaced (login/logout).
  final _unleashReplacedController = StreamController<void>.broadcast();

  Stream<void> get onUnleashDataProviderReplaced =>
      _unleashReplacedController.stream;

  DataProviderManager(
    this.apiEnv,
    this.storage,
    this.shared,
    this.appCoreManager, { //testable constructor
    UnleashDataProvider? unleashDataProvider,
    MeetUserSettingsDataProvider? meetUserSettingsDataProvider,
    List<EventLoopSyncable>? eventLoopSyncables,
    List<FeatureFlagAware>? featureFlagAwares,
  }) {
    if (unleashDataProvider == null ||
        meetUserSettingsDataProvider == null ||
        eventLoopSyncables == null ||
        featureFlagAwares == null) {
      return;
    }

    _usesInjectedProviders = true;
    this.unleashDataProvider = unleashDataProvider;
    this.unleashDataProvider.onFeatureFlagsUpdated = syncFromFeatureFlags;
    this.meetUserSettingsDataProvider = meetUserSettingsDataProvider;
    _eventLoopSyncables = eventLoopSyncables;
    _featureFlagAwares = featureFlagAwares;
  }

  Future<void> _replaceUnleashDataProvider() async {
    final previous = unleashDataProvider;
    previous.onFeatureFlagsUpdated = null;
    await previous.clear();
    unawaited(previous.close());

    unleashDataProvider = UnleashDataProvider(apiEnv, appCoreManager);
    unleashDataProvider.onFeatureFlagsUpdated = syncFromFeatureFlags;
    if (!_unleashReplacedController.isClosed) {
      _unleashReplacedController.add(null);
    }
  }

  /// Refreshes providers whose data may have changed according to event-loop
  /// payloads. Each provider decides whether to sync and emits [DataState] when
  /// its value changes.
  Future<void> syncFromEventLoop({
    required FrbGetEventsResponse meetEvents,
    required FrbGetEventsResponse coreEvents,
  }) async {
    for (final provider in _eventLoopSyncables) {
      if (!provider.shouldSyncFromEventLoop(meetEvents) &&
          !provider.shouldSyncFromEventLoop(coreEvents)) {
        continue;
      }
      try {
        await provider.syncFromEventLoop();
      } catch (e, st) {
        logger.w(
          'Event-loop sync failed for $provider',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  /// Re-evaluates feature-flag-gated provider state after Unleash refreshes.
  Future<void> syncFromFeatureFlags() async {
    for (final provider in _featureFlagAwares) {
      try {
        await provider.syncFromFeatureFlags(unleashDataProvider);
      } catch (e, st) {
        logger.w(
          'Feature-flag sync failed for $provider',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  @override
  Future<void> login(String userID) async {
    if (_usesInjectedProviders) {
      await unleashDataProvider.clear();
      await unleashDataProvider.start();
    } else {
      await _replaceUnleashDataProvider();
      await unleashDataProvider.start();
    }

    await meetUserSettingsDataProvider.clear();
    await meetUserSettingsDataProvider.reload();
  }

  @override
  Future<void> dispose() async {
    await _unleashReplacedController.close();
  }

  @override
  Future<void> init() async {
    if (!_usesInjectedProviders) {
      // create the unleash data provider and wire up the feature flag sync
      unleashDataProvider = UnleashDataProvider(apiEnv, appCoreManager);
      unleashDataProvider.onFeatureFlagsUpdated = syncFromFeatureFlags;

      // create the meet user settings data provider
      meetUserSettingsDataProvider = MeetUserSettingsDataProvider(
        manager: appCoreManager,
      );

      // wire up the event loop syncables and feature flag awares
      _eventLoopSyncables = [meetUserSettingsDataProvider];
      _featureFlagAwares = [meetUserSettingsDataProvider];
    }

    // refresh the meet user settings data provider to ensure it initializes with bootstrap values
    try {
      await meetUserSettingsDataProvider.refreshIfNeeded().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          logger.w(
            'Meet user settings bootstrap timed out; continuing app startup',
          );
          return null;
        },
      );
    } catch (e, st) {
      logger.w(
        'Meet user settings bootstrap failed; continuing app startup',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  Future<void> logout() async {
    await unleashDataProvider.clear();
    await meetUserSettingsDataProvider.clear();

    if (_usesInjectedProviders) {
      await unleashDataProvider.start();
      return;
    }

    await _replaceUnleashDataProvider();
    await unleashDataProvider.start();
  }

  @override
  Future<void> reload() async {
    await unleashDataProvider.reload();
    await meetUserSettingsDataProvider.reload();
  }

  @override
  Priority getPriority() {
    return Priority.level3;
  }
}
