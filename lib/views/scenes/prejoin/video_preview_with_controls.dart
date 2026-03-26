import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/views/components/safe_video_track_renderer.dart';
import 'package:meet/views/scenes/prejoin/prejoin_bloc.dart';
import 'package:meet/views/scenes/prejoin/prejoin_speaker_phone_panel.dart';
import 'package:meet/views/scenes/prejoin/prejoin_state.dart';
import 'package:meet/views/scenes/utils.dart';
import 'package:meet/views/scenes/widgets/audio.devices.selector.dart';
import 'package:meet/views/scenes/widgets/sound_waveform.dart';
import 'package:meet/views/scenes/widgets/video.devices.selector.dart';

class VideoPreviewWithControls extends StatelessWidget {
  final bool isVideoEnabled;
  final bool isAudioEnabled;
  final bool showSelectVideoButtons;
  final bool showSelectAudioButtons;
  final bool isCameraPermissionGranted;
  final bool isMicrophonePermissionGranted;
  final VideoTrack? videoTrack;
  final AudioTrack? audioTrack;
  final VoidCallback onVideoToggle;
  final VoidCallback onAudioToggle;
  final double width;
  final double height;
  final List<MediaDevice> videoDevices;
  final List<MediaDevice> speakerDevices;
  final List<MediaDevice> audioDevices;
  final MediaDevice? selectedVideoDevice;
  final MediaDevice? selectedAudioDevice;
  final MediaDevice? selectedSpeakerDevice;
  final ValueChanged<MediaDevice?> onVideoDeviceChanged;
  final VoidCallback onSwapVideo;
  final ValueChanged<MediaDevice?> onAudioDeviceChanged;
  final ValueChanged<MediaDevice?> onSpeakerDeviceChanged;
  final VoidCallback onCameraPermissionRequest;
  final VoidCallback onMicrophonePermissionRequest;
  final bool showWaveform;
  final String? displayName;

