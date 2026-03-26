import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class OverlayActions {
  final String title;
  final Widget icon;
  final VoidCallback onTap;

  OverlayActions({
    required this.title,
    required this.icon,
    required this.onTap,
  });
}

class IconButtonWithActions extends StatefulWidget {
  final List<OverlayActions> actions;
  final Widget icon;
  final double iconSize;
  final EdgeInsets padding;
  final String? tooltip;
  final Offset? offset;

  const IconButtonWithActions({
    required this.actions,
    required this.icon,
    super.key,
    this.iconSize = 24.0,
    this.padding = const EdgeInsets.all(8.0),
    this.tooltip,
    this.offset,
  });

  @override
  State<IconButtonWithActions> createState() => _IconButtonWithActionsState();
}

class _IconButtonWithActionsState extends State<IconButtonWithActions> {
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  void _showMenu() {
    if (widget.actions.isEmpty) {
      return;
    }
    final renderBox =
        _buttonKey.currentContext!.findRenderObject()! as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removeMenu,
              child: Container(),
            ),
          ),
          Positioned(
            left: position.dx + (widget.offset?.dx ?? 0.0),
            top: position.dy + size.height + 4 + (widget.offset?.dy ?? 0.0),
            child: Container(
              width: 240,
              decoration: BoxDecoration(
                color: context.colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  width: 0.8,
                  color: context.colors.appBorderNorm,
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: widget.actions.map((action) {
                  return InkWell(
                    onTap: () {
                      _removeMenu();
                      action.onTap();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          action.icon,
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              action.title,
                              style: ProtonStyles.body2Medium(
                                color: context.colors.textNorm,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeMenu() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _buttonKey,
      onPressed: _showMenu,
      icon: widget.icon,
      iconSize: widget.iconSize,
      padding: widget.padding,
      tooltip: widget.tooltip,
    );
  }
}
