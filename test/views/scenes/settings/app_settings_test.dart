import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meet/constants/proton.color.dart';
import 'package:meet/l10n/generated/locale.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/meet.user.settings.data.provider.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/provider/locale.provider.dart';
import 'package:meet/rust/proton_meet/models/user.dart';
import 'package:meet/views/scenes/settings/app_settings.dart';
import 'package:meet/views/scenes/settings/app_settings_bloc.dart';
import 'package:meet/views/scenes/settings/app_settings_event.dart';
import 'package:meet/views/scenes/settings/app_settings_state.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:meet/views/scenes/signin/auth_state.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentUnleash extends Mock implements UnleashDataProvider {
  @override
  Stream<DataState> get stream => const Stream.empty();

  @override
  bool isFeatureEnabled(dynamic feature) => false;
}

class _SilentMeet extends Mock implements MeetUserSettingsDataProvider {
  @override
  Stream<DataState> get stream => const Stream.empty();
}

class _SilentDataProviderManager extends Mock implements DataProviderManager {
  _SilentDataProviderManager(this.unleash);

  final UnleashDataProvider unleash;

  @override
  UnleashDataProvider get unleashDataProvider => unleash;
}

/// Seeds [initialState] without running init handlers.
class TestAppSettingsBloc extends AppSettingsBloc {
  TestAppSettingsBloc(AppSettingsState initialState)
    : super(
        dataProviderManager: _SilentDataProviderManager(_SilentUnleash()),
        meetUserSettingsDataProvider: _SilentMeet(),
      ) {
    emit(initialState);
  }

  final List<AppSettingsEvent> recordedEvents = [];

  @override
  void add(AppSettingsEvent event) {
    recordedEvents.add(event);
  }
}

class SignedInAuthBloc extends Mock implements AuthBloc {
  @override
  AuthState get state => AuthState(user: _signedInUser);
}

final _signedInUser = ProtonUser(
  id: 'user-1',
  name: 'Test User',
  usedSpace: BigInt.zero,
  currency: 'USD',
  credit: 0,
  createTime: BigInt.zero,
  maxSpace: BigInt.zero,
  maxUpload: BigInt.zero,
  role: 0,
  private: 0,
  subscribed: 0,
  services: 0,
  delinquent: 0,
  email: 'test@example.com',
  mnemonicStatus: 0,
);

Future<void> pumpAppSettings(
  WidgetTester tester, {
  required AppSettingsBloc appSettingsBloc,
  AuthBloc? authBloc,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: S.localizationsDelegates,
      supportedLocales: S.supportedLocales,
      locale: const Locale('en'),
      theme: ThemeData(extensions: [darkColorsExtension]),
      home: Scaffold(
        body: ChangeNotifierProvider(
          create: (_) => LocaleProvider(),
          child: AppSettingsBottomSheet(
            maxHeight: 800,
            isLandscape: false,
            appSettingsBloc: appSettingsBloc,
            authBloc: authBloc,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppSettingsBottomSheet', () {
    testWidgets('renders the title and core sections', (tester) async {
      final bloc = TestAppSettingsBloc(const AppSettingsState());
      addTearDown(bloc.close);

      await pumpAppSettings(tester, appSettingsBloc: bloc);

      expect(find.text('App settings'), findsOneWidget);
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
      expect(find.text('Legal'), findsOneWidget);
      expect(find.text('Languages'), findsOneWidget);
      expect(find.text('Knowledge base'), findsOneWidget);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('Terms and conditions'), findsOneWidget);
    });

    testWidgets('hides report problem when signed out', (tester) async {
      final bloc = TestAppSettingsBloc(const AppSettingsState());
      addTearDown(bloc.close);

      await pumpAppSettings(tester, appSettingsBloc: bloc);

      expect(find.text('Report problem'), findsNothing);
    });

    testWidgets('shows report problem when signed in', (tester) async {
      final bloc = TestAppSettingsBloc(const AppSettingsState());
      addTearDown(bloc.close);
      final authBloc = SignedInAuthBloc();
      await pumpAppSettings(tester, appSettingsBloc: bloc, authBloc: authBloc);

      expect(find.text('Report problem'), findsOneWidget);
    });

    testWidgets('shows waiting room row when signed in and flag is on', (
      tester,
    ) async {
      final bloc = TestAppSettingsBloc(
        const AppSettingsState(waitingRoomEnabled: true, isPaidUser: true),
      );
      addTearDown(bloc.close);
      final authBloc = SignedInAuthBloc();
      await pumpAppSettings(tester, appSettingsBloc: bloc, authBloc: authBloc);

      expect(find.text('Waiting room'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);
      expect(find.byType(CupertinoSwitch), findsOneWidget);
    });

    testWidgets('hides waiting room row when signed out', (tester) async {
      final bloc = TestAppSettingsBloc(
        const AppSettingsState(waitingRoomEnabled: true),
      );
      addTearDown(bloc.close);

      await pumpAppSettings(tester, appSettingsBloc: bloc);

      expect(find.text('Waiting room'), findsNothing);
      expect(find.byType(CupertinoSwitch), findsNothing);
    });

    testWidgets('dispatches waiting room toggle when switch is tapped', (
      tester,
    ) async {
      final bloc = TestAppSettingsBloc(
        const AppSettingsState(waitingRoomEnabled: true, isPaidUser: true),
      );
      addTearDown(bloc.close);
      final authBloc = SignedInAuthBloc();
      await pumpAppSettings(tester, appSettingsBloc: bloc, authBloc: authBloc);

      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pump();

      expect(
        bloc.recordedEvents.whereType<AppSettingsWaitingRoomToggled>(),
        hasLength(1),
      );
      final event = bloc.recordedEvents
          .whereType<AppSettingsWaitingRoomToggled>()
          .single;
      expect(event, isA<AppSettingsWaitingRoomToggled>());
      expect((event).enabled, isFalse);
      expect((event).isPaidUser, isTrue);
    });

    testWidgets('does not dispatch waiting room toggle for unpaid users', (
      tester,
    ) async {
      final bloc = TestAppSettingsBloc(const AppSettingsState());
      addTearDown(bloc.close);
      final authBloc = SignedInAuthBloc();
      await pumpAppSettings(tester, appSettingsBloc: bloc, authBloc: authBloc);

      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pump();

      expect(
        bloc.recordedEvents.whereType<AppSettingsWaitingRoomToggled>(),
        isEmpty,
      );
      expect(find.text('Available with a paid plan'), findsOneWidget);
    });

    testWidgets('shows preview placeholders when preview flag is on', (
      tester,
    ) async {
      final bloc = TestAppSettingsBloc(
        const AppSettingsState(showPreviewSettings: true),
      );
      addTearDown(bloc.close);

      await pumpAppSettings(tester, appSettingsBloc: bloc);

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Live captions'), findsOneWidget);
      expect(find.text('Test microphone'), findsOneWidget);
      expect(find.text('Test speakers'), findsOneWidget);
    });
  });
}
