import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'proton_video_effects_platform_interface.dart';

/// An implementation of [ProtonVideoEffectsPlatform] that uses method channels.
class MethodChannelProtonVideoEffects extends ProtonVideoEffectsPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('me.proton.meet/video_effects');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
