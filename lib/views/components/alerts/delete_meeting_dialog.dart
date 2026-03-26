import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';

Future<bool?> showDeleteMeetingDialog(
  BuildContext context, {
  required FrbUpcomingMeeting meeting,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (_) => DeleteMeetingDialog(meeting: meeting),
  );
}

class DeleteMeetingDialog extends StatelessWidget {
  const DeleteMeetingDialog({required this.meeting, super.key});

  final FrbUpcomingMeeting meeting;

  @override
  Widget build(BuildContext context) {
    return BaseBottomSheet(
      blurSigma: 14,
      backgroundColor: context.colors.backgroundDark.withValues(alpha: 0.3),
      contentPadding: const EdgeInsets.only(bottom: 24),
      child: SafeArea(
        left: false,
        right: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const BottomSheetHandleBar(),
            const SizedBox(height: 40),

            /// Delete icon
            context.images.iconWarningMessage.svg70(),
            const SizedBox(height: 24),

            /// Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                context.local.delete_meeting,
                textAlign: TextAlign.center,
                style: ProtonStyles.headline(color: context.colors.textNorm),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                context.local.delete_meeting_confirmation,
                textAlign: TextAlign.center,
                style: ProtonStyles.body2Medium(color: context.colors.textWeak),
              ),
            ),
            const SizedBox(height: 24),

            /// Room name field
            if (meeting.meetingName.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  width: double.infinity,
                  decoration: ShapeDecoration(
                    color: context.colors.white.withValues(alpha: 0.03),
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        color: context.colors.white.withValues(alpha: 0.03),
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.local.room_name,
                        style: ProtonStyles.body2Medium(
                          color: context.colors.textWeak,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        meeting.meetingName,
                        style: ProtonStyles.body1Semibold(
                          color: context.colors.textNorm,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),

            /// Delete button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.signalDangerMajor3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(200),
                    ),
                  ),
                  child: Text(
                    context.local.delete,
                    style: ProtonStyles.body1Semibold(
                      color: context.colors.textNorm,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            /// Cancel button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: context.colors.backgroundCard,
                    side: BorderSide(color: context.colors.borderCard),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(200),
                    ),
                  ),
                  child: Text(
                    context.local.cancel,
                    style: ProtonStyles.body1Semibold(
                      color: context.colors.textNorm,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
