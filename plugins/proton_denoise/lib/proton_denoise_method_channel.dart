import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'proton_denoise_platform_interface.dart';

/// An implementation of [ProtonDenoisePlatform] that uses method channels.
class MethodChannelProtonDenoise extends ProtonDenoisePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('proton_denoise');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
