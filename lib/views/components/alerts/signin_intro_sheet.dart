import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
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
    final isLandscape = context.isLandscape;
    final maxHeight = isLandscape ? context.height - 20 : context.height - 100;

    return BaseBottomSheetV2.withPinnedSliverScroll(
      isLandscape: isLandscape,
      modalOnBackdropTap: () => Navigator.of(context).maybePop(),
      modalMaxHeight: maxHeight,
      innerEnableHandleDragPassthrough: false,
      outerEnableHandleDragPassthrough: true,
      blurSigma: 14,
      borderSideAlpha: 0.04,
      sheetBackgroundColor: context.colors.backgroundDark.withValues(
        alpha: 0.60,
      ),
      slivers: [
        SliverToBoxAdapter(
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
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(),
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
        ),
      ],
    );
  }
}
