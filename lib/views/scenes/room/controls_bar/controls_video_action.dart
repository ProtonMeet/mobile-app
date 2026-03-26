import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/views/components/alerts/media_permission_dialog.dart';
import 'package:meet/views/scenes/widgets/video.devices.selector.dart';
import 'package:permission_handler/permission_handler.dart';

class VideoControlButton extends StatelessWidget {
  final bool autoSelectDevcie;
  final bool isCameraEnabled;
  final bool isCameraPermissionGranted;
  final Future<void> Function() reloadPermissions;
  final Future<void> Function() reloadDevices;
  final Future<void> Function() enableVideo;
  final Future<void> Function() disableVideo;
  final Future<void> Function(MediaDevice?) setVideoInputDevice;
  final List<MediaDevice> videoInputs;
  final String? selectedVideoInputId;
  final Room room; // to set device
  final bool isMicrophonePermissionGranted;

  const VideoControlButton({
    required this.room,
    required this.autoSelectDevcie,
    required this.isCameraEnabled,
    required this.isCameraPermissionGranted,
    required this.reloadPermissions,
    required this.reloadDevices,
    required this.enableVideo,
    required this.disableVideo,
    required this.setVideoInputDevice,
    required this.videoInputs,
    required this.isMicrophonePermissionGranted,
    this.selectedVideoInputId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!isCameraPermissionGranted) {
      return GestureDetector(
        onTap: () async {
          LocalToast.showToast(
            context,
            context.local.please_grant_camera_permission,
          );

          // reload permission in case user manually enabled in settings
          await reloadPermissions();
          if (!isCameraPermissionGranted) {
            await PermissionService().requestCameraPermission();
            await reloadPermissions();
            if (isCameraPermissionGranted) {
              await reloadDevices();
              await enableVideo();
            } else {
              await disableVideo();
            }
          }
        },
        child: VideoDevicesSelector(
          autoSelectDevcie: autoSelectDevcie,
          enabled: isCameraEnabled,
          showContent: false,
          videoDevices: videoInputs,
          selectedVideo: videoInputs.firstWhereOrNull(
            (d) => d.deviceId == selectedVideoInputId,
          ),
          onVideoChanged: (device) async {
            await setVideoInputDevice(device);
          },
          permissionGranted: isCameraPermissionGranted,
          onVideoEnabled: (bool value) async {
            final cameraStatus = await PermissionService().cameraStatus();
            if (cameraStatus.isPermanentlyDenied) {
              if (context.mounted) {
                showMediaPermissionSettingsDialog(
                  context,
                  cameraDenied: !isCameraPermissionGranted,
                  microphoneDenied: !isMicrophonePermissionGranted,
                  onReturned: reloadPermissions,
                );
              }
            } else {
              final bool granted = cameraStatus.isGranted
                  ? true
                  : await PermissionService().requestCameraPermission();

              if (value && granted) {
                await reloadDevices();
                await enableVideo();
              } else {
                await disableVideo();
              }
            }
          },
        ),
      );
    }

    // ✅ Normal case with granted permissions
    return VideoDevicesSelector(
      autoSelectDevcie: autoSelectDevcie,
      enabled: isCameraEnabled,
      showContent: false,
      videoDevices: videoInputs,
      selectedVideo: videoInputs.firstWhereOrNull(
        (d) => d.deviceId == selectedVideoInputId,
      ),
      onVideoChanged: (device) async {
        await setVideoInputDevice(device!);
      },
      permissionGranted: true,
      onVideoEnabled: (bool value) async {
        if (value) {
          await enableVideo();
        } else {
          await disableVideo();
        }
      },
    );
  }
}
