import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/proton.color.dart';
import 'package:meet/l10n/generated/locale.dart';
import 'package:meet/provider/theme.provider.dart';
import 'package:meet/views/scenes/dashboard/upcoming/meet_upcoming_title.dart';
import 'package:provider/provider.dart';

Widget _wrap(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => ThemeProvider(),
    child: MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      locale: const Locale('en'),
      theme: ThemeData(extensions: [darkColorsExtension]),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('MeetUpcomingTitle tab buttons', () {
    testWidgets('renders scrollable tab bar without alignment assert', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MeetUpcomingTitle(
            myMeetingsCount: 2,
            myRoomsCount: 1,
            tabStyle: MeetUpcomingTabStyle.tabButton,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TabBar), findsOneWidget);
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.isScrollable, isTrue);
      expect(tabBar.tabAlignment, TabAlignment.start);
      expect(find.text('My meetings'), findsOneWidget);
      expect(find.text('My rooms'), findsOneWidget);
    });
  });
}
