import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/background_blur/camera_background_selection.dart';
import 'package:meet/helper/background_blur/virtual_background_presets.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/scenes/room/recording/recording_save_location.dart';
import 'package:meet/views/scenes/room/recording/recording_save_location_setting.dart';
import 'package:meet/views/scenes/room/recording/saved_recordings_sheet.dart';
import 'package:meet/views/scenes/room/side_panel_widget.dart';
import 'package:proton_denoise/proton_denoise.dart';

class MeetingSettingsV2 extends StatefulWidget {
  final void Function({required bool value})? onHideSelfViewChanged;
  final void Function({required bool value})?
  onUnsubscribeVideoByDefaultChanged;
  final void Function({required bool value})? onPictureInPictureModeChanged;
  final Future<bool> Function({required bool value})? onLockMeetingChanged;
  final Future<bool> Function({required bool value})? onWaitingRoomChanged;
  final VoidCallback? onReconnectPressed;
  final void Function({required bool value})?
  onForceShowConnectionStatusBannerChanged;
  final bool hideSelfView;
  final bool unsubscribeVideoByDefault;
  final bool pictureInPictureMode;
  final bool lockMeeting;
  final bool waitingRoomEnabled;

  /// When false, the waiting-room switch is hidden (gated by the MeetWaitingRoom flag).
  final bool showWaitingRoom;
  final bool isHost;
  final bool isRejoining;
  final bool forceShowConnectionStatusBanner;
  final bool showConnectionSettings;
  final bool showCameraBackgroundBlur;
  final CameraBackgroundSelection cameraBackgroundSelection;
  final VoidCallback? onCameraBackgroundTap;
  final bool showAudioDenoise;
  final bool audioDenoiseEnabled;
  final void Function({required bool value})? onAudioDenoiseChanged;
  final List<DenoiseTypeUiOption> audioDenoiseTypeOptions;
  final DenoiseType? selectedAudioDenoiseType;
  final void Function(DenoiseType type)? onAudioDenoiseTypeSelected;
  final bool showRecordingSaveLocation;

  const MeetingSettingsV2({
    required this.hideSelfView,
    required this.unsubscribeVideoByDefault,
    required this.onUnsubscribeVideoByDefaultChanged,
    required this.pictureInPictureMode,
    required this.lockMeeting,
    required this.waitingRoomEnabled,
    required this.isHost,
    this.showWaitingRoom = false,
    this.onHideSelfViewChanged,
    this.onPictureInPictureModeChanged,
    this.onLockMeetingChanged,
    this.onWaitingRoomChanged,
    this.onReconnectPressed,
    this.onForceShowConnectionStatusBannerChanged,
    this.isRejoining = false,
    this.forceShowConnectionStatusBanner = false,
    this.showConnectionSettings = false,
    this.showCameraBackgroundBlur = false,
    this.cameraBackgroundSelection = const CameraBackgroundSelection.none(),
    this.onCameraBackgroundTap,
    this.showAudioDenoise = false,
    this.audioDenoiseEnabled = false,
    this.onAudioDenoiseChanged,
    this.audioDenoiseTypeOptions = const [],
    this.selectedAudioDenoiseType,
    this.onAudioDenoiseTypeSelected,
    this.showRecordingSaveLocation = false,
    super.key,
  });

  @override
  State<MeetingSettingsV2> createState() => _MeetingSettingsV2State();
}

/// Denoise algorithm row shown when multiple backends are enabled via Unleash.
class DenoiseTypeUiOption {
  const DenoiseTypeUiOption({required this.type});

  final DenoiseType type;

  String get id => type.id;
  String get label => type.displayName;
}

class _MeetingSettingsV2State extends State<MeetingSettingsV2> {
  final ScrollController _scrollController = ScrollController();

  // Meeting options
  bool hideSelfView = false;
  bool unsubscribeVideoByDefault = false;
  bool pictureInPictureMode = false;
  bool lockMeeting = false;
  bool waitingRoomEnabled = false;
  bool forceShowConnectionStatusBanner = false;
  bool audioDenoiseEnabled = false;

  // Loading states
  bool _isLockMeetingLoading = false;
  bool _isWaitingRoomLoading = false;

