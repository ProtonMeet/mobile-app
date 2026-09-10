import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/proton.color.dart';
import 'package:meet/l10n/generated/locale.dart';
import 'package:meet/views/components/settings/settings_group.dart';
import 'package:meet/views/components/settings/settings_row.dart';
import 'package:meet/views/components/settings/settings_section.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    theme: ThemeData(extensions: [darkColorsExtension]),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

BorderRadius _radiusOfRowAt(WidgetTester tester, int index) {
  final material = tester.widget<Material>(
    find
        .ancestor(
          of: find.byType(SettingsRow).at(index),
          matching: find.byType(Material),
        )
        .first,
  );
  return material.borderRadius! as BorderRadius;
}

void main() {
  group('SettingsGroup', () {
    testWidgets('rounds the outer corners only', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SettingsGroup(
            children: [
              SettingsRow(title: 'first'),
              SettingsRow(title: 'middle'),
              SettingsRow(title: 'last'),
            ],
          ),
        ),
      );

      const radius = Radius.circular(SettingsGroup.cornerRadius);

      expect(
        _radiusOfRowAt(tester, 0),
        const BorderRadius.only(topLeft: radius, topRight: radius),
      );
      expect(_radiusOfRowAt(tester, 1), BorderRadius.zero);
      expect(
        _radiusOfRowAt(tester, 2),
        const BorderRadius.only(bottomLeft: radius, bottomRight: radius),
      );
    });

    testWidgets('rounds every corner for a single row', (tester) async {
      await tester.pumpWidget(
        _wrap(const SettingsGroup(children: [SettingsRow(title: 'only')])),
      );

      expect(
        _radiusOfRowAt(tester, 0),
        BorderRadius.circular(SettingsGroup.cornerRadius),
      );
    });
  });

  group('SettingsSection', () {
    testWidgets('hides the header when every row is gated out', (tester) async {
      await tester.pumpWidget(
        _wrap(const SettingsSection(title: 'Meetings', rows: [])),
      );

      expect(find.text('Meetings'), findsNothing);
    });

    testWidgets('shows the header once a row is visible', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SettingsSection(
            title: 'Meetings',
            rows: [SettingsRow(title: 'Waiting room')],
          ),
        ),
      );

      expect(find.text('Meetings'), findsOneWidget);
      expect(find.text('Waiting room'), findsOneWidget);
    });
  });
}
