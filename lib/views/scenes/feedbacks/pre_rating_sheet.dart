import 'dart:async';

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

  /// Presents the sheet in a modal bottom sheet.
  ///
  /// The user's positive/negative callbacks run **after** the sheet has been
  /// fully dismissed. This matters on Android: `InAppReview.requestReview()`
  /// is silently a no-op when invoked while another modal route is still in
  /// its pop animation (Play Core requires the host activity to be in the
  /// RESUMED state with no transient surface on top).
  static Future<void> show(
    BuildContext context, {
    required FutureOr<void> Function() onPositiveAction,
    required FutureOr<void> Function() onNegativeAction,
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
          onPositiveAction: () => _dismissThenRun(ctx, onPositiveAction),
          onNegativeAction: () => _dismissThenRun(ctx, onNegativeAction),
        );
      },
    );
  }

  /// Pops the sheet, awaits the dismissal animation, then runs [action] on
  /// a clean activity surface.
  static void _dismissThenRun(
    BuildContext ctx,
    FutureOr<void> Function() action,
  ) {
    final navigator = Navigator.of(ctx);
    // Fire & forget on purpose: the InkWell handler must not await, otherwise
    // the ripple/tap feedback stalls. We still chain dismissal → delay → action
    // so platform dialogs (e.g. Play Core in-app review) get a clean window.
    unawaited(() async {
      await navigator.maybePop();
      // showModalBottomSheet uses a 250 ms reverse transition; wait slightly
      // longer so the modal route is fully removed before the callback runs.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await action();
    }());
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
