import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/local_video_track_extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/microphone_toggle_debouncer.dart';
import 'package:meet/helper/video_track_publisher.dart';
import 'package:meet/managers/channels/platform_info_channel.dart';
import 'package:meet/permissions/permission_service.dart';
import 'package:meet/rust/proton_meet/user_config.dart';
import 'package:meet/rust/proton_meet/user_config_extensions.dart';
import 'package:meet/views/scenes/room/controls_bar/controls_icon_button.dart';
import 'package:meet/views/scenes/room/controls_bar/controls_video_action.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:permission_handler/permission_handler.dart';

import 'controls_action.dart';
import 'controls_audio_action.dart';
import 'overflow_menu_bottom_sheet.dart';

class ResponsiveControlsBar extends StatefulWidget {
  const ResponsiveControlsBar({
    required this.optionalActionsBuilder,
    required this.room,
    required this.onLeave,
    super.key,
    this.backgroundColor,
    this.buttonWidth = 56,
    this.buttonGap = 6,
    this.endWidth = 90,
    this.cameraResolution,
    this.cameraMaxBitrate,
    this.currentCameraPosition,
  });

  final Room room;
  final VoidCallback onLeave;
  final List<ControlAction> Function() optionalActionsBuilder;
  final Color? backgroundColor;
  final double buttonWidth;
  final double buttonGap;
  final double endWidth;
  final VideoResolution? cameraResolution;
  final VideoMaxBitrate? cameraMaxBitrate;
  final CameraPosition? currentCameraPosition;

  @override
  State<ResponsiveControlsBar> createState() => _ResponsiveControlsBarState();
}

class _ResponsiveControlsBarState extends State<ResponsiveControlsBar> {
  List<MediaDevice> _audioInputs = [];
  List<MediaDevice> _audioOutputs = [];
  List<MediaDevice> _videoInputs = [];

  StreamSubscription? _subscription;

  bool _isCameraPermissionGranted = false;
  bool _isMicrophonePermissionGranted = false;
  bool _isIOSAppOnMacOS = false;

  // Debouncer for microphone enable/disable operations
  final _microphoneToggleDebouncer = MicrophoneToggleDebouncer();

  LocalParticipant? get participant => widget.room.localParticipant;

  bool get isMuted => participant?.isMuted ?? false;

  @override
  void initState() {
    super.initState();
    participant?.addListener(_onChange);
    _subscription = Hardware.instance.onDeviceChange.stream.listen(
      _loadDevices,
    );
    _loadIOSOnMacOSFlag();
    _reloadPermissions();
    _reloadDevices();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    participant?.removeListener(_onChange);
    // Clear pending microphone operations
    _microphoneToggleDebouncer.clear();
    super.dispose();
  }

