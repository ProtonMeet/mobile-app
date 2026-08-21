import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/close_button_v1.dart';

Future<bool?> showStartRecordingConfirmationDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _RecordingConfirmationDialog(isStart: true),
  );
}

Future<bool?> showStopRecordingConfirmationDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _RecordingConfirmationDialog(isStart: false),
  );
}

class _RecordingConfirmationDialog extends StatelessWidget {
  const _RecordingConfirmationDialog({required this.isStart});

  final bool isStart;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final borderNorm = context.colors.appBorderNorm;
    final padding =
        EdgeInsets.only(bottom: bottomInset) +
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16);

    final title = isStart
        ? context.local.record_this_meeting
        : context.local.stop_recording_title;
    final message = isStart
        ? context.local.recording_will_begin_attendees_notified
        : context.local.stop_recording_confirm_message;
    final primaryLabel = isStart
        ? context.local.start_recording
        : context.local.stop_recording_and_save;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnimatedPadding(
        padding: padding,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxMobileSheetWidth),
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: context.colors.backgroundSecondary,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: borderNorm),
                    borderRadius: BorderRadius.circular(40),
                  ),
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: CloseButtonV1(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.08,
                            ),
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: context.images.iconRecording.svg64(),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
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
                              message,
                              textAlign: TextAlign.center,
                              style: ProtonStyles.body2Medium(
                                color: context.colors.textWeak,
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: context.colors.protonBlue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(200),
                                  ),
                                ),
                                child: Text(
                                  primaryLabel,
                                  style: ProtonStyles.body1Semibold(
                                    color: context.colors.textInverted,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      context.colors.interActionWeak,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(200),
                                  ),
                                ),
                                child: Text(
                                  context.local.cancel,
                                  style: ProtonStyles.body1Semibold(
                                    color: context.colors.textWeak,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
