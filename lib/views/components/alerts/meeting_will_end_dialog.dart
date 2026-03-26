import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

typedef OnStayInMeeting = void Function();
typedef OnLeaveMeeting = void Function();

Future<void> showMeetingWillEndDialog(
  BuildContext context, {
  required OnStayInMeeting onStayInMeeting,
  required OnLeaveMeeting onLeaveMeeting,
  required int countdownSeconds,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    routeSettings: const RouteSettings(name: 'meeting_will_end'),
    builder: (_) => MeetingWillEndDialog(
      onStayInMeeting: onStayInMeeting,
      onLeaveMeeting: onLeaveMeeting,
      countdownSeconds: countdownSeconds,
    ),
  );
}

class MeetingWillEndDialog extends StatefulWidget {
  const MeetingWillEndDialog({
    required this.onStayInMeeting,
    required this.onLeaveMeeting,
    required this.countdownSeconds,
    super.key,
  });

  final OnStayInMeeting onStayInMeeting;
  final OnLeaveMeeting onLeaveMeeting;
  final int countdownSeconds;

  @override
  State<MeetingWillEndDialog> createState() => _MeetingWillEndDialogState();
}

class _MeetingWillEndDialogState extends State<MeetingWillEndDialog> {
  late int _remainingSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.countdownSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        timer.cancel();
        // Auto leave when countdown reaches 0
        widget.onLeaveMeeting();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  void _handleStayInMeeting() {
    _timer?.cancel();
    Navigator.of(context).pop();
    widget.onStayInMeeting();
  }

  void _handleLeaveMeeting() {
    _timer?.cancel();
    Navigator.of(context).pop();
    widget.onLeaveMeeting();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: maxMobileSheetWidth),
        decoration: ShapeDecoration(
          color: context.colors.backgroundSecondary,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: context.colors.appBorderNorm),
            borderRadius: BorderRadius.circular(40),
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 24),

              /// Title with countdown
              Text(
                context.local.meeting_will_end_in(
                  _formatTime(_remainingSeconds),
                ),
                textAlign: TextAlign.center,
                style: ProtonStyles.headline(color: context.colors.textNorm),
              ),
              const SizedBox(height: 16),

              /// Description
              Text(
                context.local.meeting_will_end_description,
                textAlign: TextAlign.center,
                style: ProtonStyles.body2Medium(color: context.colors.textWeak),
              ),
              const SizedBox(height: 24),

              /// Action buttons
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _handleStayInMeeting,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.signalDangerMajor3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(200),
                    ),
                  ),
                  child: Text(
                    context.local.stay_in_the_meeting,
                    style: ProtonStyles.body1Semibold(
                      color: context.colors.textInverted,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              /// Leave meeting button (secondary)
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _handleLeaveMeeting,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.interActionWeak,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(200),
                    ),
                  ),
                  child: Text(
                    context.local.leave_meeting,
                    style: ProtonStyles.body1Semibold(
                      color: context.colors.textNorm,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
