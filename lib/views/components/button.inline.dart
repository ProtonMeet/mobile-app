import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class ButtonInline extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? textColor;
  final double? width;
  final double? height;
  final double? borderRadius;

  const ButtonInline({
    required this.text,
    required this.onPressed,
    this.backgroundColor,
    this.textColor,
    this.width,
    this.height,
    this.borderRadius,
    super.key,
  });

  @override
  State<ButtonInline> createState() => _ButtonInlineState();
}

class _ButtonInlineState extends State<ButtonInline> {
  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        fixedSize: Size(widget.width ?? 90, widget.height ?? 30),
        backgroundColor:
            widget.backgroundColor ?? context.colors.notificationError,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.borderRadius ?? 40),
          side: BorderSide(
            color: widget.backgroundColor ?? context.colors.notificationError,
          ),
        ),
        elevation: 0.0,
      ),
      onPressed: widget.onPressed,
      child: Text(
        widget.text,
        style: ProtonStyles.body2Medium(
          color: widget.textColor ?? context.colors.textInverted,
        ),
      ),
    );
  }
}
