import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/close_button_v1.dart';

typedef OnLeaveMeeting = void Function();

Future<void> showRecordingInProgressDialog(
  BuildContext context, {
  required OnLeaveMeeting onLeaveMeeting,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => RecordingInProgressDialog(onLeaveMeeting: onLeaveMeeting),
  );
}

class RecordingInProgressDialog extends StatelessWidget {
  const RecordingInProgressDialog({required this.onLeaveMeeting, super.key});

  final OnLeaveMeeting onLeaveMeeting;

  void _handleContinue(BuildContext context) {
    Navigator.of(context).pop();
  }

  void _handleLeaveMeeting(BuildContext context) {
    Navigator.of(context).pop();
    onLeaveMeeting();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final borderNorm = context.colors.appBorderNorm;
    final padding =
        EdgeInsets.only(bottom: bottomInset) +
        const EdgeInsets.symmetric(horizontal: 16, vertical: 16);

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
                      /// Close button
                      Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: CloseButtonV1(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.08,
                            ),
                            onPressed: () => _handleContinue(context),
                          ),
                        ),
                      ),

                      /// Icon
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          width: 64,
                          height: 64,
                          clipBehavior: Clip.antiAlias,
                          decoration: const BoxDecoration(),
                          child: context.images.iconEarlyAccess.svg(
                            width: 64,
                            height: 64,
                            fit: BoxFit.fitWidth,
                          ),
                        ),
                      ),

                      /// Title & subtitle
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            Text(
                              context.local.meeting_being_recorded,
                              textAlign: TextAlign.center,
                              style: ProtonStyles.headline(
                                color: context.colors.textNorm,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.local.recording_consent_message,
                              textAlign: TextAlign.center,
                              style: ProtonStyles.body2Medium(
                                color: context.colors.textWeak,
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),

                      /// Action buttons
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            /// Agree and continue button
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                onPressed: () => _handleContinue(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: context.colors.protonBlue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(200),
                                  ),
                                ),
                                child: Text(
                                  context.local.agree_and_continue,
                                  style: ProtonStyles.body1Semibold(
                                    color: context.colors.textInverted,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            /// Leave meeting button
                            SizedBox(
                              width: double.infinity,
                              height: 60,
                              child: ElevatedButton(
                                onPressed: () => _handleLeaveMeeting(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      context.colors.interActionWeak,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(200),
                                  ),
                                ),
                                child: Text(
                                  context.local.leave_meeting,
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
