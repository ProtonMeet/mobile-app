import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/close_button_v1.dart';

class DeprecatedOsWarningCard extends StatelessWidget {
  const DeprecatedOsWarningCard({
    required this.onDismiss,
    required this.message,
    required this.dismissTestId,
    super.key,
  });

  final VoidCallback onDismiss;
  final Widget message;
  final String dismissTestId;

  @override
  Widget build(BuildContext context) {
    final gradientStartColor = context.colors.signalWaning;
    final gradientEndColor =
        Color.lerp(context.colors.signalWaning, Colors.black, 0.18) ??
        context.colors.signalWaning;

    return Stack(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
            decoration: ShapeDecoration(
              gradient: LinearGradient(
                begin: const Alignment(0.98, 1.00),
                end: const Alignment(0.02, 0.07),
                colors: [gradientStartColor, gradientEndColor],
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: message,
          ),
        ),
        Positioned(
          right: 16,
          top: 16,
          child: CloseButtonV1(
            testId: dismissTestId,
            onPressed: onDismiss,
            backgroundColor: Colors.transparent,
          ),
        ),
      ],
    );
  }
}
