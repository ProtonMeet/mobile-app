import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/user.agent.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/channels/platform.channel.manager.dart';
import 'package:meet/managers/channels/platform.channel.state.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/rust/proton_meet/models/user.dart';
import 'package:meet/views/scenes/utils.dart';
import 'package:permission_handler/permission_handler.dart';

import 'auth_event.dart';
import 'auth_state.dart';

/// Shown name: [ProtonUser.displayName], else non-empty [ProtonUser.name], else [ProtonUser.email].
String _resolvedDisplayName(ProtonUser user) {
  final dn = user.displayName;
  if (dn != null && dn.isNotEmpty) return dn;
  if (user.name.isNotEmpty) return user.name;
  if (user.email.isNotEmpty) return user.email;
  return '';
}

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final UserAgent userAgent;
  final PlatformChannelManager nativeViewChannel;
  final ManagerFactory serviceManager;
  late StreamSubscription<NativeLoginState> _subscription;

  @override
  Future<void> close() {
    _subscription.cancel();

    return super.close();
  }

  AuthBloc(this.userAgent, this.nativeViewChannel, this.serviceManager)
    : super(AuthState()) {
    on<AuthLoading>((event, emit) {
      emit(state.copyWith(isLoading: true));
    });
    on<AuthInitialized>(_onInitialized);
    on<LoginWithNative>(_onLoginWithNative);
    on<ShowFlutterSignIn>(_onShowFlutterSignIn);
    on<SignupWithNative>(_onSignupWithNative);
    on<SignOutUser>(_onSignOutUser);
    on<LoggedInUser>(_onLoggedInUser);
    on<AuthCoreUnavailable>((event, emit) {
      emit(
        state.copyWith(
          isLoading: false,
          isLoggingIn: false,
          isSignedOut: true,
          error: event.message,
        ),
      );
    });
  }

  Future<void> _onInitialized(
    AuthInitialized event,
    Emitter<AuthState> emit,
  ) async {
    _subscription = nativeViewChannel.stream.listen(_handleStateChanges);
    emit(state.copyWith(isLoading: true, isPermissionGranted: false));

    try {
      // Request permissions
      final permissions = await _requestPermissions();
      emit(
        state.copyWith(
          isCameraPermissionGranted: permissions.camera,
          isMicrophonePermissionGranted: permissions.microphone,
        ),
      );
    } catch (e) {
      l.logger.e("Error requesting permissions: $e");
    }

    final appCoreManager = _getAppCoreManagerOrNull();
    if (appCoreManager == null) {
      emit(state.copyWith(isLoading: false, isSignedOut: true));
      return;
    }
    final userConfig = await appCoreManager.appCore.getUserConfig();
    final versionDisplay = await userAgent.displayWithoutName;

    try {
      ProtonUser? checkedUser;
      if (appCoreManager.userID != null) {
        try {
          final user = await appCoreManager.appCore.getUser(
            userId: appCoreManager.userID!,
          );

          final displayName = _resolvedDisplayName(user);
          l.logger.i(
            'onInitialized displayName: $displayName, user.name: ${user.name}, user.displayName: ${user.displayName}, user.email: ${user.email}',
          );

          emit(
            state.copyWith(
              displayName: displayName,
              email: user.email,
              initials: getInitials(displayName, defaultValue: ''),
              user: user,
            ),
          );
          checkedUser = user;
        } catch (e) {
          l.logger.e("error getting user: $e");
        }
      }

      emit(
        state.copyWith(
          isLoading: false,
          userConfig: userConfig,
          versionDisplay: versionDisplay,
          isSignedOut: checkedUser == null,
        ),
      );
    } catch (e) {
      l.logger.e("Error initializing auth: $e");
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoggedInUser(
    LoggedInUser event,
    Emitter<AuthState> emit,
  ) async {
    final appCoreManager = _getAppCoreManagerOrNull();
    if (appCoreManager == null) {
      emit(
        state.copyWith(
          isLoading: false,
          isLoggingIn: false,
          error: 'App core is unavailable. Please restart the app.',
        ),
      );
      return;
    }
    final userConfig = await appCoreManager.appCore.getUserConfig();
    final displayName = _resolvedDisplayName(event.user);
    l.logger.i(
      'onLoggedInUser displayName: $displayName, user.name: ${event.user.name}, user.displayName: ${event.user.displayName}, user.email: ${event.user.email}',
    );

    emit(
      state.copyWith(
        isLoading: false,
        userConfig: userConfig,
        displayName: displayName,
        email: event.user.email,
        user: event.user,
        initials: getInitials(displayName, defaultValue: ''),
        isLoggingIn: false,
        error: '',
      ),
    );
  }

  Future<({bool camera, bool microphone})> _requestPermissions() async {
    final permissionService = serviceManager.get<PermissionService>();
    final cameraStatus = await permissionService.cameraStatus();
    final microphoneStatus = await permissionService.microphoneStatus();

    bool isCameraPermissionGranted = cameraStatus.isGranted;
    if (!isCameraPermissionGranted && cameraStatus.isDenied) {
      isCameraPermissionGranted = await permissionService
          .requestCameraPermission();
    }

    bool isMicrophonePermissionGranted = microphoneStatus.isGranted;
    if (!isMicrophonePermissionGranted && microphoneStatus.isDenied) {
      isMicrophonePermissionGranted = await permissionService
          .requestMicrophonePermission();
    }

    return (
      camera: isCameraPermissionGranted,
      microphone: isMicrophonePermissionGranted,
    );
  }

  Future<void> _onLoginWithNative(
    LoginWithNative event,
    Emitter<AuthState> emit,
  ) async {
    // Check if native login is supported (not desktop)
    if (desktop) {
      // Native login not supported on desktop, emit state to show Flutter sign-in
      emit(state.copyWith(shouldShowFlutterSignIn: true));
    } else {
      nativeViewChannel.switchToNativeLogin();
    }
  }

  Future<void> _onShowFlutterSignIn(
    ShowFlutterSignIn event,
    Emitter<AuthState> emit,
  ) async {
    emit(state.copyWith(shouldShowFlutterSignIn: true));
  }

  Future<void> _onSignupWithNative(
    SignupWithNative event,
    Emitter<AuthState> emit,
  ) async {
    nativeViewChannel.switchToNativeSignup();
  }

  Future<void> _onSignOutUser(
    SignOutUser event,
    Emitter<AuthState> emit,
  ) async {
    await serviceManager.logout();
    emit(
      state.copyWith(
        isSignedOut: true,
        displayName: '',
        email: '',
        initials: '',
        isPermissionGranted: false,
      ),
    );
  }

  Future<void> _handleStateChanges(NativeLoginState nativeState) async {
    if (nativeState is NativeLoginSuccess) {
      final appCoreManager = _getAppCoreManagerOrNull();
      if (appCoreManager == null) {
        add(
          AuthCoreUnavailable(
            'App core is unavailable. Please restart the app.',
          ),
        );
        return;
      }
      try {
        await appCoreManager.trySaveUserInfo(nativeState.userInfo);
        await serviceManager.login(nativeState.userInfo.userId);
      } on Object catch (e, st) {
        l.logger.e(
          'Native handoff save/login failed: $e',
          error: e,
          stackTrace: st,
        );
        return;
      }
      final loggedInUser = ProtonUser(
        id: nativeState.userInfo.userId,
        name: nativeState.userInfo.userName,
        email: nativeState.userInfo.userMail,
        displayName: nativeState.userInfo.userDisplayName,
        usedSpace: BigInt.from(0),
        currency: '',
        credit: 0,
        createTime: BigInt.from(0),
        maxSpace: BigInt.from(0),
        maxUpload: BigInt.from(0),
        role: 0,
        private: 0,
        subscribed: 0,
        services: 0,
        delinquent: 0,
        mnemonicStatus: 0,
      );
      add(LoggedInUser(loggedInUser));
    }
  }

  AppCoreManager? _getAppCoreManagerOrNull() {
    try {
      return serviceManager.get<AppCoreManager>();
    } catch (e) {
      l.logger.e("AppCoreManager unavailable: $e");
      return null;
    }
  }
}