  @override
  void initState() {
    super.initState();

    hideSelfView = widget.hideSelfView;
    unsubscribeVideoByDefault = widget.unsubscribeVideoByDefault;
    pictureInPictureMode = widget.pictureInPictureMode;
    lockMeeting = widget.lockMeeting;
    waitingRoomEnabled = widget.waitingRoomEnabled;
    forceShowConnectionStatusBanner = widget.forceShowConnectionStatusBanner;
    audioDenoiseEnabled = widget.audioDenoiseEnabled;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MeetingSettingsV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.audioDenoiseEnabled != oldWidget.audioDenoiseEnabled) {
      audioDenoiseEnabled = widget.audioDenoiseEnabled;
    }
    if (widget.waitingRoomEnabled != oldWidget.waitingRoomEnabled) {
      waitingRoomEnabled = widget.waitingRoomEnabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoomSidePanelScroll(
      scrollController: _scrollController,
      header: Text(
        context.local.meeting_settings,
        style: ProtonStyles.headline(
          fontSize: 18,
          color: context.colors.textNorm,
        ),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildSettings(context),
              const SizedBox(height: 24),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildSettings(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Host Section
        if (widget.isHost) ...[
          _buildSection(
            context,
            title: context.local.security,
            children: [
              _SettingSwitch(
                title: context.local.lock_meeting,
                value: lockMeeting,
                isLoading: _isLockMeetingLoading,
                onChanged:
                    widget.onLockMeetingChanged != null &&
                        !_isLockMeetingLoading
                    ? (value) async {
                        setState(() {
                          _isLockMeetingLoading = true;
                        });
                        final success = await widget.onLockMeetingChanged?.call(
                          value: value,
                        );
                        if (mounted) {
                          setState(() {
                            _isLockMeetingLoading = false;
                            if (success == true) {
                              lockMeeting = value;
                            }
                          });
                        }
                      }
                    : null,
              ),
              if (widget.showWaitingRoom)
                _SettingSwitch(
                  title: context.local.enable_waiting_room,
                  subtitle: waitingRoomEnabled
                      ? context.local.waiting_room_setting_on_description
                      : context.local.waiting_room_setting_off_description,
                  value: waitingRoomEnabled,
                  isLoading: _isWaitingRoomLoading,
                  onChanged:
                      widget.onWaitingRoomChanged != null &&
                          !_isWaitingRoomLoading
                      ? (value) async {
                          setState(() {
                            _isWaitingRoomLoading = true;
                          });
                          final success = await widget.onWaitingRoomChanged
                              ?.call(value: value);
                          if (mounted) {
                            setState(() {
                              _isWaitingRoomLoading = false;
                              if (success == true) {
                                waitingRoomEnabled = value;
                              }
                            });
                          }
                        }
                      : null,
                ),
            ],
          ),
        ],
        if (widget.showRecordingSaveLocation) ...[
          const SizedBox(height: 6),
          _buildSection(
            context,
            title: context.local.recording_save_location_section,
            children: [
              if (RecordingSaveLocationConfig.supportsSaveLocationPicker) ...[
                const RecordingSaveLocationSettingRow(),
                const SizedBox(height: 12),
              ],
              const SavedRecordingsSettingRow(),
            ],
          ),
        ],
        const SizedBox(height: 6),
        // Meeting options
        _buildSection(
          context,
          title: context.local.video,
          children: [
            _SettingSwitch(
              title: context.local.hide_self_view,
              value: hideSelfView,
              onChanged: widget.onHideSelfViewChanged != null
                  ? (value) {
                      setState(() {
                        hideSelfView = value;
                        widget.onHideSelfViewChanged?.call(value: value);
                      });
                    }
                  : null,
            ),
            if (widget.showCameraBackgroundBlur &&
                widget.onCameraBackgroundTap != null)
              _CameraBackgroundRow(
                selection: widget.cameraBackgroundSelection,
                onTap: widget.onCameraBackgroundTap!,
              ),
            if (widget.showAudioDenoise && widget.onAudioDenoiseChanged != null)
              _SettingSwitch(
                title: context.local.audio_noise_cancellation,
                value: audioDenoiseEnabled,
                onChanged: (value) {
                  setState(() {
                    audioDenoiseEnabled = value;
                    widget.onAudioDenoiseChanged?.call(value: value);
                  });
                },
              ),
            if (widget.showAudioDenoise &&
                audioDenoiseEnabled &&
                widget.audioDenoiseTypeOptions.length > 1 &&
                widget.onAudioDenoiseTypeSelected != null)
              ...widget.audioDenoiseTypeOptions.map(
                (option) => _SettingChoice(
                  title: option.label,
                  selected: widget.selectedAudioDenoiseType == option.type,
                  onTap: () =>
                      widget.onAudioDenoiseTypeSelected?.call(option.type),
                ),
              ),
            _SettingSwitch(
              title: context.local.unsubscribe_video_by_default,
              value: unsubscribeVideoByDefault,
              onChanged: widget.onUnsubscribeVideoByDefaultChanged != null
                  ? (value) {
                      setState(() {
                        unsubscribeVideoByDefault = value;
                        widget.onUnsubscribeVideoByDefaultChanged?.call(
                          value: value,
                        );
                      });
                    }
                  : null,
            ),
            if (widget.onPictureInPictureModeChanged != null && mobile)
              _SettingSwitch(
                title: context.local.picture_in_picture_mode,
                value: pictureInPictureMode,
                onChanged: widget.onPictureInPictureModeChanged != null
                    ? (value) {
                        setState(() {
                          pictureInPictureMode = value;
                          widget.onPictureInPictureModeChanged?.call(
                            value: value,
                          );
                        });
                      }
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Connection section
        if (widget.showConnectionSettings)
          _buildSection(
            context,
            title: context.local.connection,
            children: [
              if (widget.onReconnectPressed != null)
                _SettingSwitch(
                  title: context.local.reconnect_meeting,
                  value: widget.isRejoining,
                  isLoading: widget.isRejoining,
                  onChanged: (value) {
                    widget.onReconnectPressed?.call();
                  },
                ),
              if (widget.onForceShowConnectionStatusBannerChanged != null)
                _SettingSwitch(
                  title: context.local.always_show_status,
                  value: forceShowConnectionStatusBanner,
                  onChanged:
                      widget.onForceShowConnectionStatusBannerChanged != null
                      ? (value) {
                          setState(() {
                            forceShowConnectionStatusBanner = value;
                            widget.onForceShowConnectionStatusBannerChanged
                                ?.call(value: value);
                          });
                        }
                      : null,
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required List<Widget> children,
    required String title,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            title,
            style: ProtonStyles.body2Semibold(color: context.colors.textWeak),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ).copyWith(bottom: 12),
          decoration: ShapeDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
              borderRadius: BorderRadius.circular(
                RoomSidePanelLayout.borderRadiusMedium,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              ...children.map((child) {
                final isLast = child == children.last;
                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: isLast
                          ? null
                          : BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.04),
                                ),
                              ),
                            ),
                      child: child,
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isLoading;

  const _SettingSwitch({
    required this.title,
    required this.value,
    this.subtitle,
    this.onChanged,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: ProtonStyles.body1Medium(color: context.colors.textNorm),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: ProtonStyles.body2Regular(
                    color: context.colors.textWeak,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isLoading) ...[
          SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                context.colors.protonBlue,
              ),
            ),
          ),
          const SizedBox(width: 16, height: 33),
        ] else
          Container(
            height: 33,
            width: 56,
            decoration: BoxDecoration(
              border: Border.all(color: context.colors.interActionWeak),
              borderRadius: BorderRadius.circular(40),
            ),
            child: CupertinoSwitch(
              value: value,
              onChanged:
                  onChanged ??
                  (v) {
                    LocalToast.showToast(
                      context,
                      context.local.feature_not_ready,
                    );
                  },
              activeTrackColor: context.colors.backgroundNorm,
              inactiveTrackColor: context.colors.backgroundNorm,
              inactiveThumbColor: context.colors.interActionWeak,
              thumbColor: context.colors.protonBlue,
            ),
          ),
      ],
    );
  }
}

/// Decode width for the 28pt background swatch at 3x.
const int _backgroundSwatchCacheWidth = 84;

/// Opens the shared virtual background sheet and previews the active choice.
class _CameraBackgroundRow extends StatelessWidget {
  const _CameraBackgroundRow({required this.selection, required this.onTap});

  final CameraBackgroundSelection selection;
  final VoidCallback onTap;

  /// Null for presets — the thumbnail already identifies the image.
  String? _label(BuildContext context) {
    switch (selection.kind) {
      case CameraBackgroundEffectKind.none:
        return context.local.virtual_background_none;
      case CameraBackgroundEffectKind.blur:
      case CameraBackgroundEffectKind.preset:
        return null;
      case CameraBackgroundEffectKind.custom:
        return context.local.virtual_background_custom;
    }
  }

  Widget _thumbnail(BuildContext context) {
    const size = 28.0;
    Widget? image;
    switch (selection.kind) {
      case CameraBackgroundEffectKind.preset:
        final preset = VirtualBackgroundPresets.byId(selection.presetId);
        if (preset != null) {
          // Preset artwork is multi-megapixel; decode it at swatch size.
          image = preset.asset.image(
            fit: BoxFit.cover,
            cacheWidth: _backgroundSwatchCacheWidth,
          );
        }
      case CameraBackgroundEffectKind.custom:
        final path = selection.customImagePath;
        if (path != null && path.isNotEmpty) {
          image = Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: _backgroundSwatchCacheWidth,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
        }
      case CameraBackgroundEffectKind.none:
        image = null;
      case CameraBackgroundEffectKind.blur:
        image = context.images.iconVirtualBackgroundBlur.svgSize(
          color: context.colors.textNorm,
          size: _backgroundSwatchCacheWidth.toDouble(),
        );
    }
    if (image == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(width: size, height: size, child: image),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label = _label(context);
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.local.virtual_backgrounds_title,
              style: ProtonStyles.body1Medium(color: context.colors.textNorm),
            ),
          ),
          if (label != null)
            Text(
              label,
              style: ProtonStyles.body2Regular(color: context.colors.textWeak),
            ),
          _thumbnail(context),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: context.colors.textWeak, size: 22),
        ],
      ),
    );
  }
}

class _SettingChoice extends StatelessWidget {
  const _SettingChoice({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: ProtonStyles.body1Medium(color: context.colors.textNorm),
            ),
          ),
          Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected
                ? context.colors.protonBlue
                : context.colors.interActionWeak,
            size: 22,
          ),
        ],
      ),
    );
  }
}
