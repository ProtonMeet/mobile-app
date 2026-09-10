import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/proton.color.dart';
import 'package:meet/l10n/generated/locale.dart';
import 'package:meet/provider/theme.provider.dart';
import 'package:meet/views/scenes/dashboard/schedule/waiting_room_sheet.dart';
import 'package:provider/provider.dart';

Future<void> _pumpHost(
  WidgetTester tester, {
  required bool selected,
  required bool isPaidUser,
  required List<bool> selections,
  List<String> invalidMessages = const [],
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        localizationsDelegates: S.localizationsDelegates,
        supportedLocales: S.supportedLocales,
        locale: const Locale('en'),
        theme: ThemeData(extensions: [darkColorsExtension]),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showWaitingRoomSheet(
                  context,
                  selected: selected,
                  isPaidUser: isPaidUser,
                  onSelect: selections.add,
                  onInvalidSelection: invalidMessages.add,
                ),
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open sheet'));
  await tester.pumpAndSettle();
}

void main() {
  group('showWaitingRoomSheet', () {
    testWidgets('renders waiting room options', (tester) async {
      final selections = <bool>[];
      await _pumpHost(
        tester,
        selected: false,
        isPaidUser: true,
        selections: selections,
      );

      expect(find.text('Waiting room'), findsOneWidget);
      expect(find.text('On'), findsOneWidget);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text('Use waiting room with a paid plan'), findsOneWidget);
    });

    testWidgets('paid user selecting On applies selection and closes sheet', (
      tester,
    ) async {
      final selections = <bool>[];
      await _pumpHost(
        tester,
        selected: false,
        isPaidUser: true,
        selections: selections,
      );

      await tester.tap(find.text('On'));
      await tester.pumpAndSettle();

      expect(selections, [true]);
      expect(find.text('Waiting room'), findsNothing);
    });

    testWidgets('paid user selecting Off applies selection and closes sheet', (
      tester,
    ) async {
      final selections = <bool>[];
      await _pumpHost(
        tester,
        selected: true,
        isPaidUser: true,
        selections: selections,
      );

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();

      expect(selections, [false]);
      expect(find.text('Waiting room'), findsNothing);
    });

    testWidgets(
      'free user selecting On reports invalid selection and keeps sheet open',
      (tester) async {
        final selections = <bool>[];
        final invalidMessages = <String>[];
        await _pumpHost(
          tester,
          selected: false,
          isPaidUser: false,
          selections: selections,
          invalidMessages: invalidMessages,
        );

        await tester.tap(find.text('On'));
        await tester.pumpAndSettle();

        expect(selections, isEmpty);
        expect(invalidMessages, ['Available with a paid plan']);
        expect(find.text('Waiting room'), findsOneWidget);
      },
    );

    testWidgets('free user selecting Off applies selection and closes sheet', (
      tester,
    ) async {
      final selections = <bool>[];
      final invalidMessages = <String>[];
      await _pumpHost(
        tester,
        selected: true,
        isPaidUser: false,
        selections: selections,
        invalidMessages: invalidMessages,
      );

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();

      expect(selections, [false]);
      expect(invalidMessages, isEmpty);
      expect(find.text('Waiting room'), findsNothing);
    });
  });
}
