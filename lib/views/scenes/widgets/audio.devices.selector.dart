import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/custom.tooltip.dart';
import 'package:meet/views/components/hover.widget.dart';
import 'package:meet/views/scenes/widgets/overlay_utility.dart';

class AudioDevicesSelector extends StatefulWidget {
  final List<MediaDevice> micDevices;
  final List<MediaDevice> speakerDevices;
  final MediaDevice? selectedMic;
  final MediaDevice? selectedSpeaker;
  final ValueChanged<MediaDevice?> onMicChanged;
  final ValueChanged<MediaDevice?> onSpeakerChanged;
  final ValueChanged<bool>? onAudioEnabled;
  final bool enabled;
  final bool permissionGranted;
  final bool showContent;
  final Color? backgroundColor;
  final double? width;
  final double minMerge;
  final bool autoSelectDevice;
  const AudioDevicesSelector({
    required this.micDevices,
    required this.speakerDevices,
    required this.onMicChanged,
    required this.onSpeakerChanged,
    required this.enabled,
    required this.showContent,
    this.selectedMic,
    this.selectedSpeaker,
    this.onAudioEnabled,
    this.permissionGranted = false,
    this.backgroundColor,
    this.width = 280,
    this.minMerge = 16,
    this.autoSelectDevice = false,
    super.key,
  });

  @override
  State<AudioDevicesSelector> createState() => _AudioDevicesSelectorState();
}

class _AudioDevicesSelectorState extends State<AudioDevicesSelector> {
  OverlayEntry? _overlayEntry;
  bool _isOverlayVisible = false;
  bool _enabled = false;
  final GlobalKey _buttonKey = GlobalKey();

  MediaDevice? _selectedMic;
  MediaDevice? _selectedSpeaker;

  final iconSize = 22.0;

  @override
  void initState() {
    super.initState();
    _selectedMic = widget.selectedMic;
    _selectedSpeaker = widget.selectedSpeaker;
    _enabled = widget.enabled;
  }

  @override
  void didUpdateWidget(AudioDevicesSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedMic != widget.selectedMic) {
      setState(() {
        _selectedMic = widget.selectedMic;
      });
    }
    if (oldWidget.selectedSpeaker != widget.selectedSpeaker) {
      setState(() {
        _selectedSpeaker = widget.selectedSpeaker;
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
      builder: (context) => GestureDetector(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        widget.onAudioEnabled?.call(!_enabled);
        if (widget.permissionGranted) {
          setState(() {
            _enabled = !_enabled;
          });
        }
      },
      child: Container(
        key: _buttonKey,
        padding: const EdgeInsets.only(left: 6, right: 4),
        decoration: BoxDecoration(
          color: _enabled
              ? widget.backgroundColor ?? context.colors.controlButtonBackground
              : context.colors.deviceSelectorDisabledBackground,
          borderRadius: BorderRadius.circular(9000),
          border: Border.all(color: context.colors.appBorderNorm),
        ),
        width: widget.autoSelectDevice
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
                  (widget.onAudioEnabled != null && widget.permissionGranted)
                      ? CustomTooltip(
                          message: _enabled
                              ? context.local.turn_off_microphone
                              : context.local.turn_on_microphone,
                          child: GestureDetector(
                            onTap: () {
                              if (widget.permissionGranted) {
                                widget.onAudioEnabled?.call(!_enabled);
                                setState(() {
                                  _enabled = !_enabled;
                                });
                              }
                            },
                            child: _enabled
                                ? context.images.iconAudioOn.svg(
                                    width: iconSize,
                                    height: iconSize,
                                  )
                                : context.images.iconAudioOff.svg(
                                    width: iconSize,
                                    height: iconSize,
                                  ),
                          ),
                        )
                      : _enabled
                      ? context.images.iconAudioOn.svg(
                          width: iconSize,
                          height: iconSize,
                        )
                      : context.images.iconAudioOff.svg(
                          width: iconSize,
                          height: iconSize,
                        ),
                  if (widget.showContent) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.showContent)
                            Text(
                              context.local.audio,
                              style: ProtonStyles.body2Regular(
                                color: context.colors.textWeak,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          Text(
                            widget.permissionGranted
                                ? _selectedMic?.label ??
                                      context.local.audio_settings
                                : context.local.permission_not_given,
                            style: ProtonStyles.body2Regular(
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
            if (!widget.autoSelectDevice)
              GestureDetector(
                onTap: widget.permissionGranted ? _toggleOverlay : null,
                child: Container(
                  width: 48,
                  height: 48,
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(
                    color: _enabled
                        ? widget.backgroundColor ??
                              context.colors.interActionWeekMinor2
                        : context
                              .colors
                              .deviceSelectorDisabledCircleAvatarBackground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9000),
                    ),
                  ),
                  child: Icon(
                    _isOverlayVisible
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: context.colors.textNorm,
                    size: 22,
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
        _buildSectionTitle(context.local.select_microphone),
        const SizedBox(height: 10),
        ...widget.micDevices.map(
          (device) => _buildOption(
            device.label,
            device == _selectedMic,
            onTap: () {
              setState(() {
                _selectedMic = device;
                widget.onMicChanged(device);
              });
              _removeOverlay();
            },
          ),
        ),
        const SizedBox(height: 20),
        _buildSectionTitle(context.local.select_speaker),
        const SizedBox(height: 10),
        ...widget.speakerDevices.map(
          (device) => _buildOption(
            device.label,
            device == _selectedSpeaker,
            onTap: () {
              setState(() {
                _selectedSpeaker = device;
                widget.onSpeakerChanged(device);
              });
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
                      color: context.colors.textNorm,
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
