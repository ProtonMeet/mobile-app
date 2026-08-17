import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:proton_video_effects/proton_video_effects.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('me.proton.meet/video_effects');
  final plugin = ProtonVideoEffects.instance;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isImplementationReady') {
            return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isBackgroundBlurReady uses channel readiness', () async {
    expect(await plugin.isBackgroundBlurReady(), isTrue);
  });

  test('attachBackgroundBlur sends trackId to native channel', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return null;
        });

    await plugin.attachBackgroundBlur(trackId: 'track-1');

    expect(captured?.method, 'attach');
    expect(captured?.arguments, {'trackId': 'track-1'});
  });

  test('detachBackgroundBlur sends trackId to native channel', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return null;
        });

    await plugin.detachBackgroundBlur(trackId: 'track-2');

    expect(captured?.method, 'detach');
    expect(captured?.arguments, {'trackId': 'track-2'});
  });

  test('setBackgroundBlurConfig sends tuning to native channel', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return null;
        });

    const config = BackgroundBlurConfig(
      blurSigma: 48,
      backgroundObscureOpacity: 0.35,
    );
    await plugin.setBackgroundBlurConfig(config);

    expect(captured?.method, 'setBackgroundBlurConfig');
    expect(captured?.arguments, config.toMethodChannelArgs());
  });

  test('attachBackgroundBlur forwards optional config', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return null;
        });

    const config = BackgroundBlurConfig(
      blurSigma: 64,
      backgroundObscureOpacity: 0.5,
    );
    await plugin.attachBackgroundBlur(trackId: 'track-3', config: config);

    expect(captured?.method, 'attach');
    expect(captured?.arguments, <String, dynamic>{
      'trackId': 'track-3',
      ...config.toMethodChannelArgs(),
    });
  });
}
