import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/components/gradient_action_button.dart';

typedef SessionExpiredSignInAction = FutureOr<void> Function();
typedef SessionExpiredContinueAction = FutureOr<void> Function();

Future<void> showSessionErrorDialog(
  BuildContext context, {
  required SessionExpiredSignInAction onSignIn,
  SessionExpiredContinueAction? onContinueWithoutSignIn,
}) async {
  final isLandscape = context.isLandscape;
  final maxHeight = isLandscape ? context.height - 20 : context.height - 100;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.1),
    isDismissible: false,
    builder: (_) => _SessionExpiredBottomSheet(
      maxHeight: maxHeight,
      isLandscape: isLandscape,
      onSignIn: onSignIn,
      onContinueWithoutSignIn: onContinueWithoutSignIn,
    ),
  );
}

class _SessionExpiredBottomSheet extends StatelessWidget {
  const _SessionExpiredBottomSheet({
    required this.maxHeight,
    required this.isLandscape,
    required this.onSignIn,
    this.onContinueWithoutSignIn,
  });

  final double maxHeight;
  final bool isLandscape;
  final SessionExpiredSignInAction onSignIn;
  final SessionExpiredContinueAction? onContinueWithoutSignIn;

  @override
  Widget build(BuildContext context) {
    return BaseBottomSheetV2.withPinnedSliverScroll(
      isLandscape: isLandscape,
      modalMaxHeight: maxHeight,
      modalOnBackdropTap: () => Navigator.of(context).maybePop(),
      innerEnableHandleDragPassthrough: false,
      outerEnableHandleDragPassthrough: true,
      blurSigma: 14,
      borderSideAlpha: 0.04,
      sheetBackgroundColor: context.colors.backgroundDark.withValues(
        alpha: 0.6,
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 52),
              context.images.iconSessionExpired.svg64(),
              const SizedBox(height: 52),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Text(
                      context.local.session_expired_title,
                      textAlign: TextAlign.center,
                      style: ProtonStyles.subheadline(
                        color: context.colors.interActionNormMajor1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.local.session_expired_content,
                      textAlign: TextAlign.center,
                      style: ProtonStyles.body1Medium(
                        color: context.colors.textWeak,
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
            top: false,
            child: Column(
              children: [
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      GradientActionButton(
                        text: context.local.signin_intro_sign_in,
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await onSignIn.call();
                        },
                        textStyle: ProtonStyles.body1Semibold(
                          color: context.colors.textInverted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GradientActionButton(
                        text: context
                            .local
                            .session_expired_continue_without_signing_in,
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await onContinueWithoutSignIn?.call();
                        },
                        textStyle: ProtonStyles.body1Medium(
                          color: context.colors.textNorm,
                        ),
                        colors: [
                          context.colors.interActionWeak,
                          context.colors.interActionWeak,
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
