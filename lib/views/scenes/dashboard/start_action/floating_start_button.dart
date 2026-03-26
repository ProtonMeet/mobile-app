import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';

import 'expandable_start.dart';
import 'menu_item.dart';

class FloatingStartButton extends StatefulWidget {
  const FloatingStartButton({
    required this.onSchedule,
    required this.onPersonalMeeting,
    required this.onCreateRoom,
    required this.onJoinLink,
    required this.onInstant,
    super.key,
    this.isScheduleInAdvanceEnabled = false,
  });

  final VoidCallback onSchedule;
  final VoidCallback onPersonalMeeting;
  final VoidCallback onCreateRoom;
  final VoidCallback onJoinLink;
  final VoidCallback onInstant;
  final bool isScheduleInAdvanceEnabled;

  @override
  State<FloatingStartButton> createState() => _FloatingStartButtonState();
}

class _FloatingStartButtonState extends State<FloatingStartButton>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  // 0.0 collapsed, 1.0 expanded (for drag)
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: defaultAnimationDuration,
    value: 0,
  );

  void _open() {
    setState(() => _expanded = true);
    _c.animateTo(1, curve: Curves.easeOutCubic);
  }

  Future<void> _close() async {
    if (!_expanded) return;
    await _c.animateTo(0, curve: Curves.easeInCubic);
    if (!mounted) return;
    setState(() => _expanded = false);
  }

  void _toggle() => _expanded ? _close() : _open();

  Future<void> _action(VoidCallback cb) async {
    _close();
    if (!mounted) return;
    cb();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  final padding = 8.0;
  @override
  Widget build(BuildContext context) {
    /// Expanded panel size
    final w = context.width;
    final panelWidth = (w - padding * 2).clamp(280.0, 480.0);
    const menuItemHeight = 56.0;
    final menuItemCount = widget.isScheduleInAdvanceEnabled ? 3 : 2;

    /// 260.0 with 3 buttons;
    final menuContentHeight = menuItemHeight * menuItemCount + 92;

    /// 308.0 with 3 buttons;
    final panelMaxHeight = menuItemHeight * menuItemCount + 140;

    /// Collapsed pill size
    const collapsedW = 200.0;
    const pillH = 64.0;

    return Stack(
      children: [
        /// Tap outside overlay
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: Container(color: Colors.transparent),
            ),
          ),

        /// Panel + pill (always anchored to bottom-right)
        Positioned(
          right: padding,
          bottom: padding,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              // Smooth interpolation for the extra padding during transition
              // Fades from 32 to 0 as t goes from 0 to 0.5
              final extraPadding = t < 0.5
                  ? lerpDouble(32.0, 0.0, t * 2)!
                  : 0.0;
              final currentW =
                  lerpDouble(collapsedW, panelWidth, t)! + extraPadding;
              final currentH =
                  lerpDouble(pillH, panelMaxHeight, t)! + extraPadding + 10;

              return SizedBox(
                width: currentW,
                height: currentH,
                child: Material(
                  color: Colors.transparent,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: t > 0.2
                        ? _buildExpandView(t, menuContentHeight, pillH)
                        : _buildCollapseView(t, menuContentHeight, pillH),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCollapseView(double t, double menuContentHeight, double pillH) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
      ),
      child: Stack(
        children: [
          /// Expanded content (scrollable to avoid overflow)
          if (t > 0.01) _buildExpandedActions(t, menuContentHeight),

          /// + Start action Text
          ExpandableStart(
            t: t,
            pillH: pillH,
            onToggle: _toggle,
            onInstant: () => _action(widget.onInstant),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandView(double t, double menuContentHeight, double pillH) {
    final double sigma = 10;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.colors.interActionWeekMinor2.withValues(alpha: 0.30),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(40),
          ),
        ),
        child: Stack(
          children: [
            /// Expanded content (scrollable to avoid overflow)
            if (t > 0.01) _buildExpandedActions(t, menuContentHeight),

            /// + Start action Text
            ExpandableStart(
              t: t,
              pillH: pillH,
              onToggle: _toggle,
              onInstant: () => _action(widget.onInstant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedActions(double t, double menuContentHeight) {
    return Opacity(
      opacity: t,
      child: Column(
        children: [
          BottomSheetHandleBar(
            padding: const EdgeInsets.all(16),
            onDragUpdate: (dy) {
              // dy>0 means dragging down -> close
              // Convert drag distance to animation progress delta
              // menuContentHeight is the approximate panel height used for normalization
              final delta = dy / menuContentHeight;
              // Update animation controller value based on drag direction
              // Clamp to ensure value stays within valid range [0.0, 1.0]
              _c.value = (_c.value - delta).clamp(0.0, 1.0);
              l.logger.d('dy: $dy');
            },
            onDragEnd: () {
              // Determine final state based on current animation progress
              // If less than 60% expanded, snap closed; otherwise snap open
              if (_c.value < 0.6) {
                _close();
              } else {
                _open();
              }
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(left: 24, right: 24, bottom: 16),
              child: Column(
                children: [
                  if (widget.isScheduleInAdvanceEnabled)
                    MenuItem(
                      label: context.local.schedule_a_meeting,
                      icon: context.images.iconMeetingCalendar,
                      onTap: () => _action(widget.onSchedule),
                    ),
                  MenuItem(
                    label: context.local.create_new_room,
                    icon: context.images.iconMeetingPerson,
                    onTap: () => _action(widget.onCreateRoom),
                  ),
                  MenuItem(
                    label: context.local.join_with_a_link,
                    icon: context.images.iconLink,
                    onTap: () => _action(widget.onJoinLink),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
