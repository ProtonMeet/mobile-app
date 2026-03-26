import 'dart:async';

import 'package:flutter/material.dart';

class GradientActionButton extends StatelessWidget {
  const GradientActionButton({
    required this.text,
    required this.textStyle,
    super.key,
    this.onPressed,
    this.height = 60,
    this.borderRadius = 200,
    this.colors = const [Color(0xFFD1CBFF), Color(0xFF968AEF)],
  });

  final String text;
  final TextStyle textStyle;
  final FutureOr<void> Function()? onPressed;
  final double height;
  final double borderRadius;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: ElevatedButton(
        onPressed: onPressed == null
            ? null
            : () async {
                await onPressed?.call();
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          child: Center(child: Text(text, style: textStyle)),
        ),
      ),
    );
  }
}
