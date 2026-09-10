import 'package:meet/rust/proton_meet/models/user_settings.dart';

abstract class AppSettingsEvent {}

class AppSettingsInitialized extends AppSettingsEvent {
  AppSettingsInitialized({this.isPaidUser = false});

  final bool isPaidUser;
}

/// Host default for newly created meetings, persisted server-side.
class AppSettingsWaitingRoomToggled extends AppSettingsEvent {
  AppSettingsWaitingRoomToggled({
    required this.enabled,
    required this.isPaidUser,
  });

  final bool enabled;
  final bool isPaidUser;
}

/// Pushed when [MeetUserSettingsDataProvider] emits a new value (event loop,
/// login refresh, or another device updating settings).
class AppSettingsMeetUserSettingsChanged extends AppSettingsEvent {
  AppSettingsMeetUserSettingsChanged({required this.settings});

  final FrbUserSettings settings;
}

/// Pushed when [UnleashDataProvider] refreshes feature flags.
class AppSettingsFeatureFlagsChanged extends AppSettingsEvent {
  AppSettingsFeatureFlagsChanged();
}
