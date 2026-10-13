import 'dart:io';

import 'package:flutter/foundation.dart';

bool get mobile => android || iOS;
bool get desktop => !mobile;
bool get android => defaultTargetPlatform == TargetPlatform.android;
bool get iOS => defaultTargetPlatform == TargetPlatform.iOS;
bool get macOS => defaultTargetPlatform == TargetPlatform.macOS;
bool get linux => defaultTargetPlatform == TargetPlatform.linux;
bool get windows => defaultTargetPlatform == TargetPlatform.windows;
bool get web => kIsWeb;

/// Linux desktop running a Wayland session (capture goes through
/// xdg-desktop-portal / PipeWire instead of X11).
bool get linuxWayland {
  if (web || !linux) return false;
  final env = Platform.environment;
  return env['XDG_SESSION_TYPE']?.toLowerCase() == 'wayland' ||
      (env['WAYLAND_DISPLAY']?.isNotEmpty ?? false);
}

bool isM1Simulator() {
  if (Platform.isIOS) {
    // On iOS simulators, environment variables can help determine the architecture
    final arch = Platform.environment['SIMULATOR_RUNTIME'] ?? '';
    if (arch.contains('arm64')) {
      return true;
    }
  }
  return false;
}
