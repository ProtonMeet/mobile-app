import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proton_denoise/proton_denoise.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('me.proton.meet/denoise');
  final log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          log.add(call);
          switch (call.method) {
            case 'listDenoiseTypes':
              return [
                {'id': 'rnnoise', 'displayName': 'RNNoise', 'isReady': true},
                {
                  'id': 'deepfilter',
                  'displayName': 'DeepFilter 3',
                  'isReady': true,
                },
                {'id': 'dtln-rs', 'displayName': 'DTLN', 'isReady': false},
              ];
            case 'isTypeReady':
              return true;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('listDenoiseTypes parses native payload', () async {
    final types = await ProtonDenoiseEffects.instance.listDenoiseTypes();
    expect(types, hasLength(3));
    expect(types[0].type, DenoiseType.rnnoise);
    expect(types[1].type, DenoiseType.deepfilter);
    expect(types[2].type, DenoiseType.dtlnRs);
  });

  test('attachDenoise sends trackId and type', () async {
    await ProtonDenoiseEffects.instance.attachDenoise(
      trackId: 'audio-1',
      type: DenoiseType.rnnoise,
    );
    expect(log.single.method, 'attach');
    expect(log.single.arguments['trackId'], 'audio-1');
    expect(log.single.arguments['type'], 'rnnoise');
  });
}
