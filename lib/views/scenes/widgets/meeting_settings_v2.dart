import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';

class MeetingSettingsV2 extends StatefulWidget {
  final void Function({required bool value})? onHideSelfViewChanged;
  final void Function({required bool value})?
  onUnsubscribeVideoByDefaultChanged;
  final void Function({required bool value})? onPictureInPictureModeChanged;
  final Future<bool> Function({required bool value})? onLockMeetingChanged;
  final VoidCallback? onReconnectPressed;
  final void Function({required bool value})?
  onForceShowConnectionStatusBannerChanged;
  final bool hideSelfView;
  final bool unsubscribeVideoByDefault;
  final bool pictureInPictureMode;
  final bool lockMeeting;
  final bool isHost;
  final bool isRejoining;
  final bool forceShowConnectionStatusBanner;
  final bool showConnectionSettings;

  const MeetingSettingsV2({
    required this.hideSelfView,
    required this.unsubscribeVideoByDefault,
    required this.onUnsubscribeVideoByDefaultChanged,
    required this.pictureInPictureMode,
    required this.lockMeeting,
    required this.isHost,
    this.onHideSelfViewChanged,
    this.onPictureInPictureModeChanged,
    this.onLockMeetingChanged,
    this.onReconnectPressed,
    this.onForceShowConnectionStatusBannerChanged,
    this.isRejoining = false,
    this.forceShowConnectionStatusBanner = false,
    this.showConnectionSettings = false,
    super.key,
  });

  @override
  State<MeetingSettingsV2> createState() => _MeetingSettingsV2State();
}

class _MeetingSettingsV2Constants {
  static const double headerHeight = 51.0;
  static const double horizontalPadding = 24.0;
  static const double borderRadiusMedium = 24.0;
  static const double borderRadiusLarge = 40.0;
  static const double borderColorAlpha = 0.03;
}

class _MeetingSettingsV2State extends State<MeetingSettingsV2> {
  final ScrollController _scrollController = ScrollController();

  // Meeting options
  bool hideSelfView = false;
  bool unsubscribeVideoByDefault = false;
  bool pictureInPictureMode = false;
  bool lockMeeting = false;
  bool forceShowConnectionStatusBanner = false;

  // Loading states
  bool _isLockMeetingLoading = false;

  @override
  void initState() {
    super.initState();

    hideSelfView = widget.hideSelfView;
    unsubscribeVideoByDefault = widget.unsubscribeVideoByDefault;
    pictureInPictureMode = widget.pictureInPictureMode;
    lockMeeting = widget.lockMeeting;
    forceShowConnectionStatusBanner = widget.forceShowConnectionStatusBanner;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = context.isLandscape && mobile;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(_MeetingSettingsV2Constants.borderRadiusLarge),
        topRight: Radius.circular(
          _MeetingSettingsV2Constants.borderRadiusLarge,
        ),
      ),
      child: RepaintBoundary(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: _buildContainerDecoration(context),
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.deferToChild,
              child: _buildScrollableContent(context, isLandscape),
            ),
          ),
        ),
      ),
    );
  }

  Decoration _buildContainerDecoration(BuildContext context) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(_MeetingSettingsV2Constants.borderRadiusMedium),
      topRight: Radius.circular(_MeetingSettingsV2Constants.borderRadiusMedium),
    );

    return BoxDecoration(
      color: context.colors.blurBottomSheetBackground,
      border: Border.all(
        color: Colors.white.withValues(
          alpha: _MeetingSettingsV2Constants.borderColorAlpha,
        ),
      ),
      borderRadius: borderRadius,
    );
  }

  Widget _buildScrollableContent(BuildContext context, bool isLandscape) {
    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              toolbarHeight:
                  _MeetingSettingsV2Constants.headerHeight +
                  (!isLandscape ? 36.0 : 8.0),
              expandedHeight:
                  _MeetingSettingsV2Constants.headerHeight +
                  (!isLandscape ? 36.0 : 8.0),
              flexibleSpace: SizedBox.expand(
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(
                      _MeetingSettingsV2Constants.borderRadiusMedium,
                    ),
                    topRight: Radius.circular(
                      _MeetingSettingsV2Constants.borderRadiusMedium,
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: context.colors.clear,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(
                              _MeetingSettingsV2Constants.borderRadiusMedium,
                            ),
                            topRight: Radius.circular(
                              _MeetingSettingsV2Constants.borderRadiusMedium,
                            ),
                          ),
                        ),
                      ),
                      child: _buildHeaderWithoutHandle(isLandscape),
                    ),
                  ),
                ),
              ),
            ),
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
        ),
        // Handle area that allows bottom sheet drag to work
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height:
              _MeetingSettingsV2Constants.headerHeight +
              (!isLandscape ? 36.0 : 8.0),
          child: AbsorbPointer(
            child: Stack(
              children: [
                if (!isLandscape)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 36.0,
                    child: BottomSheetHandleBar(),
                  ),
                Positioned(
                  top: !isLandscape ? 36.0 : 8.0,
                  left: 0,
                  right: 0,
                  height: _MeetingSettingsV2Constants.headerHeight,
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: _MeetingSettingsV2Constants.horizontalPadding,
                      right: _MeetingSettingsV2Constants.horizontalPadding,
                      bottom: _MeetingSettingsV2Constants.horizontalPadding,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        context.local.meeting_settings,
                        style: ProtonStyles.headline(
                          fontSize: 18,
                          color: context.colors.textNorm,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderWithoutHandle(bool isLandscape) {
    return Container(
      width: double.infinity,
      height:
          _MeetingSettingsV2Constants.headerHeight +
          (!isLandscape ? 36.0 : 8.0),
      padding: EdgeInsets.only(
        left: _MeetingSettingsV2Constants.horizontalPadding,
        right: _MeetingSettingsV2Constants.horizontalPadding,
        bottom: _MeetingSettingsV2Constants.horizontalPadding,
        top: !isLandscape ? 36.0 : 8.0,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          context.local.meeting_settings,
          style: ProtonStyles.headline(
            fontSize: 18,
            color: context.colors.textNorm,
          ),
        ),
      ),
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
            if (widget.onPictureInPictureModeChanged != null && android)
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
              borderRadius: BorderRadius.circular(24),
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
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool isLoading;

  const _SettingSwitch({
    required this.title,
    required this.value,
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
