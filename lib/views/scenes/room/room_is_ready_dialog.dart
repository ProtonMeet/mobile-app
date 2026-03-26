import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';

Future<void> showRoomReadyBottomSheet(
  BuildContext context, {
  required String meetingLink,
  VoidCallback? onCopied,
  VoidCallback? onClosed,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (context) => LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = context.height;
        final availableHeight = screenHeight * 0.9;
        // Approximate height: handle bar + title + subtitle + link card + button + padding
        final contentHeight = 100.0 + 80.0 + 120.0 + 60.0 + 100.0;
        final maxHeight = contentHeight > availableHeight
            ? availableHeight
            : contentHeight;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: BaseBottomSheet(
            backgroundColor: context.colors.backgroundDark.withValues(
              alpha: 0.60,
            ),
            blurSigma: 14,
            maxHeight: maxHeight,
            contentPadding: const EdgeInsets.only(bottom: 24),
            onBackdropTap: () {
              Navigator.of(context).maybePop();
              onClosed?.call();
            },
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  const BottomSheetHandleBar(),
                  const SizedBox(height: 24),
                  _RoomReadyContent(
                    meetingLink: meetingLink,
                    onCopied: () async {
                      await Clipboard.setData(ClipboardData(text: meetingLink));
                      if (context.mounted) {
                        LocalToast.showToast(
                          context,
                          context.local.link_copied_to_clipboard,
                          textStyle: ProtonStyles.bodySmallSemibold(
                            color: context.colors.textInverted,
                          ),
                        );
                        // Dismiss the dialog after copying
                        Navigator.of(context).pop();
                        onClosed?.call();
                      }
                      onCopied?.call();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _RoomReadyContent extends StatelessWidget {
  const _RoomReadyContent({required this.meetingLink, required this.onCopied});

  final String meetingLink;
  final VoidCallback onCopied;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        /// Title + subtitle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Text(
                context.local.your_meeting_is_ready,
                textAlign: TextAlign.center,
                style: ProtonStyles.headline(color: context.colors.textNorm),
              ),
              const SizedBox(height: 8),
              Text(
                context.local.share_link_invite_description,
                textAlign: TextAlign.center,
                style: ProtonStyles.bodySmallSemibold(
                  color: context.colors.textWeak,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Link card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            width: double.infinity,
            decoration: ShapeDecoration(
              color: context.colors.backgroundCard,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: context.colors.borderCard),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.local.meeting_link,
                  style: ProtonStyles.bodySmallSemibold(
                    color: context.colors.textWeak,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  meetingLink,
                  style: ProtonStyles.bodySmallSemibold(
                    color: context.colors.protonBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        /// Copy button
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              onPressed: onCopied,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.interActionWeak,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(200),
                ),
              ),
              child: Text(
                context.local.copy_link_and_close,
                style: ProtonStyles.body1Medium(color: context.colors.textNorm),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
