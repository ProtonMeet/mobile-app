import 'dart:math';

import 'package:flutter/material.dart';

/// Where to anchor a dropdown overlay relative to its trigger button.
enum OverlayAnchor {
  /// Prefer below the button; fall back above if needed.
  below,

  /// Prefer above the button; fall back below if needed.
  above,

  /// Prefer above; fall back below when there is not enough room above.
  auto,
}

class OverlayPlacement {
  const OverlayPlacement({
    required this.top,
    required this.maxHeight,
    required this.showsBelow,
  });

  final double top;
  final double maxHeight;
  final bool showsBelow;
}

OverlayPlacement computeOverlayPlacement({
  required BuildContext context,
  required Offset position,
  required Size buttonSize,
  required double preferredHeight,
  required double minMargin,
  OverlayAnchor anchor = OverlayAnchor.auto,
}) {
  final mq = MediaQuery.of(context);
  final screenHeight = mq.size.height;
  final safeTop = mq.viewPadding.top;
  final safeBottom = mq.viewPadding.bottom;

  final buttonTop = position.dy;
  final buttonBottom = position.dy + buttonSize.height;
  const gap = 4.0;

  final spaceAbove = max(0.0, buttonTop - safeTop - minMargin - gap);
  final spaceBelow = max(
    0.0,
    screenHeight - safeBottom - minMargin - buttonBottom - gap,
  );

  const minOverlayHeight = 120.0;
  final heightNeeded = min(preferredHeight, minOverlayHeight);

  final preferAbove = anchor != OverlayAnchor.below;

  final bool showsBelow = preferAbove
      ? _shouldShowBelowWhenAbovePreferred(spaceAbove, spaceBelow, heightNeeded)
      : _preferBelowWhenBelowPreferred(spaceAbove, spaceBelow, heightNeeded);

  final maxHeight = min(preferredHeight, showsBelow ? spaceBelow : spaceAbove);

  final top = showsBelow
      ? buttonBottom + gap
      : buttonTop - max(maxHeight, 0) - gap;

  return OverlayPlacement(
    top: top.clamp(
      safeTop + minMargin,
      max(
        safeTop + minMargin,
        screenHeight - safeBottom - minMargin - maxHeight,
      ),
    ),
    maxHeight: maxHeight,
    showsBelow: showsBelow,
  );
}

/// Above-first: show below only when there is not enough room above.
bool _shouldShowBelowWhenAbovePreferred(
  double spaceAbove,
  double spaceBelow,
  double heightNeeded,
) {
  if (spaceAbove >= heightNeeded) {
    return false;
  }
  if (spaceBelow >= heightNeeded) {
    return true;
  }
  return spaceBelow > spaceAbove;
}

/// Below-first: show above only when there is not enough room below.
bool _preferBelowWhenBelowPreferred(
  double spaceAbove,
  double spaceBelow,
  double heightNeeded,
) {
  if (spaceBelow >= heightNeeded) {
    return true;
  }
  if (spaceAbove >= heightNeeded) {
    return false;
  }
  return spaceBelow >= spaceAbove;
}

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
