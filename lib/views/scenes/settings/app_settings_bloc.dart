import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';

import 'app_settings_event.dart';
import 'app_settings_state.dart';

class AppSettingsBloc extends Bloc<AppSettingsEvent, AppSettingsState> {
  AppSettingsBloc({ManagerFactory? managerFactory})
    : _managerFactory = managerFactory ?? ManagerFactory(),
      super(const AppSettingsState()) {
    on<AppSettingsInitialized>(_onInitialized);
  }

  final ManagerFactory _managerFactory;

  void _onInitialized(
    AppSettingsInitialized event,
    Emitter<AppSettingsState> emit,
  ) {
    emit(
      state.copyWith(showRecordingSettings: _resolveShowRecordingSettings()),
    );
  }

  bool _resolveShowRecordingSettings() {
    if (kIsWeb || !(iOS || macOS || android)) {
      return false;
    }
    return _isMeetMeetingRecordingNativeEnabled();
  }

  bool _isMeetMeetingRecordingNativeEnabled() {
    try {
      return _managerFactory
          .get<DataProviderManager>()
          .unleashDataProvider
          .isMeetMeetingRecordingNative();
    } catch (e) {
      l.logger.w(
        '[AppSettingsBloc] MeetingRecordingNative flag check failed: $e',
      );
      return false;
    }
  }
}
