import 'package:flutter/material.dart';

class HoverWidget extends StatefulWidget {
  final Color backgroundColor;
  final Color hoverColor;
  final Widget child;
  final BorderRadiusGeometry? borderRadius;

  const HoverWidget({
    required this.backgroundColor,
    required this.hoverColor,
    required this.child,
    this.borderRadius,
    super.key,
  });

  @override
  State<HoverWidget> createState() => _HoverWidgetState();
}

class _HoverWidgetState extends State<HoverWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _isHovered ? widget.hoverColor : widget.backgroundColor,
          borderRadius: widget.borderRadius,
        ),
        child: widget.child,
      ),
    );
  }
}
