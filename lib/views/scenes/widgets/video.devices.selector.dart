import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/custom.tooltip.dart';
import 'package:meet/views/components/hover.widget.dart';
import 'package:meet/views/scenes/widgets/overlay_utility.dart';

class VideoDevicesSelector extends StatefulWidget {
  final List<MediaDevice> videoDevices;
  final MediaDevice? selectedVideo;
  final ValueChanged<MediaDevice?> onVideoChanged;
  final ValueChanged<bool>? onVideoEnabled;
  final bool enabled;
  final bool permissionGranted;
  final bool showContent;
  final Color? backgroundColor;
  final double? width;
  final double minMerge;
  final bool autoSelectDevcie;
  const VideoDevicesSelector({
    required this.videoDevices,
    required this.onVideoChanged,
    required this.enabled,
    required this.showContent,
    this.autoSelectDevcie = false,
    this.selectedVideo,
    this.onVideoEnabled,
    this.permissionGranted = false,
    this.backgroundColor,
    this.width = 280,
    this.minMerge = 16,
    super.key,
  });

  @override
  State<VideoDevicesSelector> createState() => _VideoDevicesSelectorState();
}

class _VideoDevicesSelectorState extends State<VideoDevicesSelector> {
  OverlayEntry? _overlayEntry;
  bool _isOverlayVisible = false;
  bool _enabled = false;
  final GlobalKey _buttonKey = GlobalKey();
  MediaDevice? _selectedVideo;

  @override
  void initState() {
    super.initState();
    _selectedVideo = widget.selectedVideo;
    _enabled = widget.enabled;
  }

  @override
  void didUpdateWidget(VideoDevicesSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedVideo != widget.selectedVideo) {
      setState(() {
        _selectedVideo = widget.selectedVideo;
      });
    }
    if (oldWidget.permissionGranted != widget.permissionGranted) {
      setState(() {
        _enabled = widget.enabled;
      });
    }
    if (oldWidget.enabled != widget.enabled) {
      setState(() {
        _enabled = widget.enabled;
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _toggleOverlay() {
    if (_isOverlayVisible) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    setState(() {
      _isOverlayVisible = true;
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (_isOverlayVisible) {
      setState(() {
        _isOverlayVisible = false;
      });
    }
  }

  OverlayEntry _createOverlayEntry() {
    final RenderBox? renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final Offset? position = renderBox?.localToGlobal(Offset.zero);
    final Size? buttonSize = renderBox?.size;
    final overlayWidth = 320.0;
    final overlayHeight = 320.0;

    return OverlayEntry(
      builder: (context) {
        return GestureDetector(
          onTap: _removeOverlay,
          behavior: HitTestBehavior.translucent,
          child: ColoredBox(
            color: Colors.black.withValues(alpha: 0.3),
            child: Stack(
              children: [
                if (position != null && buttonSize != null)
                  Positioned(
                    left: computeOverlayLeft(
                      context: context,
                      position: position,
                      buttonSize: buttonSize,
                      overlayWidth: overlayWidth,
                      minMargin: widget.minMerge,
                    ),
                    top: position.dy - overlayHeight - 4,
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: overlayWidth,
                        height: overlayHeight,
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.backgroundNorm,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [_buildOverlayContent(context)],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onVideoEnabled?.call(!_enabled);
        if (widget.permissionGranted) {
          setState(() {
            _enabled = !_enabled;
          });
        }
      },
      child: Container(
        key: _buttonKey,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _enabled
              ? widget.backgroundColor ?? context.colors.controlButtonBackground
              : context.colors.deviceSelectorDisabledBackground,
          borderRadius: BorderRadius.circular(9000),
          border: Border.all(color: context.colors.appBorderNorm),
        ),
        width: widget.autoSelectDevcie
            ? 56
            : widget.showContent
            ? widget.width
            : 110,
        height: 56,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 11),
                  (widget.onVideoEnabled != null && widget.permissionGranted)
                      ? CustomTooltip(
                          message: _enabled
                              ? context.local.turn_off_camera
                              : context.local.turn_on_camera,
                          child: GestureDetector(
                            onTap: () {
                              widget.onVideoEnabled?.call(!_enabled);
                              setState(() {
                                _enabled = !_enabled;
                              });
                            },
                            child: _enabled
                                ? context.images.iconVideoOn.svg22()
                                : context.images.iconVideoOff.svg22(),
                          ),
                        )
                      : _enabled
                      ? context.images.iconVideoOn.svg22()
                      : context.images.iconVideoOff.svg22(),
                  if (widget.showContent) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.showContent)
                            Text(
                              context.local.video,
                              style: ProtonStyles.body2Regular(
                                color: context.colors.textWeak,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          Text(
                            widget.permissionGranted
                                ? _selectedVideo?.label ??
                                      context.local.video_settings
                                : context.local.permission_not_given,
                            style: ProtonStyles.body2Medium(
                              color: context.colors.textNorm,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),

            if (!widget.autoSelectDevcie)
              GestureDetector(
                onTap: widget.permissionGranted ? _toggleOverlay : null,
                child: Container(
                  width: 46,
                  height: 46,
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(
                    color: _enabled
                        ? widget.backgroundColor ??
                              context.colors.interActionWeekMinor2
                        : context
                              .colors
                              .deviceSelectorDisabledCircleAvatarBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: Icon(
                    _isOverlayVisible
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: context.colors.textNorm,
                    size: 24,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayContent(BuildContext context) {
    return Column(
      children: [
        _buildSectionTitle(context.local.select_camera_device),
        const SizedBox(height: 10),
        ...widget.videoDevices.map(
          (device) => _buildOption(
            device.label,
            device.deviceId == _selectedVideo?.deviceId,
            onTap: () {
              setState(() {
                _selectedVideo = device;
              });
              widget.onVideoChanged(device);
              _removeOverlay();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: ProtonStyles.body2Regular(color: context.colors.textWeak),
        ),
      ),
    );
  }

  Widget _buildOption(String label, bool selected, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: widget.permissionGranted ? onTap : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: HoverWidget(
          backgroundColor: Colors.transparent,
          hoverColor: context.colors.interActionWeak,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Row(
              children: [
                Visibility(
                  visible: selected,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Row(
                    children: [
                      Icon(
                        Icons.check,
                        color: context.colors.textNorm,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
