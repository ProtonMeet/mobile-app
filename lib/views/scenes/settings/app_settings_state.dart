class AppSettingsState {
  const AppSettingsState({this.showRecordingSettings = false});

  final bool showRecordingSettings;

  AppSettingsState copyWith({bool? showRecordingSettings}) {
    return AppSettingsState(
      showRecordingSettings:
          showRecordingSettings ?? this.showRecordingSettings,
    );
  }
}
