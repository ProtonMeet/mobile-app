// // NOTE:
// // please run this integration test on an physical device.
// // you will got a lot of MissingPluginException when you run with flutter test
// //
// // To run following integration test on windows:
// // ```
// // flutter drive --driver=lib/test_driver/integration_test_driver.dart --target=lib/integration_test/case_1_basic_features.dart -d Windows
// // ```

// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// // ignore: depend_on_referenced_packages
// import 'package:flutter_test/flutter_test.dart';
// // ignore: depend_on_referenced_packages
// import 'package:integration_test/integration_test.dart';
// import 'package:meet/constants/app.keys.dart';
// import 'package:meet/constants/constants.dart';
// import 'package:meet/main.dart' as app;
// import 'package:meet/views/scenes/app/app.coordinator.dart';

// const testName = 'testName';
// const testMockStorage = './test';
// const MethodChannel pathProviderChannel = MethodChannel(
//   'plugins.flutter.io/path_provider',
// );

// /// Helper function to wait for a specified number of frames
// Future<void> waitFrames(WidgetTester tester, int frames) async {
//   for (final _ in List.generate(frames, (index) => index)) {
//     await tester.pump(const Duration(milliseconds: 100));
//   }
// }

// /// Helper function to wait for a specified number of seconds
// Future<void> waitSeconds(WidgetTester tester, double seconds) async {
//   final frames = (seconds * 10).round(); // 10 frames per second (100ms each)
//   await waitFrames(tester, frames);
// }

// void main() {
//   IntegrationTestWidgetsFlutterBinding.ensureInitialized();

//   testWidgets('Integration Test case 1', (tester) async {
//     /// mock the path_provider native method to avoid MissingPluginException
//     tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
//       pathProviderChannel,
//       (MethodCall methodCall) async {
//         if (methodCall.method == 'getApplicationDocumentsDirectory') {
//           return testMockStorage;
//         }
//         return null;
//       },
//     );

//     /// setup window size
//     await tester.binding.setSurfaceSize(const Size(1280, 720));

//     /// start the app and test
//     await app.appInit();
//     await tester.pumpWidget(AppCoordinator().start());

//     /// wait 2 seconds to show splash page and redirect to landing page
//     await waitSeconds(tester, 2.0);

//     /// check the landing page
//     final landingPageTitleResult = find.textContaining("Talk freely");
//     final landingPageSubTitleResult = find.textContaining(
//       "Our end-to-end encrypted meetings protect privacy and empower truly free expression.",
//     );
//     expect(landingPageTitleResult, findsOneWidget);
//     expect(landingPageSubTitleResult, findsOneWidget);

//     /// check the text fields and input name
//     final textFields = find.byType(TextFormField);
//     expect(textFields, findsWidgets);

//     await tester.enterText(textFields.at(1), testName);
//     await tester.pumpAndSettle();

//     /// check the join button
//     final joinButton = find.widgetWithText(ElevatedButton, 'Join meeting');
//     expect(joinButton, findsOneWidget);

//     /// tap the join button to unfocus the text field, so button will be enabled
//     await tester.tap(joinButton);

//     /// wait 1 second
//     await waitSeconds(tester, 1.0);

//     /// tap the join button
//     await tester.tap(joinButton);

//     /// wait for 10 seconds to join the room
//     await waitSeconds(tester, 10.0);

//     final roomNameResult = find.textContaining(defaultRoomId);
//     expect(roomNameResult, findsOneWidget);

//     final participantCameraViewNameResult = find.textContaining(testName);
//     expect(participantCameraViewNameResult, findsOneWidget);

//     /// click participant list
//     final participantsBtn = find.byKey(AppKeys.showParticipantsListButton);
//     expect(participantsBtn, findsOneWidget);
//     await tester.tap(participantsBtn);

//     /// wait 1 second
//     await waitSeconds(tester, 1.0);

//     /// we should have 1 name in participant camera view and 1 name in participant list
//     final participantCameraViewNameResult2 = find.textContaining(testName);
//     expect(participantCameraViewNameResult2, findsExactly(2));

