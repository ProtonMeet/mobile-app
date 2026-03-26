import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/alerts/recording_in_progress_dialog.dart';

extension LKExampleExt on BuildContext {
  Future<bool?> showPlayAudioManuallyDialog() => showDialog<bool>(
    context: this,
    builder: (context) {
      return AlertDialog(
        title: Text(context.local.play_audio),
        content: Text(context.local.ios_safari_audio_activation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.local.ignore),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.local.play_audio),
          ),
        ],
      );
    },
  );

  Future<bool?> showDataReceivedDialog(String data) => showDialog<bool>(
    context: this,
    builder: (context) {
      return AlertDialog(
        title: Text(context.local.received_data),
        content: Text(data),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.local.ok),
          ),
        ],
      );
    },
  );

  Future<void> showRecordingStatusChangedDialog({
    required VoidCallback onLeaveMeeting,
  }) {
    return showRecordingInProgressDialog(this, onLeaveMeeting: onLeaveMeeting);
  }

  Future<bool?> showSubscribePermissionDialog() => showDialog<bool>(
    context: this,
    builder: (context) {
      return AlertDialog(
        title: Text(context.local.allow_subscription),
        content: Text(context.local.allow_subscription_question),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.local.no),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.local.yes),
          ),
        ],
      );
    },
  );

  Future<SimulateScenarioResult?> showSimulateScenarioDialog() =>
      showDialog<SimulateScenarioResult>(
        context: this,
        builder: (context) {
          return SimpleDialog(
            title: Text(context.local.simulate_scenario),
            children: SimulateScenarioResult.values
                .map(
                  (e) => SimpleDialogOption(
                    child: Text(e.name),
                    onPressed: () => Navigator.pop(context, e),
                  ),
                )
                .toList(),
          );
        },
      );
}

enum SimulateScenarioResult {
  signalReconnect,
  fullReconnect,
  speakerUpdate,
  nodeFailure,
  migration,
  serverLeave,
  switchCandidate,
  e2eeKeyRatchet,
  participantName,
  participantMetadata,
  clear,
}
