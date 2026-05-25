import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proton_video_effects/proton_video_effects_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannelProtonVideoEffects platform = MethodChannelProtonVideoEffects();
  const MethodChannel channel = MethodChannel('me.proton.meet/video_effects');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '42';
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getPlatformVersion', () async {
    expect(await platform.getPlatformVersion(), '42');
  });
}
