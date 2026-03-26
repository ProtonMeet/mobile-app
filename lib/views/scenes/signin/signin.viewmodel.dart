import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:meet/constants/app.config.dart';
import 'package:meet/constants/env.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/models/native.session.model.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/rust/proton_meet/models/proton_user_session.dart';
import 'package:meet/views/scenes/core/view.navigatior.identifiers.dart';
import 'package:meet/views/scenes/core/viewmodel.dart';
import 'package:meet/views/scenes/signin/signin.coordinator.dart';

abstract class SigninViewModel extends ViewModel<SigninCoordinator> {
  SigninViewModel(super.coordinator);

  Future<void> signIn(String username, String password, String twoFactorCode);

  String errorMessage = "";

  bool isTwoFactor = false;

  bool loginSuccess = false;

  ProtonUserSession? loginUser;
}

class SigninViewModelImpl extends SigninViewModel {
  final ManagerFactory serviceManager;
  final AppStateManager appStateManger;
  final DataProviderManager dataProviderManager;
  final AppCoreManager appCoreManager;

  SigninViewModelImpl(
    super.coordinator,
    this.dataProviderManager,
    this.appStateManger,
    this.serviceManager,
    this.appCoreManager,
  );

  bool hadLocallogin = false;

  late ApiEnv env;

  @override
  Future<void> loadData() async {
    env = appConfig.apiEnv;
  }

  @override
  Future<void> move(NavID to) async {
    switch (to) {
      case NavID.nativeSignin:
        break;
      case NavID.nativeSignup:
        break;
      case NavID.home:
        break;
      default:
        break;
    }
  }

  @override
  Future<void> signIn(
    String username,
    String password,
    String twoFactorCode,
  ) async {
    try {
      final appCoreManager = ManagerFactory().get<AppCoreManager>();
      ProtonUserSession user;
      if (twoFactorCode.isNotEmpty) {
        // This is a 2FA login attempt
        final protonUserSession = await appCoreManager.appCore
            .loginWithTwoFactor(
              password: password,
              twoFactorCode: twoFactorCode,
            );
        user = protonUserSession;
      } else {
        // This is a regular login attempt
        final protonUserSession = await appCoreManager.appCore.login(
          username: username,
          password: password,
        );
        user = protonUserSession;
      }
      final userInfo = UserInfo.fromProtonUserSession(user);
      await appCoreManager.trySaveUserInfo(userInfo);
      await serviceManager.login(userInfo.userId);
      if (kDebugMode) {
        logger.i("userId: ${user.userId}");
      }
      isTwoFactor = false; // Reset the flag on successful login
      loginSuccess = true; // Set success flag for callback
      loginUser = user; // Store the user data for callback
      sinkAddSafe(); // Notify the view of state change
    } on BridgeError catch (e) {
      final errorString = e.toString();
      logger.e("errorString: $errorString");
      if (errorString.contains("MissingTwoFactor") ||
          errorString.contains("Two-factor authentication required")) {
        isTwoFactor = true;
        errorMessage = "Two-factor authentication required";
      } else {
        isTwoFactor = false;
        errorMessage = errorString;
      }
      sinkAddSafe();
    } catch (e) {
      final errorString = e.toString();
      if (errorString.contains("MissingTwoFactor") ||
          errorString.contains("Two-factor authentication required")) {
        isTwoFactor = true;
        errorMessage = "Two-factor authentication required";
      } else {
        isTwoFactor = false;
        errorMessage = errorString;
      }
      sinkAddSafe();
    }
  }
}
