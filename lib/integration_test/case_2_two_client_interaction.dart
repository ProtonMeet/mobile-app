// // NOTE:
// // please run this integration test on an physical device.
// // you will got a lot of MissingPluginException when you run with flutter test
// //
// // To run following integration test on windows:
// // ```
// // flutter drive --driver=lib/test_driver/integration_test_driver.dart --target=lib/integration_test/case_2_two_client_interaction.dart -d Windows
// // ```

// import 'dart:convert';
// import 'dart:io';

// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// // ignore: depend_on_referenced_packages
// import 'package:flutter_test/flutter_test.dart';
// // ignore: depend_on_referenced_packages
// import 'package:integration_test/integration_test.dart';
// import 'package:meet/constants/app.config.dart';
// import 'package:meet/constants/app.keys.dart';
// import 'package:meet/constants/constants.dart';
// import 'package:meet/constants/env.dart';
// import 'package:meet/main.dart' as app;
// import 'package:meet/views/scenes/app/app.coordinator.dart';

// class FileLogger {
//   final IOSink _sink;

//   FileLogger._(this._sink);

//   static Future<FileLogger> create(String path) async {
//     final file = File(path);
//     // The sink is intentionally kept open for logging and will be closed via close()
//     // ignore: close_sinks
//     final sink = file.openWrite(mode: FileMode.append); // append mode
//     return FileLogger._(sink);
//   }

//   Future<void> log(String message) async {
//     final now = DateTime.now();
//     final timestamp =
//         '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')} '
//         '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}:${now.millisecond.toString().padLeft(3, '0')}';
//     _sink.writeln('$timestamp: $message');
//     await _sink.flush();
//   }

//   Future<void> close() async {
//     await _sink.flush();
//     await _sink.close();
//   }
// }

// FileLogger? _logger;
// const testName = 'testName';
// const MethodChannel pathProviderChannel = MethodChannel(
//   'plugins.flutter.io/path_provider',
// );
// final executablePath = Platform.resolvedExecutable;
// int epoch = 1;

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

// bool get isChildProcess {
//   final isChildProcess = Platform.environment['IS_CHILD'] == 'true';
//   return isChildProcess;
// }

// Future<void> spawnChildProcesses(int count, WidgetTester tester) async {
//   final exec = Platform.resolvedExecutable;
//   await _logger?.log('🔍 exec: $exec');

//   for (int i = 0; i < count; i++) {
//     final process = await Process.start(
//       exec,
//       [],
//       environment: {...Platform.environment, 'IS_CHILD': 'true'},
//     );

//     await _logger?.log('🚀 Spawned child $i, pid: ${process.pid}');

//     process.stdout.transform(utf8.decoder).listen((data) async {
//       for (final line in data.split('\n')) {
//         if (line.trim().isEmpty) continue;
//         try {
//           final jsonData = jsonDecode(line);
//           if (jsonData['event'] == 'room_joined') {
//             await waitSeconds(tester, 1.0);
//             await _logger?.log('Child stdout: $data');
//             epoch += 1;
//             try {
//               final epochWidget = find.textContaining("Epoch: $epoch");
//               expectSync(epochWidget, findsOneWidget);
//               await _logger?.log('child joined room, epoch changed correctly');
//             } catch (e) {
//               await _logger?.log(
//                 'child joined room, but we did not find epoch widget correctly: $epoch',
//               );
//               await _logger?.log('Error: $e');
//               exit(1); // exit with error code 1
//             }
//           } else if (jsonData['event'] == 'room_left') {
//             await waitSeconds(tester, 1.0);
//             await _logger?.log('Child stdout: $data');
//             epoch += 1;
//             try {
//               final epochWidget = find.textContaining("Epoch: $epoch");
//               expectSync(epochWidget, findsOneWidget);
//               await _logger?.log('child left room, epoch changed correctly');
//             } catch (e) {
//               await _logger?.log(
//                 'child left room, but we did not find epoch widget correctly: $epoch',
//               );
//               await _logger?.log('Error: $e');
//               exit(1);
//             }
//           } else if (jsonData['event'] == 'message_sent') {
//             await _logger?.log('Child stdout: $data');
//             try {
//               /// open chat widget
//               await tapChatButton(tester);

