import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/views/scenes/room/room_state.dart';

extension RoomStateExtension on RoomState {
  bool get isAlone {
    return room.remoteParticipants.isEmpty;
  }
}

extension MlsSyncStateExtension on MlsSyncState {
  /// Get the localized message for this MLS sync state
  String message(BuildContext context) {
    switch (this) {
      case MlsSyncState.checking:
        return context.local.connection_check_mls_checking;
      case MlsSyncState.retrying:
        return context.local.connection_issue_restoring;
      case MlsSyncState.failed:
        return context.local.connection_check_mls_failed;
      case MlsSyncState.success:
        return context.local.connection_check_mls_passed;
    }
  }

  /// Check if this state should show a banner
  bool get shouldShowBanner {
    return this == MlsSyncState.retrying || this == MlsSyncState.failed;
  }
}

extension RejoinStatusExtension on RejoinStatus {
  /// Get the localized message for this rejoin status
  String message(BuildContext context) {
    return "${context.local.connection_lost}\n${displayMessage(context)}";
  }
}
