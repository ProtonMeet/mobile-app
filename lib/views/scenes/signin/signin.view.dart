import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:meet/constants/assets.gen.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/l10n/generated/locale.dart';
import 'package:meet/rust/proton_meet/models/user.dart';
import 'package:meet/views/scenes/core/view.dart';
import 'package:meet/views/scenes/signin/signin.viewmodel.dart';

class SigninView extends ViewBase<SigninViewModel> {
  final Function(ProtonUser) onLoginSuccess;

  const SigninView(SigninViewModel viewModel, {required this.onLoginSuccess})
    : super(viewModel, const Key("SigninView"));

  @override
  Widget build(BuildContext context) {
    return buildWelcome(context);
  }

  Widget buildWelcome(BuildContext context) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    /// This is the workaround to show the error message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Check for login success
      if (viewModel.loginSuccess && viewModel.loginUser != null) {
        viewModel.loginSuccess = false; // Reset the flag
        final user = viewModel.loginUser!;
        viewModel.loginUser = null; // Clear the user data

        final loggedInUser = ProtonUser(
          id: user.userId,
          name: user.userName,
          email: user.userMail,
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
        onLoginSuccess(loggedInUser); // Pass the user data to the callback
        return Navigator.of(context).pop();
      }

      if (viewModel.errorMessage.isNotEmpty) {
        if (viewModel.errorMessage.contains("MissingTwoFactor") ||
            viewModel.errorMessage.contains("two-factor") ||
            viewModel.errorMessage.contains("2FA")) {
          // Show 2FA dialog
          _show2FADialog(
            context,
            usernameController.text,
            passwordController.text,
          );
        } else {
          LocalToast.showErrorToast(context, viewModel.errorMessage);
        }
        viewModel.errorMessage = "";
      }

      // Also check the isTwoFactor flag
      if (viewModel.isTwoFactor) {
        _show2FADialog(
          context,
          usernameController.text,
          passwordController.text,
        );
        viewModel.isTwoFactor = false;
      }
    });

    return AlertDialog(
      title: SignInHeader(),
      backgroundColor: context.colors.backgroundNorm,
      content: SigninContentForm(
        usernameController: usernameController,
        passwordController: passwordController,
      ),
      actions: [
        TextButton(
          onPressed: () {
            // Closes the dialog
            Navigator.of(context).pop();
          },
          child: Text(
            // cancel
            context.local.cancel,
            style: ProtonStyles.body2Regular(color: Colors.grey),
          ),
        ),
        TextButton(
          onPressed: () async {
            // Logic for logging in goes here
            EasyLoading.show(maskType: EasyLoadingMaskType.black);
            await viewModel.signIn(
              usernameController.text,
              passwordController.text,
              "", // Empty 2FA code for initial login
            );
            EasyLoading.dismiss();
            // Success handling is now done in the PostFrameCallback above
          },
          child: Text(
            // login
            context.local.login,
            style: ProtonStyles.body2Regular(),
          ),
        ),
      ],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  void _show2FADialog(BuildContext context, String username, String password) {
    final twoFactorController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.security, color: context.colors.protonBlue, size: 24),
              const SizedBox(width: 8),
              Text(
                "Two-Factor Authentication",
                style: ProtonStyles.body1Medium(),
              ),
            ],
          ),
          backgroundColor: context.colors.backgroundNorm,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Please enter your 2FA code to continue",
                style: ProtonStyles.body2Regular(
                  color: context.colors.textWeak,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "2FA Code",
                style: ProtonStyles.body2Medium(color: context.colors.textWeak),
              ),
              const SizedBox(height: 8),
              CupertinoTextField.borderless(
                controller: twoFactorController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: ProtonStyles.body1Regular(
                  color: context.colors.textNorm,
                ),
                decoration: BoxDecoration(
                  color: context.colors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(14.0),
                ),
                padding: const EdgeInsets.symmetric(
                  vertical: 12.0,
                  horizontal: 16.0,
                ),
                placeholder: "123456",
                placeholderStyle: ProtonStyles.body1Regular(
                  color: context.colors.textWeak.withValues(alpha: 0.5),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                context.local.cancel,
                style: ProtonStyles.body2Regular(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () async {
                if (twoFactorController.text.isNotEmpty) {
                  Navigator.of(context).pop();
                  EasyLoading.show(maskType: EasyLoadingMaskType.black);
                  await viewModel.signIn(
                    username,
                    password,
                    twoFactorController.text,
                  );
                  EasyLoading.dismiss();
                  // Success/failure handling is done in the PostFrameCallback
                }
              },
              child: Text("Verify", style: ProtonStyles.body2Regular()),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        );
      },
    );
  }
}

class SigninContentForm extends StatelessWidget {
  const SigninContentForm({
    required this.usernameController,
    required this.passwordController,
    super.key,
  });

  final TextEditingController usernameController;
  final TextEditingController passwordController;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, // Align text to the left
        children: [
          Text(
            S.of(context).sign_in,
            style: ProtonStyles.body2Medium(color: context.colors.textWeak),
            textAlign: TextAlign.left,
          ),
          SizedBox(height: 8),
          CupertinoTextField.borderless(
            keyboardType: TextInputType.emailAddress,
            controller: usernameController,
            style: ProtonStyles.body1Regular(color: context.colors.textNorm),
            decoration: BoxDecoration(
              color: context.colors.backgroundSecondary,
              borderRadius: BorderRadius.circular(14.0),
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 12.0,
              horizontal: 16.0,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.local.password,
            style: ProtonStyles.body2Medium(color: context.colors.textWeak),
            textAlign: TextAlign.left,
          ),
          const SizedBox(height: 8),
          CupertinoTextField.borderless(
            keyboardType: TextInputType.visiblePassword,
            obscureText: true,
            controller: passwordController,
            style: ProtonStyles.body1Regular(color: context.colors.textNorm),
            decoration: BoxDecoration(
              color: context.colors.backgroundSecondary,
              borderRadius: BorderRadius.circular(14.0),
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 12.0,
              horizontal: 16.0,
            ),
          ),
        ],
      ),
    );
  }
}

class SignInHeader extends StatelessWidget {
  const SignInHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 340),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          Assets.images.logos.protonPLogo.svg(),
          const SizedBox(height: 20),
          Text(
            S.of(context).sign_in_to_proton_title,
            style: ProtonStyles.hero(),
          ),
          const SizedBox(height: 8),
          Text(
            S.of(context).sign_in_to_proton_subtitle,
            style: ProtonStyles.body1Regular(),
          ),
        ],
      ),
    );
  }
}
