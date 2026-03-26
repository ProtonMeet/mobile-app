import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/env.dart';
import 'package:meet/managers/app.core.manager.dart';

import 'package:meet/managers/manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/preferences/preferences.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/managers/secure.storage/secure.storage.manager.dart';

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
    add(DirectEmitEvent(state));
  }

  Future<void> clear();

  /// reload data
  Future<void> reload();
}

class DataProviderManager extends Manager {
  final SecureStorageManager storage;
  final PreferencesManager shared;
  final ApiEnv apiEnv;

  // late GatewayDataProvider gatewayDataProvider;
  // late ProtonAddressProvider protonAddressProvider;
  // late BlockInfoDataProvider blockInfoDataProvider;
  // late BackupAlertTimerProvider backupAlertTimerProvider;
  late UnleashDataProvider unleashDataProvider;

  DataProviderManager(this.apiEnv, this.storage, this.shared);

  @override
  Future<void> login(String userID) async {
    await unleashDataProvider.clear();
    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    unleashDataProvider = UnleashDataProvider(apiEnv, appCoreManager);
    await unleashDataProvider.start();
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<void> init() async {
    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    unleashDataProvider = UnleashDataProvider(apiEnv, appCoreManager);
  }

  @override
  Future<void> logout() async {
    await unleashDataProvider.clear();
    // Create a new client with bootstrapOverride=true to reset any cached state
    // Start it to ensure it initializes with bootstrap values
    final appCoreManager = ManagerFactory().get<AppCoreManager>();
    unleashDataProvider = UnleashDataProvider(
      apiEnv,
      appCoreManager,
      bootstrapOverride: true,
    );
    await unleashDataProvider.start();
  }

  @override
  Future<void> reload() async {
    await unleashDataProvider.reload();
  }

  @override
  Priority getPriority() {
    return Priority.level4;
  }
}
