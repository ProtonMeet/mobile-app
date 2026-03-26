import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/views/components/alerts/media_permission_dialog.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:meet/views/scenes/widgets/audio.devices.selector.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioControlButton extends StatelessWidget {
  final bool isMuted;
  final bool isMicrophonePermissionGranted;
  final bool isCameraPermissionGranted;
  final bool autoSelectDevice;
  final Future<void> Function() reloadPermissions;
  final Future<void> Function() reloadDevices;
  final Future<void> Function() enableAudio;
  final Future<void> Function() disableAudio;
  final List<MediaDevice> audioInputs;
  final List<MediaDevice> audioOutputs;
  final String? selectedAudioInputId;
  final String? selectedAudioOutputId;
  final Room room; // to set device
  final BuildContext context;

  const AudioControlButton({
    required this.context,
    required this.room,
    required this.isMuted,
    required this.isMicrophonePermissionGranted,
    required this.isCameraPermissionGranted,
    required this.reloadPermissions,
    required this.reloadDevices,
    required this.enableAudio,
    required this.disableAudio,
    required this.audioInputs,
    required this.audioOutputs,
    required this.selectedAudioInputId,
    required this.selectedAudioOutputId,
    this.autoSelectDevice = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!isMicrophonePermissionGranted) {
      return GestureDetector(
        onTap: () async {
          LocalToast.showToast(
            context,
            "Please grant microphone permission to continue",
          );

          // reload permission in case user manually enabled in settings
          await reloadPermissions();
          if (!isMicrophonePermissionGranted) {
            await PermissionService().requestMicrophonePermission();
            await reloadPermissions();
            if (isMicrophonePermissionGranted) {
              await reloadDevices();
              await enableAudio();
            } else {
              await disableAudio();
            }
          }
        },
        child: AudioDevicesSelector(
          autoSelectDevice: autoSelectDevice,
          enabled: !isMuted,
          showContent: false,
          micDevices: audioInputs,
          speakerDevices: audioOutputs,
          selectedMic: audioInputs.firstWhereOrNull(
            (d) => d.deviceId == selectedAudioInputId,
          ),
          selectedSpeaker: audioOutputs.firstWhereOrNull(
            (d) => d.deviceId == selectedAudioOutputId,
          ),
          onMicChanged: (device) => room.setAudioInputDevice(device!),
          onSpeakerChanged: (device) => room.setAudioOutputDevice(device!),
          permissionGranted: isMicrophonePermissionGranted,
          onAudioEnabled: (bool value) async {
            final microphoneStatus = await PermissionService()
                .microphoneStatus();
            if (microphoneStatus.isPermanentlyDenied) {
              if (context.mounted) {
                showMediaPermissionSettingsDialog(
                  context,
                  cameraDenied: !isCameraPermissionGranted,
                  microphoneDenied: !isMicrophonePermissionGranted,
                  onReturned: reloadPermissions,
                );
              }
            } else {
              final bool granted = microphoneStatus.isGranted
                  ? true
                  : await PermissionService().requestMicrophonePermission();

              if (value && granted) {
                await reloadDevices();
                await enableAudio();
              } else {
                await disableAudio();
              }
            }
          },
        ),
      );
    }

    // ✅ Normal case with granted permissions
    return AudioDevicesSelector(
      autoSelectDevice: autoSelectDevice,
      enabled: !isMuted,
      showContent: false,
      micDevices: audioInputs,
      speakerDevices: audioOutputs,
      selectedMic: audioInputs.firstWhereOrNull(
        (d) => d.deviceId == selectedAudioInputId,
      ),
      selectedSpeaker: audioOutputs.firstWhereOrNull(
        (d) => d.deviceId == selectedAudioOutputId,
      ),
      onMicChanged: (device) async {
        if (device != null) {
          final bloc = context.read<RoomBloc>();
          await room.setAudioInputDevice(device);
          // Update state through RoomBloc if available
          bloc.add(SetAudioInputDevice(device: device));
        }
      },
      onSpeakerChanged: (device) async {
        if (device != null) {
          final bloc = context.read<RoomBloc>();
          await room.setAudioOutputDevice(device);
          // Update state through RoomBloc if available
          bloc.add(SetAudioOutputDevice(device: device));
        }
      },
      permissionGranted: isMicrophonePermissionGranted,
      onAudioEnabled: (bool value) async {
        if (value) {
          await enableAudio();
        } else {
          await disableAudio();
        }
      },
    );
  }
}