//               /// wait 100 second
//               await waitSeconds(tester, 2.0);

//               /// check the chat widget
//               final messageWidget = find.textContaining(jsonData['message']);
//               expectSync(messageWidget, findsAtLeast(1));

//               /// close chat widget
//               await tapChatButton(tester);
//               await _logger?.log(
//                 'child sent message, message widget found correctly',
//               );
//             } catch (e) {
//               await _logger?.log(
//                 'child sent message, but we did not find message widget correctly: ${jsonData['message']}',
//               );
//               await _logger?.log('Error: $e');
//               exit(1);
//             }
//           }
//         } catch (e) {
//           // skip
//         }
//       }
//     });

//     process.stderr.transform(utf8.decoder).listen((data) async {
//       await _logger?.log('Child stderr: $data');
//     });

//     final exitCode = await process.exitCode;
//     await _logger?.log('Child process $i exited with code $exitCode');
//     if (exitCode != 0) {
//       await _logger?.log('🔍 test failed!');
//       await _logger!.close();
//       _logger = null;
//       exit(1);
//     }
//   }
// }

// Future<void> tapChatButton(WidgetTester tester) async {
//   final chatBtn = find.byKey(AppKeys.showChatButton);
//   await tester.tap(chatBtn);
//   await waitSeconds(tester, 1.0);
// }

// Future<void> testSendMessage(WidgetTester tester, String message) async {
//   /// open chat widget
//   await tapChatButton(tester);

//   /// send message
//   final chatMessageTextField = find.byKey(AppKeys.chatMessageTextField);
//   await tester.enterText(chatMessageTextField, message);
//   final chatSendButton = find.byKey(AppKeys.chatSendButton);
//   await tester.tap(chatSendButton);
//   await waitSeconds(tester, 1.0);

//   /// close chat widget
//   await tapChatButton(tester);
// }

// void main() {
//   IntegrationTestWidgetsFlutterBinding.ensureInitialized();

//   final testMockStorage =
//       './test/session_${DateTime.now().microsecondsSinceEpoch}';
//   final documentsPath = "$testMockStorage/documents";

//   /// mock path provider
//   TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
//       .setMockMethodCallHandler(pathProviderChannel, (
//         MethodCall methodCall,
//       ) async {
//         final dir = Directory(documentsPath);
//         if (!dir.existsSync()) dir.createSync(recursive: true);
//         return documentsPath;
//       });

//   testWidgets('Integration Test App open meet with name=testName', (
//     tester,
//   ) async {
//     if (!isChildProcess) {
//       _logger = await FileLogger.create('./test/test.log');
//       await _logger?.log('Start integration test');
//     }

//     /// setup window size
//     await tester.binding.setSurfaceSize(const Size(1280, 720));

//     /// update app config for test, so app will use mock storage
//     appConfig = AppConfig(
//       apiEnv: ApiEnv.atlas(null),
//       testMode: true,
//       testMockStorage: documentsPath,
//     );

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

//     /// wait for 15 seconds to join the room
//     await waitSeconds(tester, 15.0);

//     final roomNameResult = find.textContaining(defaultRoomId);
//     expect(roomNameResult, findsOneWidget);
//     await _logger?.log('room joined, room name found correctly');

//     /// start child app if not child process
//     if (!isChildProcess) {
//       await spawnChildProcesses(1, tester);
//     }

//     if (isChildProcess) {
//       /// send a random message
//       final randomMessage =
//           'Random message from child process ${DateTime.now().microsecondsSinceEpoch}';
//       await testSendMessage(tester, randomMessage);

//       /// wait 2 seconds
//       await waitSeconds(tester, 2.0);

//       /// wait 5 seconds
//       await waitSeconds(tester, 5.0);

//       /// click leave room button
//       final leaveBtn = find.byKey(AppKeys.leaveRoomButton);
//       expect(leaveBtn, findsOneWidget);
//       await tester.tap(leaveBtn);

//       await waitSeconds(tester, 5.0);
//       await waitSeconds(tester, 5.0);
//     }

//     if (_logger != null) {
//       await _logger?.log('🔍 test success!');
//       await _logger!.close();
//     }
//     exit(0);
//   });
// }
