import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet/helper/extension/platform.extension.dart';

/// Top insets so desktop content clears the native title-bar controls.
///
/// macOS uses a hidden transparent title bar with [fullSizeContentView], so
/// Flutter's [MediaQuery] does not report top safe-area padding.
class DesktopContentFit {
  const DesktopContentFit._();

  /// Vertical space reserved for the traffic-light row.
  static const double macOSTitleBarHeight = 28;

  static EdgeInsets minimumSafeArea(BuildContext context) {
    if (!macOS || kIsWeb) {
      return EdgeInsets.zero;
    }

    final mediaTop = MediaQuery.paddingOf(context).top;
    if (mediaTop > 0) {
      return EdgeInsets.zero;
    }

    return const EdgeInsets.only(top: macOSTitleBarHeight);
  }

  static double extraTopPadding(BuildContext context) {
    return minimumSafeArea(context).top;
  }
}