//     /// click chat button
//     final chatBtn = find.byKey(AppKeys.showChatButton);
//     expect(chatBtn, findsOneWidget);
//     await tester.tap(chatBtn);

//     /// wait 1 second
//     await waitSeconds(tester, 1.0);

//     /// check the chat widget
//     final chatWidgetTitle = find.textContaining("Meeting Chat");
//     final chatWidgetEmptyHint = find.textContaining("No messages yet");
//     expect(chatWidgetTitle, findsOneWidget);
//     expect(chatWidgetEmptyHint, findsOneWidget);

//     /// send a message
//     const message = "Hello, world!";
//     final chatWidgetContentBeforeSendMessage = find.textContaining(message);
//     expect(chatWidgetContentBeforeSendMessage, findsNothing);

//     final chatMessageTextField = find.byKey(AppKeys.chatMessageTextField);
//     expect(chatMessageTextField, findsOneWidget);
//     await tester.enterText(chatMessageTextField, message);
//     final chatSendButton = find.byKey(AppKeys.chatSendButton);
//     expect(chatSendButton, findsOneWidget);
//     await tester.tap(chatSendButton);

//     /// wait 1 second
//     await waitSeconds(tester, 1.0);

//     final chatWidgetContentAfterSendMessage = find.textContaining(message);
//     expect(chatWidgetContentAfterSendMessage, findsOneWidget);

//     final chatFindButton = find.byKey(AppKeys.chatFindButton);
//     expect(chatFindButton, findsOneWidget);
//     await tester.tap(chatFindButton);

//     /// wait 1 second
//     await waitSeconds(tester, 1.0);

//     final chatFindTextField = find.byKey(AppKeys.chatFindTextField);
//     expect(chatFindTextField, findsOneWidget);
//     await tester.enterText(chatFindTextField, 'world');

//     /// wait 1 second
//     await waitSeconds(tester, 1.0);

//     final chatWidgetContentAfterFilter1 = find.textContaining(message);
//     expect(chatWidgetContentAfterFilter1, findsOneWidget);

//     await tester.enterText(chatFindTextField, 'nothing');

//     /// wait 1 second
//     await waitSeconds(tester, 1.0);

//     final chatWidgetContentAfterFilter2 = find.textContaining(message);
//     final chatWidgetNothingFoundHint = find.textContaining("No messages found");
//     expect(chatWidgetContentAfterFilter2, findsNothing);
//     expect(chatWidgetNothingFoundHint, findsOneWidget);

//     /// click settings button
//     final settingsBtn = find.byKey(AppKeys.showSettingsButton);
//     expect(settingsBtn, findsOneWidget);
//     await tester.tap(settingsBtn);

//     /// wait 1 second
//     await waitSeconds(tester, 1.0);

//     /// check the settings widget
//     final settingsWidgetTitle = find.textContaining("Meeting settings");
//     final settingsWidgetHideSelfView = find.textContaining("Hide self view");
//     expect(settingsWidgetTitle, findsOneWidget);
//     expect(settingsWidgetHideSelfView, findsOneWidget);

//     /// click meeting info button
//     final meetingInfoBtn = find.byKey(AppKeys.showMeetingInfoButton);
//     expect(meetingInfoBtn, findsOneWidget);
//     await tester.tap(meetingInfoBtn);

//     /// wait 1 second
//     await waitSeconds(tester, 1.0);

//     /// check the meeting info widget
//     final meetingInfoWidgetTitle = find.textContaining("Meeting detail");
//     final meetingInfoWidgetRoomId = find.textContaining(defaultRoomId);
//     expect(meetingInfoWidgetTitle, findsOneWidget);
//     expect(
//       meetingInfoWidgetRoomId,
//       findsExactly(2),
//     ); // meeting name and meeting id to share

//     /// click leave room button
//     final leaveBtn = find.byKey(AppKeys.leaveRoomButton);
//     expect(leaveBtn, findsOneWidget);
//     await tester.tap(leaveBtn);

//     /// wait 1 second
//     await waitSeconds(tester, 1.0);
//   });
// }
