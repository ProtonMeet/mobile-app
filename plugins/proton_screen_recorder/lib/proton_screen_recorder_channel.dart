import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MethodChannelProtonScreenRecorder {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('proton_screen_recorder');
}
