import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/scenes/core/responsive_v2.dart';
import 'package:meet/views/scenes/room/recording/meeting_recorder.dart';
import 'package:meet/views/scenes/room/recording/recording_confirmation_dialog.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:proton_screen_recorder/proton_screen_recorder.dart';

/// Host/admin recording controls — mirrors web [RecordingControls].
class RecordingControls extends StatefulWidget {
  const RecordingControls({
    required this.meetingRecorder,
    required this.showUpsellOnTap,
    super.key,
  });

  final MeetingRecorder meetingRecorder;
  final VoidCallback? showUpsellOnTap;

  @override
  State<RecordingControls> createState() => _RecordingControlsState();
}

class _RecordingControlsState extends State<RecordingControls> {
  bool? _isSupported;

  @override
  void initState() {
    super.initState();
    unawaited(_loadSupported());
  }

  Future<void> _loadSupported() async {
    final supported = await widget.meetingRecorder.isSupported();
    if (mounted) {
      setState(() => _isSupported = supported);
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _handleStart(BuildContext context) async {
    final confirmed = await showStartRecordingConfirmationDialog(context);
    if (confirmed != true || !context.mounted) return;

    try {
      await widget.meetingRecorder.startRecording();
    } on ScreenRecordingNotSupportedException {
      if (context.mounted) {
        LocalToast.showToastification(
          context,
          context.local.error,
          _unsupportedRecordingMessage(context),
        );
      }
    } catch (_) {
      if (context.mounted) {
        LocalToast.showToastification(
          context,
          context.local.error,
          context.local.failed_to_start_recording,
        );
      }
    }
  }

  Future<void> _handleStop(BuildContext context) async {
    final confirmed = await showStopRecordingConfirmationDialog(context);
    if (confirmed != true || !context.mounted) return;
    await widget.meetingRecorder.finishRecording();
  }

  String _unsupportedRecordingMessage(BuildContext context) {
    if (!kIsWeb &&
        Platform.isIOS &&
        Platform.environment.containsKey('SIMULATOR_DEVICE_NAME')) {
      return context.local.recording_simulator_not_supported;
    }
    return context.local.recording_not_supported;
  }

  @override
  Widget build(BuildContext context) {
    if (_isSupported == false) {
      return const SizedBox.shrink();
    }

    return BlocSelector<RoomBloc, RoomState, (bool, int)>(
      selector: (state) => (
        state.isLocalParticipantRecording,
        state.localRecordingElapsedSeconds,
      ),
      builder: (context, data) {
        final isLocalRecording = data.$1;
        final elapsed = data.$2;

        if (!isLocalRecording) {
          return _RecordButton(
            tooltip: context.local.start_recording,
            onPressed: widget.showUpsellOnTap ?? () => _handleStart(context),
          );
        }

        return Material(
          color: context.colors.signalDangerMajor3,
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => _handleStop(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.stop_rounded,
                    color: context.colors.white,
                    size: 24,
                  ),
                  if (context.isAtLeastMedium) ...[
                    const SizedBox(width: 8),
                    Text(
                      context.local.stop_recording,
                      style: ProtonStyles.body2Semibold(
                        color: context.colors.white,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: Text(
                      _formatDuration(elapsed),
                      textAlign: TextAlign.center,
                      style:
                          ProtonStyles.body2Semibold(
                            color: context.colors.white,
                          ).copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: context.colors.controlButtonBackground,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Center(child: context.images.iconRecording.svg24()),
          ),
        ),
      ),
    );
  }
}
