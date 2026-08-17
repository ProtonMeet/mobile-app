import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/bridge_error.extension.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/views/components/alerts/join_meeting_blocked_error.dart';
import 'package:meet/views/components/alerts/meeting_locked_error.dart';
import 'package:meet/views/components/bottom.sheets/upgrade_due_to_meet_server_version_not_support_sheet.dart';

import 'waiting_room_error_code.dart';

extension WaitingRoomErrorCodeExtension on WaitingRoomErrorCode {
  static WaitingRoomErrorCode? tryParse(String? value) {
    if (value == null) {
      return null;
    }
    for (final code in WaitingRoomErrorCode.values) {
      if (code.name == value) {
        return code;
      }
    }
    return null;
  }

  static WaitingRoomErrorCode? fromBridgeError(Object error) {
    return switch (error) {
      BridgeError_MeetingLocked() => WaitingRoomErrorCode.meetingLocked,
      BridgeError_IncorrectPassword() => WaitingRoomErrorCode.incorrectPassword,
      BridgeError_MlsServerVersionNotSupported() =>
        WaitingRoomErrorCode.mlsServerVersionNotSupported,
      BridgeError_CheckDeviceClock() => WaitingRoomErrorCode.checkDeviceClock,
      BridgeError_TokenIsInvalid() => WaitingRoomErrorCode.tokenIsInvalid,
      BridgeError_TokenIsExpired() => WaitingRoomErrorCode.tokenIsExpired,
      _ => null,
    };
  }

  /// Shows a dedicated bottom sheet when this error has one. Returns true if shown.
  bool showDedicatedBottomSheet(BuildContext context, {String? meetingLink}) {
    switch (this) {
      case WaitingRoomErrorCode.meetingLocked:
        showMeetingLockedBottomSheet(context, meetingLink: meetingLink);
        return true;
      case WaitingRoomErrorCode.mlsServerVersionNotSupported:
        showUpgradeDueToMeetServerVersionNotSupportSheet(context);
        return true;
      case WaitingRoomErrorCode.checkDeviceClock:
        showJoinMeetingBlockedBottomSheet(
          context,
          title: context.local.check_device_clock_title,
          description: context.local.check_device_clock_description,
          routeName: 'check_device_clock',
        );
        return true;
      case WaitingRoomErrorCode.tokenIsInvalid:
        showJoinMeetingBlockedBottomSheet(
          context,
          title: context.local.token_is_invalid_title,
          description: context.local.token_is_invalid_description,
          routeName: 'token_is_invalid',
        );
        return true;
      case WaitingRoomErrorCode.tokenIsExpired:
        showJoinMeetingBlockedBottomSheet(
          context,
          title: context.local.token_is_expired_title,
          description: context.local.token_is_expired_description,
          routeName: 'token_is_expired',
        );
        return true;
      case WaitingRoomErrorCode.incorrectPassword:
      case WaitingRoomErrorCode.generic:
        return false;
    }
  }
}

/// Maps typed [BridgeError] variants to [WaitingRoomErrorCode] names for the UI.
String waitingRoomErrorFromException(Object error) {
  final code = WaitingRoomErrorCodeExtension.fromBridgeError(error);
  if (code != null) {
    return code.name;
  }
  return extractErrorMessage(error);
}
