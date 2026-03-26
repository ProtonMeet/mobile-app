import 'dart:math';

import 'package:flutter/material.dart';

double computeOverlayLeft({
  required BuildContext context,
  required Offset position, // button's global top-left
  required Size buttonSize,
  required double overlayWidth, // desired width
  required double minMargin, // your widget.minMerge
}) {
  final mq = MediaQuery.of(context);
  final screenWidth = mq.size.width;

  // Safe areas (notches, rounded corners, system UI on iPad split view, etc.)
  final safeLeft = mq.viewPadding.left;
  final safeRight = mq.viewPadding.right;

  // Max width we can occupy inside the window with margins + safe areas
  final maxAllowedWidth = screenWidth - safeLeft - safeRight - (2 * minMargin);

  // Clamp the actual overlay width so it never exceeds the available space
  final clampedWidth = overlayWidth.clamp(0.0, max(0.0, maxAllowedWidth));

  // Center the overlay over the button by default
  final desiredLeft = position.dx + (buttonSize.width - clampedWidth) / 2;

  // Left/right bounds inside the window
  final minLeft = safeLeft + minMargin;
  final maxLeft = screenWidth - safeRight - minMargin - clampedWidth;

  final finalLeft = desiredLeft.clamp(minLeft, maxLeft);
  // Final clamped left
  return finalLeft;
}
