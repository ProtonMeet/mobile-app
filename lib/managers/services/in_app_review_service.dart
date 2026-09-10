import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/managers/channels/platform_info_channel.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/managers/providers/unleash.data.provider.dart';
import 'package:meet/managers/user_activity.manager.dart';
import 'package:meet/views/scenes/feedbacks/pre_rating_sheet.dart'
    show PreRatingSheet;

/// Store in-app review ([InAppReview.requestReview]). Uses [UserActivityManager]
/// for engagement, cooldown, and deferred flags; this type only gates and invokes
/// the OS prompt.
class InAppReviewService {
  InAppReviewService._();

  /// Whether [InAppReview.requestReview] may be attempted for the deferred flow
  /// (platform + deferred state). Does not consider the global cooldown.
  static Future<bool> canShowStoreReview() async {
    if (kIsWeb) return false;

    try {
      final unleash = ManagerFactory()
          .get<DataProviderManager>()
          .unleashDataProvider;
      if (!unleash.isMeetInAppStoreReviewEnabled()) return false;
    } catch (e, st) {
      logger.w(
        '[InAppReview] Unleash MeetInAppStoreReview: $e',
        stackTrace: st,
      );
      return false;
    }

    // check if the app is running through testflight
    final isFromTestFlight = await PlatformInfoChannel.isFromTestFlight();
    if (isFromTestFlight) return false;

    try {
      final ua = ManagerFactory().get<UserActivityManager>();
      if (!await ua.isDeferredStoreReviewReadyForPrompt()) return false;

      final inAppReview = InAppReview.instance;
      if (!await inAppReview.isAvailable()) return false;

      return true;
    } catch (e, st) {
      logger.w('[InAppReview] canShowStoreReview: $e', stackTrace: st);
    }
    return false;
  }

  /// Pre-rating sheet: user chose the negative path — thanks toast and persist
  /// a cooldown so the prompt is not offered again for several days.
  static Future<void> onPreRatingNegativeAction({BuildContext? context}) async {
    try {
      if (context != null && context.mounted) {
        LocalToast.showToast(context, context.local.store_review_thanks_toast);
      }
      await ManagerFactory()
          .get<UserActivityManager>()
          .recordPreRatingNegativeResponse();
    } catch (e, st) {
      logger.w('[InAppReview] onPreRatingNegativeAction: $e', stackTrace: st);
    }
  }

  /// Debug / manual: deferred eligibility + [InAppReview.requestReview], ignoring
  /// the global cooldown.
  static Future<bool> tryRequestReviewForDebug() => tryRequestReview(
    requireDeferredEligibility: false,
    respectGlobalCooldown: false,
    clearDeferredPendingOnSuccess: false,
  );

  /// Evaluates gates and calls [InAppReview.requestReview] when they pass.
  ///
  /// Use [canShowStoreReview] before UI such as [PreRatingSheet] when the deferred
  /// flow applies.
  ///
  /// Gates (in order): not web; [requireDeferredEligibility] → deferred prompt
  /// ready; [respectGlobalCooldown] → global cooldown inactive;
  /// [InAppReview.isAvailable].
  ///
  /// [thanksToastContext]: when non-null, shows the thanks toast before
  /// "requestReview" (e.g. after the user taps positive on the sheet).
  ///
  /// [clearDeferredPendingOnSuccess]: after a successful "requestReview", clears
  /// the deferred flag (cold-start / post-sheet flow).
  static Future<bool> tryRequestReview({
    BuildContext? thanksToastContext,
    bool requireDeferredEligibility = true,
    bool respectGlobalCooldown = true,
    bool clearDeferredPendingOnSuccess = true,
  }) async {
    if (kIsWeb) return false;

    try {
      if (requireDeferredEligibility) {
        if (!await canShowStoreReview()) return false;
      }

      final ua = ManagerFactory().get<UserActivityManager>();
      if (respectGlobalCooldown) {
        if (await ua.isGlobalStoreReviewCooldownActive()) return false;
      }

      final inAppReview = InAppReview.instance;
      if (!await inAppReview.isAvailable()) return false;

      final toastCtx = thanksToastContext;
      if (toastCtx != null && toastCtx.mounted) {
        LocalToast.showToast(
          toastCtx,
          toastCtx.local.store_review_thanks_toast,
        );
      }

      try {
        await inAppReview.requestReview();
      } catch (e, st) {
        logger.w('[InAppReview] requestReview failed: $e', stackTrace: st);
        return false;
      }

      await ua.markGlobalInAppReviewPromptCompleted();
      if (clearDeferredPendingOnSuccess) {
        await ua.clearDeferredStoreReviewPending();
      }
      return true;
    } catch (e, st) {
      logger.w('[InAppReview] tryRequestReview: $e', stackTrace: st);
      return false;
    }
  }
}
