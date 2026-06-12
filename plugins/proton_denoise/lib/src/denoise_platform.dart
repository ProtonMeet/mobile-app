import 'package:flutter/foundation.dart' show kIsWeb;

/// iOS, Android, macOS, Linux, and Windows; false on web.
bool get isProtonDenoisePlatformSupported => !kIsWeb;
