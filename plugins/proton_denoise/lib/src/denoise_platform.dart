import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// iOS, macOS, and Android. Windows and Linux are planned later.
bool get isProtonDenoisePlatformSupported =>
    !kIsWeb && (Platform.isIOS || Platform.isMacOS || Platform.isAndroid);
