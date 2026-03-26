import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

/// A visual handle bar indicator for bottom sheets with optional drag support.
///
/// This widget displays a small rounded bar at the top of a bottom sheet to
/// indicate that the sheet can be dragged. It provides a visual affordance for
/// users to interact with draggable bottom sheets.
///
/// The handle bar can be used in two modes:
/// 1. **Visual indicator only**: When no drag callbacks are provided, it serves
///    as a passive visual indicator that the sheet is draggable.
/// 2. **Interactive drag handle**: When drag callbacks are provided, it becomes
///    an active drag target that responds to vertical drag gestures.
///
/// ## Usage
///
/// ### Simple visual indicator (no drag handling):
/// ```dart
/// BottomSheetHandleBar()
/// ```
///
/// ### Interactive drag handle:
/// ```dart
/// BottomSheetHandleBar(
///   onDragUpdate: (dy) {
///     // Handle drag updates
///     // dy > 0 means dragging down, dy < 0 means dragging up
///     updateSheetPosition(dy);
///   },
///   onDragEnd: () {
///     // Handle drag completion
///     snapToNearestPosition();
///   },
/// )
/// ```
class BottomSheetHandleBar extends StatelessWidget {
  const BottomSheetHandleBar({
    this.onDragUpdate,
    this.onDragEnd,
    this.padding,
    super.key,
  });

  /// Callback invoked during vertical drag gestures.
  ///
  /// The "dy" parameter represents the vertical drag delta:
  /// - Positive values indicate dragging downward
  /// - Negative values indicate dragging upward
  ///
  /// This callback is called continuously as the user drags the handle.
  final ValueChanged<double>? onDragUpdate;

  /// Callback invoked when the drag gesture ends.
  ///
  /// This is typically used to snap the sheet to a specific position or
  /// determine whether to fully expand or collapse based on the final drag
  /// position.
  final VoidCallback? onDragEnd;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    // Build the visual handle bar container
    Widget handleBar = Container(
      width: double.infinity,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Visual handle bar indicator - small rounded rectangle
          Container(
            width: 32,
            height: 4,
            decoration: ShapeDecoration(
              color: context.colors.white.withValues(alpha: 0.16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
        ],
      ),
    );

    // Conditionally wrap with GestureDetector to enable drag functionality
    // Only add gesture detection if at least one drag callback is provided
    if (onDragUpdate != null || onDragEnd != null) {
      handleBar = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerUp: (_) {
          onDragEnd?.call();
        },
        onPointerCancel: (_) {
          onDragEnd?.call();
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Start the drag gesture to ensure it's properly recognized
          // This is crucial for the drag end callback to fire
          onVerticalDragUpdate: onDragUpdate != null
              ? (d) {
                  onDragUpdate!(d.delta.dy);
                }
              : null,
          onVerticalDragEnd: onDragEnd != null
              ? (details) {
                  onDragEnd!();
                }
              : null,
          onVerticalDragCancel: onDragEnd != null
              ? () {
                  onDragEnd!();
                }
              : null,

          child: handleBar,
        ),
      );
    }

    return handleBar;
  }
}
