import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/app.keys.dart';

import '../helper.dart';

void main() {
  group('AppKeys', () {
    testUnit('All keys should be non-null', () {
      expect(AppKeys.showParticipantsListButton, isNotNull);
      expect(AppKeys.showChatButton, isNotNull);
      expect(AppKeys.showSettingsButton, isNotNull);
      expect(AppKeys.showMeetingInfoButton, isNotNull);
      expect(AppKeys.leaveRoomButton, isNotNull);
      expect(AppKeys.chatMessageTextField, isNotNull);
      expect(AppKeys.chatSendButton, isNotNull);
      expect(AppKeys.chatFindButton, isNotNull);
      expect(AppKeys.chatFindCloseButton, isNotNull);
      expect(AppKeys.chatFindTextField, isNotNull);
    });

    testUnit('All keys should have unique values', () {
      final keys = [
        AppKeys.showParticipantsListButton,
        AppKeys.showChatButton,
        AppKeys.showSettingsButton,
        AppKeys.showMeetingInfoButton,
        AppKeys.leaveRoomButton,
        AppKeys.chatMessageTextField,
        AppKeys.chatSendButton,
        AppKeys.chatFindButton,
        AppKeys.chatFindCloseButton,
        AppKeys.chatFindTextField,
      ];

      final keyValues = keys.map((k) => k.toString()).toList();
      final uniqueValues = keyValues.toSet();
      expect(
        uniqueValues.length,
        equals(keyValues.length),
        reason: 'All AppKeys should have unique values',
      );
    });

    testUnit('showParticipantsListButton should have correct value', () {
      expect(
        AppKeys.showParticipantsListButton.toString(),
        equals("[<'show_participants_list_button'>]"),
      );
    });

    testUnit('showChatButton should have correct value', () {
      expect(
        AppKeys.showChatButton.toString(),
        equals("[<'show_chat_button'>]"),
      );
    });

    testUnit('showSettingsButton should have correct value', () {
      expect(
        AppKeys.showSettingsButton.toString(),
        equals("[<'show_settings_button'>]"),
      );
    });

    testUnit('showMeetingInfoButton should have correct value', () {
      expect(
        AppKeys.showMeetingInfoButton.toString(),
        equals("[<'show_meeting_info_button'>]"),
      );
    });

    testUnit('leaveRoomButton should have correct value', () {
      expect(
        AppKeys.leaveRoomButton.toString(),
        equals("[<'leave_room_button'>]"),
      );
    });

    testUnit('chatMessageTextField should have correct value', () {
      expect(
        AppKeys.chatMessageTextField.toString(),
        equals("[<'chat_message_text_field'>]"),
      );
    });

    testUnit('chatSendButton should have correct value', () {
      expect(
        AppKeys.chatSendButton.toString(),
        equals("[<'chat_send_button'>]"),
      );
    });

    testUnit('chatFindButton should have correct value', () {
      expect(
        AppKeys.chatFindButton.toString(),
        equals("[<'chat_find_button'>]"),
      );
    });

    testUnit('chatFindCloseButton should have correct value', () {
      expect(
        AppKeys.chatFindCloseButton.toString(),
        equals("[<'chat_find_close_button'>]"),
      );
    });

    testUnit('chatFindTextField should have correct value', () {
      expect(
        AppKeys.chatFindTextField.toString(),
        equals("[<'chat_find_text_field'>]"),
      );
    });

    testUnit('Keys should be const instances', () {
      // Const keys should be identical
      const key1 = Key('show_chat_button');
      const key2 = Key('show_chat_button');
      expect(identical(key1, key2), isTrue);
    });
  });
}
