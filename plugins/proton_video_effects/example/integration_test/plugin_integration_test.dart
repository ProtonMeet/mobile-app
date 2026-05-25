// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:proton_video_effects/proton_video_effects.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('background blur readiness returns a bool', (
    WidgetTester tester,
  ) async {
    final ProtonVideoEffects plugin = ProtonVideoEffects.instance;
    final bool ready = await plugin.isBackgroundBlurReady();
    expect(ready, isA<bool>());
  });
}
