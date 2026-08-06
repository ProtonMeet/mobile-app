import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/scenes/dashboard/dashboard_page.dart';

void showJoinMeetingBlockedBottomSheet(
  BuildContext context, {
  required String title,
  required String description,
  required String routeName,
}) {
  Navigator.of(context).popUntil(
    (route) => route.settings.name == DashboardPage.routeName || route.isFirst,
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;

    final isLandscape = context.isLandscape;
    final maxHeight = isLandscape ? context.height - 20 : context.height - 100;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      routeSettings: RouteSettings(name: routeName),
      builder: (_) => JoinMeetingBlockedModal(
        title: title,
        description: description,
        isLandscape: isLandscape,
        maxHeight: maxHeight,
      ),
    );
  });
}

class JoinMeetingBlockedModal extends StatelessWidget {
  const JoinMeetingBlockedModal({
    required this.title,
    required this.description,
    required this.isLandscape,
    required this.maxHeight,
    super.key,
  });

  final String title;
  final String description;
  final bool isLandscape;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
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
                      title,
                      textAlign: TextAlign.center,
                      style: ProtonStyles.headline(
                        color: context.colors.textNorm,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      description,
                      textAlign: TextAlign.start,
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.drawerBackground,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(200),
                      ),
                    ),
                    child: Text(
                      context.local.close,
                      style: ProtonStyles.body1Semibold(
                        color: context.colors.protonBlue,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }
}
