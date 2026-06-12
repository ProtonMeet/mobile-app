import 'package:flutter_test/flutter_test.dart';
import 'package:proton_denoise/proton_denoise.dart';

void main() {
  test('ProtonDenoiseEffects is supported on test VM', () {
    expect(ProtonDenoiseEffects.isSupported, true);
    expect(ProtonDenoise.isSupported, true);
  });
}