  const VideoPreviewWithControls({
    required this.isVideoEnabled,
    required this.isAudioEnabled,
    required this.isCameraPermissionGranted,
    required this.isMicrophonePermissionGranted,
    required this.videoTrack,
    required this.audioTrack,
    required this.onVideoToggle,
    required this.onAudioToggle,
    required this.onVideoDeviceChanged,
    required this.onSwapVideo,
    required this.onAudioDeviceChanged,
    required this.onSpeakerDeviceChanged,
    required this.onCameraPermissionRequest,
    required this.onMicrophonePermissionRequest,
    this.showSelectVideoButtons = false,
    this.showSelectAudioButtons = false,
    super.key,
    this.width = 600,
    this.height = 240,
    this.videoDevices = const [],
    this.speakerDevices = const [],
    this.audioDevices = const [],
    this.selectedVideoDevice,
    this.selectedAudioDevice,
    this.selectedSpeakerDevice,
    this.showWaveform = false,
    this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final controlHeight = 86.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : width;

        return Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      width: availableWidth,
                      decoration: ShapeDecoration(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(32),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: Stack(
                          children: [
                            // Background layer
                            ColoredBox(
                              color: context.colors.interActionPurpleMinor3,
                              child: isVideoEnabled && videoTrack != null
                                  ? SafeVideoTrackRenderer(
                                      mirrorMode: VideoViewMirrorMode.off,
                                      videoTrack: videoTrack!,
                                    )
                                  : Center(
                                      child: Container(
                                        width: 72,
                                        height: 72,
                                        decoration: ShapeDecoration(
                                          color: context
                                              .colors
                                              .interActionPurpleMinor1,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              200,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              getInitials(displayName),
                                              textAlign: TextAlign.center,
                                              style: ProtonStyles.body2Medium(
                                                fontSize: 18.0,
                                                color:
                                                    context.colors.textInverted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ),
                            // Gradient overlay on top
                            Positioned.fill(
                              child: Container(
                                decoration: ShapeDecoration(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(32),
                                  ),
                                  gradient: LinearGradient(
                                    begin: const Alignment(0.50, 0.1),
                                    end: const Alignment(0.50, 1.00),
                                    stops: const [0.0, 0.5, 1.0],
                                    colors: [
                                      Colors.black.withValues(alpha: 0),
                                      Colors.black.withValues(alpha: 0.2),
                                      Colors.black.withValues(alpha: 0.4),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (showWaveform && audioTrack != null && isAudioEnabled)
                    Positioned(
                      right: 16,
                      top: 16,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: context.colors.backgroundNorm,
                        child: SoundWaveformWidget(
                          key: ValueKey(audioTrack!.hashCode),
                          audioTrack: audioTrack!,
                          minHeight: 3,
                          maxHeight: 10,
                          width: 1,
                          barCount: 3,
                        ),
                      ),
                    ),
                  BlocSelector<PreJoinBloc, PreJoinState, bool>(
                    selector: (state) => state.isMeetMobileSpeakerToggleEnabled,
                    builder: (context, isEnabled) {
                      if (!isEnabled) {
                        return Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: const SizedBox.shrink(),
                        );
                      }
                      return Positioned(
                        right: 24,
                        top: 24,
                        child: _buildSpeakerPhoneButton(context),
                      );
                    },
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        /// Audio toggle
                        _buildAudioButton(context),
                        const SizedBox(width: 12),

                        /// Video toggle
                        _buildVideoButton(context),

                        if (isVideoEnabled && mobile) ...[
                          const SizedBox(width: 12),
                          // swape video button
                          _buildSwapVideoButton(context),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showSelectVideoButtons || showSelectAudioButtons)
              SizedBox(
                height: controlHeight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (showSelectVideoButtons) ...[
                            _buildVideoSelection(
                              context,
                              constraints.maxWidth / 2 - 55,
                            ),
                            const SizedBox(width: 10),
                          ],
                          if (showSelectAudioButtons)
                            _buildAudioSelection(
                              context,
                              constraints.maxWidth / 2 - 55,
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildVideoButton(BuildContext context) {
    final bg = isVideoEnabled
        ? context.colors.controlBarBtnBackground
        : context.colors.deviceSelectorDisabledBackground;

    return _ControlButton(
      onTap: (!isCameraPermissionGranted && !isVideoEnabled)
          ? onCameraPermissionRequest
          : onVideoToggle,
      bgColor: bg,
      icon: isVideoEnabled
          ? context.images.iconVideoOn.svg(width: 24, height: 24)
          : context.images.iconVideoOff.svg(width: 24, height: 24),
      iconColor: context.colors.textNorm,
      showWarning: !isCameraPermissionGranted,
    );
  }

  Widget _buildAudioButton(BuildContext context) {
    final bg = isAudioEnabled
        ? context.colors.controlBarBtnBackground
        : context.colors.deviceSelectorDisabledBackground;

    return _ControlButton(
      onTap: (!isMicrophonePermissionGranted && !isAudioEnabled)
          ? onMicrophonePermissionRequest
          : onAudioToggle,
      bgColor: bg,
      icon: isAudioEnabled
          ? context.images.iconAudioOn.svg(
              width: 20,
              height: 20,
              fit: BoxFit.fill,
            )
          : context.images.iconAudioOff.svg(
              width: 20,
              height: 20,
              fit: BoxFit.fill,
            ),
      iconColor: context.colors.textNorm,
      showWarning: !isMicrophonePermissionGranted,
    );
  }

  Widget _buildSwapVideoButton(BuildContext context) {
    final buttonSize = 48.0;
    return GestureDetector(
      onTap: onSwapVideo,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: buttonSize,
          height: buttonSize,
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: context.colors.controlBarBtnBackground,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                width: 0.86,
                color: context.colors.controlBarBtnBackground,
              ),
              borderRadius: BorderRadius.circular(100),
            ),
          ),
          child: context.images.iconSwapCamera.svg(
            width: 20,
            height: 20,
            fit: BoxFit.fill,
            colorFilter: ColorFilter.mode(
              context.colors.textNorm,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeakerPhoneButton(BuildContext context) {
    final buttonSize = 48.0;
    return GestureDetector(
      onTap: () {
        final preJoinBloc = context.read<PreJoinBloc>();
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
          ),
          builder: (BuildContext context) {
            return BlocProvider<PreJoinBloc>.value(
              value: preJoinBloc,
              child: SafeArea(
                child: IntrinsicHeight(child: const PreJoinSpeakerPhonePanel()),
              ),
            );
          },
        );
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: buttonSize,
          height: buttonSize,
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: context.colors.controlBarBtnBackground,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                width: 0.86,
                color: context.colors.controlBarBtnBackground,
              ),
              borderRadius: BorderRadius.circular(100),
            ),
          ),
          child: context.images.iconSpeakerPhone.svg(
            width: 20,
            height: 20,
            fit: BoxFit.fill,
            colorFilter: ColorFilter.mode(
              context.colors.textNorm,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSelection(BuildContext context, double width) {
    if (!isCameraPermissionGranted) {
      return GestureDetector(
        onTap: onCameraPermissionRequest,
        child: VideoDevicesSelector(
          enabled: true,
          showContent: true,
          videoDevices: videoDevices,
          selectedVideo: selectedVideoDevice,
          onVideoChanged: onVideoDeviceChanged,
          permissionGranted: isCameraPermissionGranted,
          backgroundColor: context.colors.backgroundNorm,
          width: width,
        ),
      );
    }
    return VideoDevicesSelector(
      enabled: true,
      showContent: true,
      videoDevices: videoDevices,
      selectedVideo: selectedVideoDevice,
      onVideoChanged: onVideoDeviceChanged,
      permissionGranted: isCameraPermissionGranted,
      backgroundColor: context.colors.backgroundNorm,
      width: width,
    );
  }

  Widget _buildAudioSelection(BuildContext context, double width) {
    if (!isMicrophonePermissionGranted) {
      return GestureDetector(
        onTap: onMicrophonePermissionRequest,
        child: AudioDevicesSelector(
          enabled: true,
          showContent: true,
          micDevices: audioDevices,
          speakerDevices: speakerDevices,
          selectedMic: selectedAudioDevice,
          selectedSpeaker: selectedSpeakerDevice,
          onMicChanged: onAudioDeviceChanged,
          onSpeakerChanged: onSpeakerDeviceChanged,
          permissionGranted: isMicrophonePermissionGranted,
          backgroundColor: context.colors.backgroundNorm,
          width: width,
        ),
      );
    }

    return AudioDevicesSelector(
      enabled: true,
      showContent: true,
      micDevices: audioDevices,
      speakerDevices: speakerDevices,
      selectedMic: selectedAudioDevice,
      selectedSpeaker: selectedSpeakerDevice,
      onMicChanged: onAudioDeviceChanged,
      onSpeakerChanged: onSpeakerDeviceChanged,
      permissionGranted: isMicrophonePermissionGranted,
      backgroundColor: context.colors.backgroundNorm,
      width: width,
    );
  }
}

// 1) Reusable round control with optional warning badge
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.onTap,
    required this.bgColor,
    required this.icon,
    required this.iconColor,
    this.showWarning = false,
  });

  final VoidCallback onTap;
  final Color bgColor;
  final Widget icon;
  final Color iconColor;
  final bool showWarning;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // round button
            Container(
              width: 48,
              height: 48,
              padding: const EdgeInsets.all(14),
              decoration: ShapeDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    width: 0.86,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: FittedBox(child: icon),
                ),
              ),
            ),

            // small warning badge (top-right)
            if (showWarning)
              Positioned(
                right: -2, // slightly outside for a clean overlap
                top: -2,
                child: Semantics(
                  label: context.local.permission_required,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: Colors.amber, // warning fill
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        width: 2, // ring to separate from button
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.priority_high_rounded,
                        size: 12,
                        color: Colors.black, // good contrast
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
