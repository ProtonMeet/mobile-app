import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'proton_denoise_method_channel.dart';

abstract class ProtonDenoisePlatform extends PlatformInterface {
  /// Constructs a ProtonDenoisePlatform.
  ProtonDenoisePlatform() : super(token: _token);

  static final Object _token = Object();

  static ProtonDenoisePlatform _instance = MethodChannelProtonDenoise();

  /// The default instance of [ProtonDenoisePlatform] to use.
  ///
  /// Defaults to [MethodChannelProtonDenoise].
  static ProtonDenoisePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [ProtonDenoisePlatform] when
  /// they register themselves.
  static set instance(ProtonDenoisePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
