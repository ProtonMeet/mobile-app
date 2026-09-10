import 'package:equatable/equatable.dart';

/// Whether the waiting-room row is readable / writable right now.
enum WaitingRoomStatus { ready, updating }

class AppSettingsState extends Equatable {
  const AppSettingsState({
    this.showRecordingSettings = false,
    this.showPreviewSettings = false,
    this.isPaidUser = false,
    this.waitingRoomEnabled = false,
    this.waitingRoomStatus = WaitingRoomStatus.ready,
    this.waitingRoomError,
  });

  /// Local recording rows (save location, saved recordings).
  final bool showRecordingSettings;

  /// Rows that are designed but not wired yet; they render disabled.
  final bool showPreviewSettings;

  final bool isPaidUser;

  final bool waitingRoomEnabled;
  final WaitingRoomStatus waitingRoomStatus;

  /// Last failed waiting-room update, shown under the row.
  final String? waitingRoomError;

  bool get isWaitingRoomBusy => waitingRoomStatus != WaitingRoomStatus.ready;

  bool get canEditWaitingRoom => isPaidUser;

  AppSettingsState copyWith({
    bool? showRecordingSettings,
    bool? showWaitingRoomInAppSettings,
    bool? showPreviewSettings,
    bool? isPaidUser,
    bool? waitingRoomEnabled,
    WaitingRoomStatus? waitingRoomStatus,
    String? waitingRoomError,
    bool clearWaitingRoomError = false,
  }) {
    return AppSettingsState(
      showRecordingSettings:
          showRecordingSettings ?? this.showRecordingSettings,
      showPreviewSettings: showPreviewSettings ?? this.showPreviewSettings,
      isPaidUser: isPaidUser ?? this.isPaidUser,
      waitingRoomEnabled: waitingRoomEnabled ?? this.waitingRoomEnabled,
      waitingRoomStatus: waitingRoomStatus ?? this.waitingRoomStatus,
      waitingRoomError: clearWaitingRoomError
          ? null
          : waitingRoomError ?? this.waitingRoomError,
    );
  }

  @override
  List<Object?> get props => [
    showRecordingSettings,
    showPreviewSettings,
    isPaidUser,
    waitingRoomEnabled,
    waitingRoomStatus,
    waitingRoomError,
  ];
}
