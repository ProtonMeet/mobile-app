import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/components/gradient_action_button.dart';

typedef OnCreateAccount = Future<void> Function();
typedef OnSignIn = Future<void> Function();

enum AlmostThereContext { schedule, createRoom, personalRoom }

Future<void> showAlmostThereBottomSheet(
  BuildContext context, {
  required AlmostThereContext almostThereContext,
  required OnCreateAccount onCreateAccount,
  required OnSignIn onSignIn,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (context) => AlmostThereModal(
      almostThereContext: almostThereContext,
      onCreateAccount: onCreateAccount,
      onSignIn: onSignIn,
    ),
  );
}

class AlmostThereModal extends StatelessWidget {
  const AlmostThereModal({
    required this.almostThereContext,
    required this.onCreateAccount,
    required this.onSignIn,
    super.key,
  });

  final AlmostThereContext almostThereContext;
  final OnCreateAccount onCreateAccount;
  final OnSignIn onSignIn;

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
          child: _AlmostThereUpper(almostThereContext: almostThereContext),
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
                        onPressed: onCreateAccount,
                        textStyle: ProtonStyles.body1Semibold(
                          color: context.colors.textInverted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GradientActionButton(
                        text: context.local.signin_intro_sign_in,
                        onPressed: onSignIn,
                        textStyle: ProtonStyles.body1Semibold(
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
                const SizedBox(height: 52),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AlmostThereUpper extends StatelessWidget {
  const _AlmostThereUpper({required this.almostThereContext});

  final AlmostThereContext almostThereContext;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 52),
        _getImage(context, almostThereContext),
        const SizedBox(height: 52),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Text(
                context.local.almost_there_title,
                textAlign: TextAlign.center,
                style: ProtonStyles.headline(color: context.colors.textNorm),
              ),
              const SizedBox(height: 16),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _contentBeforeForContext(
                        context,
                        almostThereContext,
                      ),
                      style: ProtonStyles.body2Medium(
                        color: context.colors.textWeak,
                      ),
                    ),
                    TextSpan(
                      text: context.local.almost_there_proton_account,
                      style: ProtonStyles.body2Medium(
                        color: context.colors.white,
                      ),
                    ),
                    TextSpan(
                      text: context.local.almost_there_content_after,
                      style: ProtonStyles.body2Medium(
                        color: context.colors.textWeak,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}

String _contentBeforeForContext(BuildContext context, AlmostThereContext ctx) {
  switch (ctx) {
    case AlmostThereContext.schedule:
      return context.local.almost_there_content_before;
    case AlmostThereContext.createRoom:
      return context.local.almost_there_content_before_create_room;
    case AlmostThereContext.personalRoom:
      return context.local.almost_there_content_before_personal_room;
  }
}

Widget _getImage(BuildContext context, AlmostThereContext almostThereContext) {
  final image = switch (almostThereContext) {
    AlmostThereContext.schedule => context.images.iconCalendarModalHeader,
    AlmostThereContext.createRoom => context.images.iconPeopleModalHeader,
    AlmostThereContext.personalRoom => context.images.iconPeopleModalHeader,
  };

  return SizedBox(width: 64, height: 64, child: image.svg64());
}
