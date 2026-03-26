import 'dart:async';

/// Interface for Picture-in-Picture (PIP) functionality
/// Different platforms (Android, iOS, Desktop) will implement this interface
abstract class PipManagerInterface {
  /// Check if PIP is available on this platform
  Future<bool> isPipAvailable();

  /// Check if PIP is supported
  Future<bool> isPipSupported();

  /// Check if PIP is currently active
  Future<bool> isPipActivated();

  /// Enter PIP mode
  /// Returns true if successful, false otherwise
  Future<bool> enterPipMode();

  /// Exit PIP mode
  Future<void> exitPipMode();

  /// Initialize PIP functionality
  /// Should be called before using PIP
  Future<void> initialize({
    required String roomName,
    required Future<void> Function() onPipEntered,
    required Future<void> Function() onPipExited,
    required Future<void> Function() onNotificationTap,
  });

  /// Dispose and clean up PIP resources
  Future<void> dispose();

  /// Stream that emits PIP state changes
  Stream<bool> get pipStateStream;
}
