import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/components/gradient_action_button.dart';

/// Confirmation bottom sheet shown before the user enables live captions
/// (web: `CaptionsModal.tsx`).
Future<bool?> showLiveCaptionsEnableDialog(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (_) => const LiveCaptionsEnableBottomSheet(),
  );
}

class LiveCaptionsEnableBottomSheet extends StatelessWidget {
  const LiveCaptionsEnableBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseBottomSheet(
      blurSigma: 14,
      backgroundColor: context.colors.backgroundDark.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      onBackdropTap: () => Navigator.of(context).pop(false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          const BottomSheetHandleBar(),
          const SizedBox(height: 48),
          context.images.iconLiveCaptions.svg64(),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Text(
                  context.local.live_captions_modal_title,
                  textAlign: TextAlign.center,
                  style: ProtonStyles.headline(color: context.colors.textNorm),
                ),
                const SizedBox(height: 16),
                Text(
                  context.local.live_captions_modal_message,
                  textAlign: TextAlign.center,
                  style: ProtonStyles.body2Medium(
                    color: context.colors.textWeak,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GradientActionButton(
                  text: context.local.live_captions_enable,
                  onPressed: () => Navigator.of(context).pop(true),
                  textStyle: ProtonStyles.body1Semibold(
                    color: context.colors.textInverted,
                  ),
                ),
                const SizedBox(height: 8),
                GradientActionButton(
                  text: context.local.cancel,
                  onPressed: () => Navigator.of(context).pop(false),
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
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
