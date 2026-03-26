import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

/// Custom responsive breakpoints
class ResponsiveBreakpoints {
  static const double xxsmall = 375.0;
  static const double xsmall = 450.0;
  static const double small = 680.0;
  static const double medium = 1050.0;
  static const double large = 1150.0;
  static const double xlarge = 1500.0;
}

/// Responsive size enum
enum ResponsiveSize { xxsmall, xsmall, small, medium, large, xlarge }

/// Enhanced responsive widget with custom breakpoints
class ResponsiveV2 extends StatelessWidget {
  final Widget? xxsmall;
  final Widget? xsmall;
  final Widget? small;
  final Widget? medium;
  final Widget? large;
  final Widget? xlarge;

  const ResponsiveV2({
    super.key,
    this.xxsmall,
    this.xsmall,
    this.small,
    this.medium,
    this.large,
    this.xlarge,
  });

  /// Get the current responsive size based on screen width
  static ResponsiveSize getSize(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < ResponsiveBreakpoints.xxsmall) {
      return ResponsiveSize.xxsmall;
    } else if (width < ResponsiveBreakpoints.xsmall) {
      return ResponsiveSize.xsmall;
    } else if (width < ResponsiveBreakpoints.small) {
      return ResponsiveSize.small;
    } else if (width < ResponsiveBreakpoints.medium) {
      return ResponsiveSize.medium;
    } else if (width < ResponsiveBreakpoints.large) {
      return ResponsiveSize.large;
    } else if (width < ResponsiveBreakpoints.xlarge) {
      return ResponsiveSize.xlarge;
    } else {
      return ResponsiveSize.xlarge;
    }
  }

  /// Get the current responsive size based on width
  static ResponsiveSize getSizeByWidth(double width) {
    if (width < ResponsiveBreakpoints.xxsmall) {
      return ResponsiveSize.xxsmall;
    } else if (width < ResponsiveBreakpoints.xsmall) {
      return ResponsiveSize.xsmall;
    } else if (width < ResponsiveBreakpoints.small) {
      return ResponsiveSize.small;
    } else if (width < ResponsiveBreakpoints.medium) {
      return ResponsiveSize.medium;
    } else if (width < ResponsiveBreakpoints.large) {
      return ResponsiveSize.large;
    } else if (width < ResponsiveBreakpoints.xlarge) {
      return ResponsiveSize.xlarge;
    } else {
      return ResponsiveSize.xlarge;
    }
  }

  /// Get screen width (cached for performance)
  static double _getWidth(BuildContext context) {
    return context.width;
  }

  /// Check if current size is xxsmall
  static bool isXXSmall(BuildContext context) {
    return _getWidth(context) < ResponsiveBreakpoints.xxsmall;
  }

  /// Check if current size is xsmall
  static bool isXSmall(BuildContext context) {
    final width = _getWidth(context);
    return width >= ResponsiveBreakpoints.xxsmall &&
        width < ResponsiveBreakpoints.xsmall;
  }

  /// Check if current size is small
  static bool isSmall(BuildContext context) {
    final width = _getWidth(context);
    return width >= ResponsiveBreakpoints.xsmall &&
        width < ResponsiveBreakpoints.small;
  }

  /// Check if current size is medium
  static bool isMedium(BuildContext context) {
    final width = _getWidth(context);
    return width >= ResponsiveBreakpoints.small &&
        width < ResponsiveBreakpoints.medium;
  }

  /// Check if current size is large
  static bool isLarge(BuildContext context) {
    final width = _getWidth(context);
    return width >= ResponsiveBreakpoints.medium &&
        width < ResponsiveBreakpoints.large;
  }

  /// Check if current size is xlarge
  static bool isXLarge(BuildContext context) {
    return _getWidth(context) >= ResponsiveBreakpoints.xlarge;
  }

  /// Check if current size is at least small
  static bool isAtLeastSmall(BuildContext context) {
    return _getWidth(context) >= ResponsiveBreakpoints.small;
  }

  /// Check if current size is at least medium
  static bool isAtLeastMedium(BuildContext context) {
    return _getWidth(context) >= ResponsiveBreakpoints.medium;
  }

  /// Check if current size is at least large
  static bool isAtLeastLarge(BuildContext context) {
    return _getWidth(context) >= ResponsiveBreakpoints.large;
  }

  /// Check if current size is at least xlarge
  static bool isAtLeastXLarge(BuildContext context) {
    return _getWidth(context) >= ResponsiveBreakpoints.xlarge;
  }

  @override
  Widget build(BuildContext context) {
    final size = getSize(context);

    // Return the most specific widget available, falling back to larger sizes
    switch (size) {
      case ResponsiveSize.xxsmall:
        return xxsmall ??
            xsmall ??
            small ??
            medium ??
            large ??
            xlarge ??
            const SizedBox.shrink();
      case ResponsiveSize.xsmall:
        return xsmall ??
            small ??
            medium ??
            large ??
            xlarge ??
            xxsmall ??
            const SizedBox.shrink();
      case ResponsiveSize.small:
        return small ??
            medium ??
            large ??
            xlarge ??
            xsmall ??
            xxsmall ??
            const SizedBox.shrink();
      case ResponsiveSize.medium:
        return medium ??
            large ??
            xlarge ??
            small ??
            xsmall ??
            xxsmall ??
            const SizedBox.shrink();
      case ResponsiveSize.large:
        return large ??
            xlarge ??
            medium ??
            small ??
            xsmall ??
            xxsmall ??
            const SizedBox.shrink();
      case ResponsiveSize.xlarge:
        return xlarge ??
            large ??
            medium ??
            small ??
            xsmall ??
            xxsmall ??
            const SizedBox.shrink();
    }
  }
}

/// Extension methods for BuildContext to easily access responsive utilities
extension ResponsiveV2Extension on BuildContext {
  /// Get the current responsive size
  ResponsiveSize get responsiveSize => ResponsiveV2.getSize(this);

  /// Get the current screen width
  double get screenWidth => MediaQuery.of(this).size.width;

  /// Get the current screen height
  double get screenHeight => MediaQuery.of(this).size.height;

  /// Check if current size is xxsmall
  bool get isXXSmall => ResponsiveV2.isXXSmall(this);

  /// Check if current size is xsmall
  bool get isXSmall => ResponsiveV2.isXSmall(this);

  /// Check if current size is small
  bool get isSmall => ResponsiveV2.isSmall(this);

  /// Check if current size is medium
  bool get isMedium => ResponsiveV2.isMedium(this);

  /// Check if current size is large
  bool get isLarge => ResponsiveV2.isLarge(this);

  /// Check if current size is xlarge
  bool get isXLarge => ResponsiveV2.isXLarge(this);

  /// Check if current size is at least small
  bool get isAtLeastSmall => ResponsiveV2.isAtLeastSmall(this);

  /// Check if current size is at least medium
  bool get isAtLeastMedium => ResponsiveV2.isAtLeastMedium(this);

  /// Check if current size is at least large
  bool get isAtLeastLarge => ResponsiveV2.isAtLeastLarge(this);

  /// Check if current size is at least xlarge
  bool get isAtLeastXLarge => ResponsiveV2.isAtLeastXLarge(this);
}
