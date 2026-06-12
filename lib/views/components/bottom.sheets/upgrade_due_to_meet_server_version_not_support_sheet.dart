import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/external.url.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/components/gradient_action_button.dart';
import 'package:meet/views/scenes/dashboard/dashboard_page.dart';

void showUpgradeDueToMeetServerVersionNotSupportSheet(BuildContext context) {
  Navigator.of(context).popUntil(
    (route) => route.settings.name == DashboardPage.routeName || route.isFirst,
  );

  if (context.mounted) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      routeSettings: const RouteSettings(
        name: 'upgrade_due_to_meet_server_version_not_support',
      ),
      builder: (_) => const UpgradeDueToMeetServerVersionNotSupportModal(),
    );
  }
}

class UpgradeDueToMeetServerVersionNotSupportModal extends StatelessWidget {
  const UpgradeDueToMeetServerVersionNotSupportModal({super.key});

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
              context.images.iconErrorMessage.svg(width: 48, height: 48),
              const SizedBox(height: 52),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Text(
                      context.local.meet_server_version_not_supported_title,
                      textAlign: TextAlign.center,
                      style: ProtonStyles.headline(
                        color: context.colors.textNorm,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context
                          .local
                          .meet_server_version_not_supported_description,
                      textAlign: TextAlign.center,
                      style: ProtonStyles.body2Medium(
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
            child: Column(
              children: [
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GradientActionButton(
                        text: context.local.upgrade,
                        onPressed: ExternalUrl.shared.lanuchStore,
                        textStyle: ProtonStyles.body1Semibold(
                          color: context.colors.textInverted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GradientActionButton(
                        text: context.local.close,
                        onPressed: () => Navigator.of(context).maybePop(),
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
