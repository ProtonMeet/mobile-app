import 'package:flutter_test/flutter_test.dart';
import 'package:proton_denoise/proton_denoise.dart';
import 'package:proton_denoise/proton_denoise_platform_interface.dart';
import 'package:proton_denoise/proton_denoise_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockProtonDenoisePlatform
    with MockPlatformInterfaceMixin
    implements ProtonDenoisePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final ProtonDenoisePlatform initialPlatform = ProtonDenoisePlatform.instance;

  test('$MethodChannelProtonDenoise is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelProtonDenoise>());
  });

  test('getPlatformVersion', () async {
    expect(ProtonDenoise.isSupported, true);
  });
}
