import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/app.keys.dart';
import 'package:meet/constants/proton.color.dart';
import 'package:meet/l10n/generated/locale.dart';
import 'package:meet/provider/theme.provider.dart';
import 'package:meet/views/scenes/room/chat/chat_controller.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';
import 'package:meet/views/scenes/room/chat/chat_widget.dart';
import 'package:provider/provider.dart';

Future<void> pumpChatWidget(
  WidgetTester tester, {
  required ChatController controller,
  String localIdentity = 'local-user',
  String localName = 'Local User',
  Future<void> Function(String text, {String? replyToId, String? topicId})?
  onSend,
  Future<void> Function(String messageId, String emoji)? onToggleReaction,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        theme: ThemeData(extensions: [darkColorsExtension]),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 800,
            child: ChatWidget(
              controller: controller,
              localIdentity: localIdentity,
              localName: localName,
              onSend: onSend ?? (_, {replyToId, topicId}) async {},
              onToggleReaction: onToggleReaction ?? (_, _) async {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> tapChatSend(WidgetTester tester) async {
  await tester.tap(
    find.byWidgetPredicate((widget) {
      if (widget is! GestureDetector || widget.child is! Container) {
        return false;
      }
      final decoration = (widget.child! as Container).decoration;
      return decoration is ShapeDecoration &&
          decoration.color == const Color(0xFFABABF8);
    }),
  );
}

Future<void> settleChatTimers(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('ChatWidget', () {
    testWidgets('shows title, privacy empty state, and composer', (
      tester,
    ) async {
      final controller = ChatController(localIdentity: 'local-user');
      addTearDown(controller.dispose);

      await pumpChatWidget(tester, controller: controller);

      expect(find.text('Chat'), findsWidgets);
      expect(find.textContaining('end to end encrypted chat'), findsOneWidget);
      expect(find.text('Type an encrypted message…'), findsOneWidget);
      expect(find.byKey(AppKeys.chatMessageTextField), findsOneWidget);
      await settleChatTimers(tester);
    });

    testWidgets('renders an incoming root message', (tester) async {
      final controller = ChatController(localIdentity: 'local-user');
      addTearDown(controller.dispose);

      await pumpChatWidget(tester, controller: controller);
      controller.receiveMessage(
        RoomChatMessage(
          id: 'msg-1',
          message: 'Hello from Alice',
          timestamp: 1,
          identity: 'alice',
          name: 'Alice',
        ),
      );
      await tester.pump();

      expect(find.textContaining('Hello from Alice'), findsOneWidget);
      expect(find.textContaining('Alice'), findsWidgets);
      await settleChatTimers(tester);
    });

    testWidgets('submits trimmed text through onSend', (tester) async {
      final controller = ChatController(localIdentity: 'local-user');
      addTearDown(controller.dispose);
      final sent = <String>[];

      await pumpChatWidget(
        tester,
        controller: controller,
        onSend: (text, {replyToId, topicId}) async {
          sent.add(text);
        },
      );

      await tester.enterText(
        find.byKey(AppKeys.chatMessageTextField),
        '  Hi team  ',
      );
      await tapChatSend(tester);
      await tester.pump();

      expect(sent, ['Hi team']);
      expect(
        tester
            .widget<TextField>(find.byKey(AppKeys.chatMessageTextField))
            .controller
            ?.text,
        isEmpty,
      );
      await settleChatTimers(tester);
    });

    testWidgets('does not send empty messages', (tester) async {
      final controller = ChatController(localIdentity: 'local-user');
      addTearDown(controller.dispose);
      var sendCount = 0;

      await pumpChatWidget(
        tester,
        controller: controller,
        onSend: (_, {replyToId, topicId}) async {
          sendCount++;
        },
      );

      await tester.enterText(find.byKey(AppKeys.chatMessageTextField), '   ');
      await tapChatSend(tester);
      await tester.pump();

      expect(sendCount, 0);
      await settleChatTimers(tester);
    });
  });
}
