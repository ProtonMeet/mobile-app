import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/scenes/feedbacks/pre_rating_sheet_actions.dart';
import 'package:meet/views/scenes/feedbacks/pre_rating_sheet_hero.dart';

/// Pre–in-app-review sheet: enjoyment prompt, rating CTA, and report path.
///
/// Uses [BaseBottomSheetV2.withPinnedSliverScroll] bottom sheet
/// (pinned drag handle, blur shell, modal backdrop).
class PreRatingSheet extends StatelessWidget {
  const PreRatingSheet({
    required this.maxHeight,
    required this.isLandscape,
    required this.onPositiveAction,
    required this.onNegativeAction,
    super.key,
  });

  final double maxHeight;
  final bool isLandscape;
  final VoidCallback onPositiveAction;
  final VoidCallback onNegativeAction;

  /// Presents the sheet in a modal bottom sheet
  static Future<void> show(
    BuildContext context, {
    required VoidCallback onPositiveAction,
    required VoidCallback onNegativeAction,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.1),
      builder: (ctx) {
        final isLandscape = ctx.isLandscape;
        final maxHeight = isLandscape ? ctx.height - 20 : ctx.height - 100;
        return PreRatingSheet(
          maxHeight: maxHeight,
          isLandscape: isLandscape,
          onPositiveAction: () {
            Navigator.of(ctx).maybePop();
            onPositiveAction();
          },
          onNegativeAction: () {
            Navigator.of(ctx).maybePop();
            onNegativeAction();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BaseBottomSheetV2.withPinnedSliverScroll(
      isLandscape: isLandscape,
      modalOnBackdropTap: () => Navigator.of(context).maybePop(),
      modalMaxHeight: maxHeight,
      modalFillMaxHeight: false,
      innerEnableHandleDragPassthrough: false,
      outerEnableHandleDragPassthrough: true,
      borderSideAlpha: 0.04,
      sheetBackgroundColor: context.colors.interActionWeekMinor2.withValues(
        alpha: 0.30,
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 50),
              PreRatingSheetHero(
                title: context.local.pre_rating_sheet_title,
                subtitle: context.local.pre_rating_sheet_subtitle,
              ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              const SizedBox(height: 32),
              PreRatingSheetActions(
                positiveLabel:
                    context.local.pre_rating_sheet_yes_enjoy_proton_meet,
                negativeLabel:
                    context.local.pre_rating_sheet_not_really_enjoy_proton_meet,
                onPositiveAction: onPositiveAction,
                onNegativeAction: onNegativeAction,
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
