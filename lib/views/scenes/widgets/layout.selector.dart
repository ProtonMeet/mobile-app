import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/custom.tooltip.dart';
import 'package:meet/views/scenes/room/camera_layout.dart';
import 'package:meet/views/scenes/widgets/overlay_utility.dart';

class LayoutSelector extends StatefulWidget {
  final CameraLayout selectedLayout;
  final ValueChanged<CameraLayout> onLayoutChanged;
  final double minMerge;
  const LayoutSelector({
    required this.selectedLayout,
    required this.onLayoutChanged,
    this.minMerge = 16,
    super.key,
  });

  @override
  State<LayoutSelector> createState() => _LayoutSelectorState();
}

class _LayoutSelectorState extends State<LayoutSelector> {
  OverlayEntry? _overlayEntry;
  bool _isOverlayVisible = false;
  final GlobalKey _buttonKey = GlobalKey();

  CameraLayout _selectedLayout = CameraLayout.grid;

  @override
  void initState() {
    super.initState();
    _selectedLayout = widget.selectedLayout;
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
    final overlayHeight = 260.0;

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
                      padding: const EdgeInsets.all(20),
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
      onTap: _toggleOverlay,
      child: Container(
        key: _buttonKey,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: context.colors.controlButtonBackground,
          borderRadius: BorderRadius.circular(44),
        ),
        width: 110,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 18),
                  CustomTooltip(
                    message: context.local.change_layout,
                    child: Icon(
                      _selectedLayout.toIconData(),
                      color: context.colors.textNorm,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 46,
              height: 46,
              clipBehavior: Clip.antiAlias,
              decoration: ShapeDecoration(
                color: context.colors.interActionWeekMinor2,
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
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayContent(BuildContext context) {
    return Column(
      children: [
        _buildSectionTitle(context.local.change_layout),
        const SizedBox(height: 10),
        ...CameraLayout.values.map(
          (layout) => _buildOption(
            layout.toLabel(context),
            layout.toIconData(),
            layout == _selectedLayout,
            onTap: () {
              setState(() {
                _selectedLayout = layout;
                widget.onLayoutChanged(layout);
              });
              _removeOverlay();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: ProtonStyles.body2Regular(color: context.colors.textWeak),
      ),
    );
  }

  Widget _buildOption(
    String label,
    IconData icon,
    bool selected, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2C2C3C) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check, color: Colors.white70, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}
