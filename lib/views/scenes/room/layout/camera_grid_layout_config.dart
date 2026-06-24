import 'package:flutter/material.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/views/scenes/core/responsive_v2.dart';

/// Grid layout presets for in-room participant video tiles.
///
/// Used by [ResponsiveCameraLayout] (spaced grid) and
/// [FixedSizingCameraLayout] (compact grid).
///
/// ## Configuration format
///
/// Each preset is `[columns, rows]`. Presets are ordered largest-first; the
/// first preset that fits the available area is chosen.
///
/// ## Window-size tiers (desktop only)
///
/// Breakpoints come from [ResponsiveBreakpoints]:
///
/// | Tier    | Width              | Spaced grid (landscape) | Compact grid (5+ people) |
/// |---------|--------------------|-------------------------|--------------------------|
/// | Small   | under 1050px       | up to 3×2               | up to 3×2                |
/// | Medium  | 1050–1150px        | up to 4×2               | up to 4×2                |
/// | Large   | 1150–1500px        | up to 5×3               | up to 4×3                |
/// | XLarge  | ≥ 1500px           | up to 6×3               | up to 5×3                |
///
/// Mobile keeps the original presets and does not use these tiers.
///
/// ## Selection
///
/// [selectBest] picks the first `[col, row]` where each tile is at least
/// [minTileWidth] wide and `row` tile heights fit in the viewport.
/// [selectBestForLastPage] re-runs selection on the final page (configs in
/// reverse order) so a partial last page uses a tighter grid and aspect ratio.
///
/// ## Auto-subscribe window ([ResponsiveCameraLayout])
///
/// Camera tracks are subscribed for the current page (HIGH quality) plus
/// nearby pages (LOW quality prefetch). [subscriptionCachePageRadius] scales
/// the prefetch radius down as `maxWidgets` grows so the subscribed window
/// stays capped (~36 participants) on large desktop grids.
class CameraGridLayoutConfig {
  /// Upper bound on participants kept subscribed in the prefetch window
  /// (current page ± nearby pages).
  static const int maxSubscriptionWindow = 36;

  /// Minimum tile width when evaluating spaced-grid presets.
  ///
  /// Higher on larger desktop windows so tiles stay readable as the grid grows.
  static double minTileWidth(double width) {
    if (!desktop) return 48;
    if (width >= ResponsiveBreakpoints.xlarge) return 160;
    if (width >= ResponsiveBreakpoints.large) return 140;
    if (width >= ResponsiveBreakpoints.medium) return 120;
    return 100;
  }

  /// Spaced-grid `[col, row]` presets for the current platform and orientation.
  static List<List<int>> configurationsFor(
    double width,
    Orientation orientation,
  ) {
    if (!desktop) {
      // Mobile — unchanged from original ResponsiveCameraLayout presets.
      return orientation == Orientation.portrait
          ? const [
              [2, 2],
              [1, 2],
              [1, 1],
            ]
          : const [
              [3, 1],
              [2, 1],
              [1, 1],
            ];
    }

    if (orientation == Orientation.portrait) {
      return _desktopPortrait(width);
    }
    return _desktopLandscape(width);
  }

  /// Same presets as [configurationsFor], reversed for last-page tightening.
  static List<List<int>> lastPageConfigurationsFor(
    double width,
    Orientation orientation,
  ) {
    return configurationsFor(width, orientation).reversed.toList();
  }

  /// Picks the largest `[col, row]` preset that fits the viewport.
  static ({int cols, int maxWidgets}) selectBest({
    required double screenWidth,
    required double screenHeight,
    required List<List<int>> configurations,
    required double minWidgetWidth,
  }) {
    for (final config in configurations) {
      final col = config[0];
      final row = config[1];
      final widgetWidth = screenWidth / col;
      final widgetHeight = screenHeight / row;

      if (widgetWidth >= minWidgetWidth && widgetHeight * row <= screenHeight) {
        return (cols: col, maxWidgets: col * row);
      }
    }
    return (cols: 1, maxWidgets: 1);
  }

  /// Last-page variant of [selectBest]; also returns the tile aspect ratio.
  static ({int cols, double ratio})? selectBestForLastPage({
    required double screenWidth,
    required double screenHeight,
    required List<List<int>> configurations,
    required double minWidgetWidth,
    required int itemCount,
  }) {
    for (final config in configurations) {
      final col = config[0];
      final row = config[1];
      if (col * row < itemCount) continue;

      final widgetWidth = screenWidth / col;
      final widgetHeight = screenHeight / row;
      if (widgetWidth >= minWidgetWidth && widgetHeight * row <= screenHeight) {
        return (cols: col, ratio: widgetWidth / widgetHeight);
      }
    }
    return null;
  }