  Future<void> _onChange() async {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadIOSOnMacOSFlag() async {
    final value = await PlatformInfoChannel.isIOSAppOnMacOS();
    if (mounted) {
      setState(() {
        _isIOSAppOnMacOS = value;
      });
    }
  }

  Future<void> _reloadPermissions() async {
    final permissionService = PermissionService();
    final cameraStatus = await permissionService.cameraStatus();
    final microphoneStatus = await permissionService.microphoneStatus();
    bool isCameraPermissionGranted = false;
    bool isMicrophonePermissionGranted = false;
    // if camera permission is denied, request it
    if (cameraStatus.isGranted) {
      isCameraPermissionGranted = true;
    } else if (cameraStatus.isDenied) {
      isCameraPermissionGranted = await permissionService
          .requestCameraPermission();
    }
    // if microphone permission is denied, request it
    if (microphoneStatus.isGranted) {
      isMicrophonePermissionGranted = true;
    } else if (microphoneStatus.isDenied) {
      isMicrophonePermissionGranted = await permissionService
          .requestMicrophonePermission();
    }

    if (mounted) {
      setState(() {
        _isCameraPermissionGranted = isCameraPermissionGranted;
        _isMicrophonePermissionGranted = isMicrophonePermissionGranted;
      });
    }
  }

  void _reloadDevices() {
    Hardware.instance.enumerateDevices().then(_loadDevices);
  }

  Future<void> _loadDevices(List<MediaDevice> devices) async {
    _audioInputs = devices.where((d) => d.kind == 'audioinput').toList();
    _audioOutputs = devices.where((d) => d.kind == 'audiooutput').toList();
    _videoInputs = devices.where((d) => d.kind == 'videoinput').toList();

    l.logger.d('devices: $devices');
    l.logger.d('selectedVideoInput: ${Hardware.instance.selectedAudioInput}');
    l.logger.d('selectedAudioInput: ${Hardware.instance.selectedAudioOutput}');

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _disableAudio() async {
    final participant = this.participant;
    if (participant == null) return;
    // Use debouncer to prevent rapid toggles
    await _microphoneToggleDebouncer.disable(participant);
    _onChange();
  }

  Future<void> _enableAudio() async {
    final participant = this.participant;
    if (participant == null) return;
    // Use debouncer to prevent rapid toggles
    await _microphoneToggleDebouncer.enable(participant);
    _onChange();
  }

  Future<void> _disableVideo() async {
    await participant?.setCameraEnabled(false);
    // await _stopVideoTrack();
    _onChange();
  }

  Future<void> _enableVideo() async {
    await _startVideoTrack();
    await participant?.setCameraEnabled(true);
    _onChange();
  }

  Future<void> _startVideoTrack() async {
    final p = participant;
    if (p == null) return;

    // Schedule heavy operations asynchronously to avoid blocking UI
    final tracks = p.trackPublications.values.toList();
    bool hasVideoTrack = false;
    for (LocalTrackPublication track in tracks) {
      if (track.track is LocalVideoTrack) {
        if (!track.isScreenShare) {
          hasVideoTrack = true;
        }
      }
    }
    if (!hasVideoTrack) {
      /// no active video track, create a new one

      /// create camera track with current room camera capture options
      final resolution = widget.cameraResolution ?? defaultCameraResolution;
      final maxBitrate = widget.cameraMaxBitrate ?? defaultCameraMaxBitrate;
      LocalVideoTrack? cameraTrack;
      try {
        cameraTrack = await LocalVideoTrackHelper.cameraTrack(
          parameters: VideoParameters(dimensions: resolution.videoDimensions),
          position: widget.currentCameraPosition,
        );
      } catch (e) {
        l.logger.e('[ControlsBar] Failed to create camera track: $e');
        return;
      }

      /// publish camera track with given maxBitrate, use preferred codec (vp9 by default) first and fallback to vp8 if failed
      final preferredCodec =
          widget.room.roomOptions.defaultVideoPublishOptions.videoCodec;
      try {
        cameraTrack = await publishVideoTrackWithFallback(
          participant: participant!,
          initialTrack: cameraTrack,
          createTrack: () => LocalVideoTrackHelper.cameraTrack(
            parameters: VideoParameters(dimensions: resolution.videoDimensions),
            position: widget.currentCameraPosition,
          ),
          publishOptions: VideoPublishOptions(
            videoCodec: preferredCodec,
            videoEncoding: maxBitrate.videoEncoding,
            screenShareEncoding: maxBitrate.videoEncoding,
          ),
        );
      } catch (e) {
        l.logger.e(
          '[ControlsBar] Failed to publish video track: $e. Stopping camera track.',
        );
        // Clean up camera track if publish fails
        try {
          await cameraTrack?.stop();
        } catch (stopError) {
          l.logger.e('[ControlsBar] Error stopping camera track: $stopError');
        }
        rethrow;
      }
    }
  }

  Future<void> _setVideoInputDevice(
    MediaDevice? device,
    BuildContext? context,
  ) async {
    if (device == null || participant == null) return;

    final track =
        widget.room.localParticipant?.videoTrackPublications.firstOrNull?.track;

    final currentDeviceId =
        widget.room.engine.roomOptions.defaultCameraCaptureOptions.deviceId;

    // Always update roomOptions so future tracks use the correct device
    widget.room.engine.roomOptions = widget.room.engine.roomOptions.copyWith(
      defaultCameraCaptureOptions: widget
          .room
          .engine
          .roomOptions
          .defaultCameraCaptureOptions
          .copyWith(deviceId: device.deviceId),
    );

    try {
      if (track != null) {
        await track.switchCamera(device.deviceId);
        Hardware.instance.selectedVideoInput = device;
      }
      // Update state through RoomBloc if available
      if (context != null && context.mounted) {
        try {
          final bloc = context.read<RoomBloc>();
          bloc.add(SetVideoInputDevice(device: device));
        } catch (e) {
          l.logger.d(
            '[ControlsBar] Could not update video device in state: $e',
          );
        }
      }
    } catch (e) {
      // if the switching actually fails, reset it to the previous deviceId
      widget.room.engine.roomOptions = widget.room.engine.roomOptions.copyWith(
        defaultCameraCaptureOptions: widget
            .room
            .engine
            .roomOptions
            .defaultCameraCaptureOptions
            .copyWith(deviceId: currentDeviceId),
      );
    }
    _onChange();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor ?? Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Build & filter optionals
            final allOptionals = widget
                .optionalActionsBuilder()
                .where((a) => a.visiblePredicate?.call() ?? true)
                .toList();

            // ---- width packing: always show [Mic][Video][...visible optionals...][More?][End] ----
            final maxW = constraints.maxWidth;
            final moreW = widget.buttonWidth;
            // Start with required: mic + video
            double used = 0;
            // place mic
            used += widget.buttonWidth; //110;
            // gap + video
            used += widget.buttonGap + widget.buttonWidth;

            // Try to fit as many optionals as possible (optimistically assume no "More")
            final visible = <ControlAction>[];
            for (final a in allOptionals) {
              // If we add this optional, can we still fit the END button?
              final need =
                  widget.buttonGap +
                  widget
                      .buttonWidth // this optional
                      +
                  widget.buttonGap +
                  widget.endWidth; // gap + END
              if (used + need <= maxW) {
                used += widget.buttonGap + widget.buttonWidth;
                visible.add(a);
              } else {
                break; // stop adding more, we have overflow
              }
            }

            final hasOverflow = visible.length < allOptionals.length;
            // If overflow, we need to reserve a "More" button.
            if (hasOverflow) {
              // Ensure [gap + More + gap + End] fits; if not, remove some visible optionals.
              while (visible.isNotEmpty &&
                  used +
                          widget.buttonGap +
                          moreW +
                          widget.buttonGap +
                          widget.endWidth >
                      maxW) {
                // remove last visible optional
                used -= (widget.buttonGap + widget.buttonWidth);
                visible.removeLast();
              }
            }

            // Finally check (no overflow case): we must ensure END fits even if we filled all optionals
            while (!hasOverflow &&
                used + widget.buttonGap + widget.endWidth > maxW &&
                visible.isNotEmpty) {
              used -= (widget.buttonGap + widget.buttonWidth);
              visible.removeLast();
            }

            final overflow = hasOverflow
                ? allOptionals.sublist(visible.length)
                : const <ControlAction>[];

            Widget buildIcon(ControlAction a) => ControlIconButton(
              icon: a.icon,
              activeIcon: a.activeIcon,
              tooltip: a.tooltip,
              onPressed: a.onPressed,
              isActive: a.isActive,
              backgroundColor: a.backgroundColor,
              inactiveBackgroundColor: a.inactiveBackgroundColor,
              badge: a.badge,
              key: a.key,
            );

            Widget buildMoreMenu() {
              // No hidden actions → no "More" button at all.
              if (overflow.isEmpty) return const SizedBox.shrink();

              return ControlIconButton(
                icon: context.images.iconMore.svg24(),
                tooltip: context.local.more,
                onPressed: () {
                  OverflowMenuBottomSheet.show(context, overflow);
                },
              );
            }

            return Center(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    /// Mic (always)
                    _buildAudioAction(context),
                    SizedBox(width: widget.buttonGap),

                    /// Video (always)
                    _buildVideoAction(context),
                    SizedBox(width: widget.buttonGap),

                    // Visible optionals
                    for (final a in visible) ...[
                      buildIcon(a),
                      SizedBox(width: widget.buttonGap),
                    ],

                    // More (only if overflow)
                    if (overflow.isNotEmpty) ...[
                      buildMoreMenu(),
                      SizedBox(width: widget.buttonGap),
                    ],

                    /// leave button
                    _buildLeaveButton(context),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildVideoAction(BuildContext context) {
    // Create a wrapper function that captures context
    Future<void> setVideoDeviceWrapper(MediaDevice? device) async {
      await _setVideoInputDevice(device, context);
    }

    return VideoControlButton(
      room: widget.room,
      autoSelectDevcie: mobile && !_isIOSAppOnMacOS,
      isCameraEnabled: participant?.isCameraEnabled() ?? false,
      isCameraPermissionGranted: _isCameraPermissionGranted,
      reloadPermissions: () async => _reloadPermissions(),
      reloadDevices: () async => _reloadDevices(),
      enableVideo: () async => _enableVideo(),
      disableVideo: () async => _disableVideo(),
      setVideoInputDevice: setVideoDeviceWrapper,
      videoInputs: _videoInputs,
      selectedVideoInputId: widget.room.selectedVideoInputDeviceId,
      isMicrophonePermissionGranted: _isMicrophonePermissionGranted,
    );
  }

  Widget _buildAudioAction(BuildContext context) {
    return AudioControlButton(
      context: context,
      room: widget.room,
      autoSelectDevice: mobile && !_isIOSAppOnMacOS,
      isMuted: isMuted,
      isMicrophonePermissionGranted: _isMicrophonePermissionGranted,
      isCameraPermissionGranted: _isCameraPermissionGranted,
      reloadPermissions: () async => _reloadPermissions(),
      reloadDevices: () async => _reloadDevices(),
      enableAudio: () async => _enableAudio(),
      disableAudio: () async => _disableAudio(),
      audioInputs: _audioInputs,
      audioOutputs: _audioOutputs,
      selectedAudioInputId: widget.room.selectedAudioInputDeviceId,
      selectedAudioOutputId: widget.room.selectedAudioOutputDeviceId,
    );
  }

  Widget _buildLeaveButton(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        fixedSize: Size(widget.endWidth, 56),
        backgroundColor: context.colors.deviceSelectorDisabledBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(40),
          side: BorderSide(
            color: context.colors.deviceSelectorDisabledBackground,
          ),
        ),
        elevation: 0.0,
      ),
      onPressed: widget.onLeave,
      child: mobile
          ? context.images.iconEndCall.svg30(color: context.colors.white)
          : Text(
              context.local.leave,
              style: ProtonStyles.body2Medium(color: context.colors.white),
            ),
    );
  }
}
