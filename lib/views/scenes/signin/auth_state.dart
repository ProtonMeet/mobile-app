import 'package:meet/rust/proton_meet/models/user.dart';
import 'package:meet/rust/proton_meet/user_config.dart';

class AuthState {
  final String displayName;
  final String email;
  final String initials;
  final ProtonUser? user;

  ///
  final UserConfig? userConfig;
  final String versionDisplay;

  ///
  final bool isLoading;
  final bool isLoggingIn;
  final bool isLoggingOut;

  /// old
  final bool isPermissionGranted;
  final bool isCameraPermissionGranted;
  final bool isMicrophonePermissionGranted;
  final bool shouldShowCameraPermissionSettings;
  final bool shouldShowMicrophonePermissionSettings;
  final bool shouldShowFlutterSignIn;
  final String? error;

  AuthState({
    this.displayName = '',
    this.email = '',
    this.initials = '',
    this.versionDisplay = '',
    this.isLoggingIn = false,
    this.isLoggingOut = false,
    this.isCameraPermissionGranted = false,
    this.isMicrophonePermissionGranted = false,
    this.shouldShowCameraPermissionSettings = false,
    this.shouldShowMicrophonePermissionSettings = false,
    this.shouldShowFlutterSignIn = false,
    this.isLoading = false,
    this.error,
    this.userConfig,
    this.isPermissionGranted = false,
    this.user,
  });

  AuthState copyWith({
    String? displayName,
    String? email,
    String? initials,
    bool? isLoggingIn,
    bool? isLoggingOut,
    bool? isCameraPermissionGranted,
    bool? isMicrophonePermissionGranted,
    bool? shouldShowCameraPermissionSettings,
    bool? shouldShowMicrophonePermissionSettings,
    bool? shouldShowFlutterSignIn,
    bool? isLoading,
    String? error,
    UserConfig? userConfig,
    String? versionDisplay,
    bool? isPermissionGranted,
    ProtonUser? user,
    bool isSignedOut = false,
  }) {
    return AuthState(
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      initials: initials ?? this.initials,
      isLoggingIn: isLoggingIn ?? this.isLoggingIn,
      isLoggingOut: isLoggingOut ?? this.isLoggingOut,
      shouldShowCameraPermissionSettings:
          shouldShowCameraPermissionSettings ??
          this.shouldShowCameraPermissionSettings,
      shouldShowMicrophonePermissionSettings:
          shouldShowMicrophonePermissionSettings ??
          this.shouldShowMicrophonePermissionSettings,
      shouldShowFlutterSignIn:
          shouldShowFlutterSignIn ?? this.shouldShowFlutterSignIn,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      userConfig: userConfig ?? this.userConfig,
      versionDisplay: versionDisplay ?? this.versionDisplay,
      isPermissionGranted: isPermissionGranted ?? this.isPermissionGranted,
      isCameraPermissionGranted:
          isCameraPermissionGranted ?? this.isCameraPermissionGranted,
      isMicrophonePermissionGranted:
          isMicrophonePermissionGranted ?? this.isMicrophonePermissionGranted,
      user: isSignedOut ? null : user ?? this.user,
    );
  }

  bool get isSignedIn => user != null;
}