  /// How many grid pages to prefetch before/after the current page.
  ///
  /// Window size is `(2r + 1) * maxWidgets`. Radius shrinks as tiles-per-page
  /// grows so total subscribed participants stay within [maxSubscriptionWindow].
  static int subscriptionCachePageRadius(int maxWidgets) {
    if (maxWidgets <= 0) return 0;
    if (maxWidgets > maxSubscriptionWindow) return 0;

    const maxRadius = 2;
    for (var radius = maxRadius; radius >= 0; radius--) {
      final window = (2 * radius + 1) * maxWidgets;
      if (window <= maxSubscriptionWindow) return radius;
    }
    return 0;
  }

  /// Compact-grid column/row counts for [FixedSizingCameraLayout].
  static ({int columns, int rows}) fixedSizingGrid({
    required int participantCount,
    required double width,
  }) {
    if (!desktop) {
      return (
        columns: _mobileColumnCount(participantCount),
        rows: _mobileRowCount(participantCount),
      );
    }

    final maxColumns = switch (true) {
      _ when width >= ResponsiveBreakpoints.xlarge => 5,
      _ when width >= ResponsiveBreakpoints.large => 4,
      _ when width >= ResponsiveBreakpoints.medium => 4,
      _ => 3,
    };
    final maxRows = switch (true) {
      _ when width >= ResponsiveBreakpoints.xlarge => 3,
      _ when width >= ResponsiveBreakpoints.large => 3,
      _ => 2,
    };

    if (participantCount <= 1) {
      return (columns: 1, rows: 1);
    }
    if (participantCount <= 2) {
      return (columns: maxColumns.clamp(1, 2), rows: 1);
    }
    if (participantCount <= 4) {
      return (columns: maxColumns.clamp(1, 2), rows: maxRows.clamp(1, 2));
    }
    return (columns: maxColumns, rows: maxRows);
  }

  static List<List<int>> _desktopLandscape(double width) {
    // XLarge (≥ 1500px): up to 6×3
    if (width >= ResponsiveBreakpoints.xlarge) {
      return const [
        [6, 3],
        [5, 3],
        [4, 3],
        [4, 2],
        [3, 2],
        [3, 1],
        [2, 2],
        [2, 1],
        [1, 1],
      ];
    }
    // Large (1150–1500px): up to 5×3
    if (width >= ResponsiveBreakpoints.large) {
      return const [
        [5, 3],
        [4, 3],
        [4, 2],
        [3, 2],
        [3, 1],
        [2, 2],
        [2, 1],
        [1, 1],
      ];
    }
    // Medium (1050–1150px): up to 4×2
    if (width >= ResponsiveBreakpoints.medium) {
      return const [
        [4, 2],
        [4, 1],
        [3, 2],
        [3, 1],
        [2, 2],
        [2, 1],
        [1, 1],
      ];
    }
    // Small desktop (under 1050px): up to 3×2
    return const [
      [3, 2],
      [3, 1],
      [2, 2],
      [2, 1],
      [1, 1],
    ];
  }

  static List<List<int>> _desktopPortrait(double width) {
    // XLarge (≥ 1500px): up to 3×4
    if (width >= ResponsiveBreakpoints.xlarge) {
      return const [
        [3, 4],
        [3, 3],
        [2, 3],
        [2, 2],
        [1, 2],
        [1, 1],
      ];
    }
    // Large (1150–1500px): up to 3×3
    if (width >= ResponsiveBreakpoints.large) {
      return const [
        [3, 3],
        [2, 3],
        [2, 2],
        [1, 2],
        [1, 1],
      ];
    }
    // Medium (1050–1150px): up to 2×3
    if (width >= ResponsiveBreakpoints.medium) {
      return const [
        [2, 3],
        [2, 2],
        [1, 2],
        [1, 1],
      ];
    }
    // Small desktop (under 1050px): up to 2×2
    return const [
      [2, 2],
      [1, 2],
      [1, 1],
    ];
  }

  static int _mobileColumnCount(int total) {
    if (total <= 1) return 1;
    if (total <= 4) return 2;
    return 3;
  }

  static int _mobileRowCount(int total) {
    if (total <= 2) return 1;
    return 2;
  }
}
