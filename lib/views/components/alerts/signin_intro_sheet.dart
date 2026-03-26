import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/gradient_action_button.dart';
import 'package:meet/views/components/version_text.dart';

Future<void> showSignInIntroSheet(
  BuildContext context, {
  required String versionDisplay,
  required VoidCallback onSignIn,
  required VoidCallback onSignUp,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.1),
    builder: (context) {
      return SignInIntroSheet(
        versionDisplay: versionDisplay,
        onSignIn: onSignIn,
        onSignUp: onSignUp,
      );
    },
  );
}

class SignInIntroSheet extends StatelessWidget {
  const SignInIntroSheet({
    required this.versionDisplay,
    required this.onSignIn,
    required this.onSignUp,
    super.key,
  });

  final String versionDisplay;
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    final maxHeight = context.height - 60;

    return BaseBottomSheet(
      backgroundColor: context.colors.backgroundDark.withValues(alpha: 0.60),
      blurSigma: 14,
      maxHeight: maxHeight,
      contentPadding: const EdgeInsets.only(bottom: 24),
      onBackdropTap: () {
        Navigator.of(context).maybePop();
      },
      child: SizedBox(
        height: maxHeight,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _buildHandleBar(context),
              const SizedBox(height: 24),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 52),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: context.images.iconLeaveMeetingGuest.svg72(),
                    ),
                    const SizedBox(height: 52),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        children: [
                          Text(
                            context.local.signin_intro_title,
                            textAlign: TextAlign.center,
                            style: ProtonStyles.subheadline(
                              color: context.colors.textNorm,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.local.signin_intro_subtitle,
                            textAlign: TextAlign.center,
                            style: ProtonStyles.body1Medium(
                              color: context.colors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: Container()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GradientActionButton(
                            text: context.local.signin_intro_create_account,
                            textStyle: ProtonStyles.body1Semibold(
                              color: context.colors.textInverted,
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                              onSignUp();
                            },
                          ),
                          const SizedBox(height: 8),
                          GradientActionButton(
                            text: context.local.signin_intro_sign_in,
                            textStyle: ProtonStyles.body2Medium(
                              color: context.colors.textNorm,
                            ),
                            colors: [
                              context.colors.interActionWeak,
                              context.colors.interActionWeak,
                            ],
                            onPressed: () {
                              Navigator.of(context).pop();
                              onSignIn();
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    VersionText(versionDisplay: versionDisplay),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildHandleBar(BuildContext context) {
  return Container(
    width: 36,
    height: 4,
    decoration: BoxDecoration(
      color: context.colors.textWeak.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(100),
    ),
  );
}
