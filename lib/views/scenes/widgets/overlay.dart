import 'package:flutter/material.dart';

/// Where the popover should appear relative to the target.
enum OverlayPlacement {
  topLeft,
  topCenter,
  topRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Controller so you can close programmatically if needed.
class OverlayPopoverController {
  OverlayEntry? _entry;

  bool get isShown => _entry != null;

  void show(BuildContext context, OverlayEntry entry) {
    hide();
    _entry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void hide() {
    _entry?.remove();
    _entry = null;
  }
}

/// A helper to create and manage a popover overlay positioned near a target widget.
class OverlayPopover {
  OverlayPopover({
    required this.targetKey,
    required this.builder,
    this.width = 320,
    this.maxHeightFraction = 0.6,
    this.placement = OverlayPlacement.topCenter,
    this.autoFlipIfNoSpace = true,
    this.horizontalScreenPadding = 16,
    this.verticalGap = 8,
    this.dismissOnBarrierTap = true,
    this.barrierColor = const Color(0x4D000000), // 30% black
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.decorationColor,
  });

  final GlobalKey targetKey;
  final WidgetBuilder builder;

  /// Fixed width of the popover (will be clamped if near screen edge).
  final double width;

  /// Max height as a fraction of the screen height.
  final double maxHeightFraction;

  /// Initial desired placement relative to the target.
  final OverlayPlacement placement;

  /// If true, flip above/below automatically when there isn’t enough room.
  final bool autoFlipIfNoSpace;

  /// Screen padding to keep the popover inside left/right edges.
  final double horizontalScreenPadding;

  /// Gap between target and popover.
  final double verticalGap;

  /// Close when tapping the barrier.
  final bool dismissOnBarrierTap;

  /// Barrier (background) color.
  final Color barrierColor;

  /// Popover styling
  final BorderRadius borderRadius;
  final Color? decorationColor;

  /// Show and return the controller so you can close later.
  OverlayPopoverController show(BuildContext context) {
    final controller = OverlayPopoverController();
    final entry = _createOverlayEntry(context, controller);
    controller.show(context, entry);
    return controller;
  }

  OverlayEntry _createOverlayEntry(
    BuildContext context,
    OverlayPopoverController controller,
  ) {
    final overlayContext = Overlay.of(context).context;
    final mediaQuery = MediaQuery.of(overlayContext);
    final screenSize = mediaQuery.size;
    final maxHeight = screenSize.height * maxHeightFraction;

    // Resolve target position/size
    final renderBox =
        targetKey.currentContext?.findRenderObject() as RenderBox?;
    final targetOffset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final targetSize = renderBox?.size ?? Size.zero;
    final targetRect = Rect.fromLTWH(
      targetOffset.dx,
      targetOffset.dy,
      targetSize.width,
      targetSize.height,
    );

    // Decide vertical placement (flip if needed)
    final wantsTop = _isTop(placement);
    final hasSpaceAbove =
        targetRect.top >= (maxHeight + verticalGap + mediaQuery.padding.top);
    final hasSpaceBelow =
        (screenSize.height - targetRect.bottom) >=
        (maxHeight + verticalGap + mediaQuery.padding.bottom);

    OverlayPlacement finalPlacement = placement;
    if (autoFlipIfNoSpace) {
      if (wantsTop && !hasSpaceAbove && hasSpaceBelow) {
        finalPlacement = _flipVertical(placement);
      } else if (!wantsTop && !hasSpaceBelow && hasSpaceAbove) {
        finalPlacement = _flipVertical(placement);
      }
    }

    // Compute left based on horizontal alignment
    double desiredLeft;
    switch (_horizontal(finalPlacement)) {
      case _HorizAlign.left:
        desiredLeft = targetRect.left;
      case _HorizAlign.center:
        desiredLeft = targetRect.left + (targetRect.width - width) / 2;
      case _HorizAlign.right:
        desiredLeft = targetRect.right - width;
    }

    // Clamp width and left to avoid horizontal overflow
    final maxWidth = screenSize.width - 2 * horizontalScreenPadding;
    final clampedWidth = width.clamp(0.0, maxWidth);
    double left = desiredLeft;
    if (left < horizontalScreenPadding) {
      left = horizontalScreenPadding;
    }
    if (left + clampedWidth > screenSize.width - horizontalScreenPadding) {
      left = screenSize.width - horizontalScreenPadding - clampedWidth;
    }

    // Compute top using maxHeight as an upper bound (actual child may be smaller)
    double top;
    if (_isTop(finalPlacement)) {
      // Try to place above; clamp to keep on screen
      top = (targetRect.top - verticalGap - maxHeight).clamp(
        mediaQuery.padding.top + horizontalScreenPadding,
        targetRect.top - verticalGap,
      );
    } else {
      // Place below; clamp to keep on screen
      top = (targetRect.bottom + verticalGap).clamp(
        targetRect.bottom + verticalGap,
        screenSize.height -
            mediaQuery.padding.bottom -
            horizontalScreenPadding -
            maxHeight,
      );
    }

    final bgColor =
        decorationColor ?? Theme.of(overlayContext).colorScheme.surface;

    return OverlayEntry(
      builder: (ctx) {
        // Important: keep a handle so controller can insert this entry
        (OverlayEntry)
            .toString(); // no-op; just to keep analyzer calm about ctx usage
        return GestureDetector(
          // barrier tap to dismiss
          onTap: dismissOnBarrierTap ? controller.hide : null,
          behavior: HitTestBehavior.translucent,
          child: ColoredBox(
            color: barrierColor,
            child: Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  child: GestureDetector(
                    onTap: () {}, // absorb taps
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: clampedWidth,
                        maxHeight: maxHeight,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 20,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: borderRadius,
                          ),
                          child: SingleChildScrollView(
                            child: builder(overlayContext),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static bool _isTop(OverlayPlacement p) {
    switch (p) {
      case OverlayPlacement.topLeft:
      case OverlayPlacement.topCenter:
      case OverlayPlacement.topRight:
        return true;
      default:
        return false;
    }
  }

  static OverlayPlacement _flipVertical(OverlayPlacement p) {
    switch (p) {
      case OverlayPlacement.topLeft:
        return OverlayPlacement.bottomLeft;
      case OverlayPlacement.topCenter:
        return OverlayPlacement.bottomCenter;
      case OverlayPlacement.topRight:
        return OverlayPlacement.bottomRight;
      case OverlayPlacement.bottomLeft:
        return OverlayPlacement.topLeft;
      case OverlayPlacement.bottomCenter:
        return OverlayPlacement.topCenter;
      case OverlayPlacement.bottomRight:
        return OverlayPlacement.topRight;
    }
  }

  static _HorizAlign _horizontal(OverlayPlacement p) {
    switch (p) {
      case OverlayPlacement.topLeft:
      case OverlayPlacement.bottomLeft:
        return _HorizAlign.left;
      case OverlayPlacement.topCenter:
      case OverlayPlacement.bottomCenter:
        return _HorizAlign.center;
      case OverlayPlacement.topRight:
      case OverlayPlacement.bottomRight:
        return _HorizAlign.right;
    }
  }
}

enum _HorizAlign { left, center, right }

// /// ----------------------
// /// Usage example widget:
// /// ----------------------
// class ExamplePopoverButton extends StatefulWidget {
//   const ExamplePopoverButton({super.key});

//   @override
//   State<ExamplePopoverButton> createState() => _ExamplePopoverButtonState();
// }

// class _ExamplePopoverButtonState extends State<ExamplePopoverButton> {
//   final GlobalKey _buttonKey = GlobalKey();
//   OverlayPopoverController? _controller;

//   @override
//   Widget build(BuildContext context) {
//     return ElevatedButton(
//       key: _buttonKey,
//       onPressed: _togglePopover,
//       child: const Text('Show Popover'),
//     );
//   }

//   void _togglePopover() {
//     if (_controller?.isShown == true) {
//       _controller?.hide();
//       _controller = null;
//       return;
//     }

//     final popover = OverlayPopover(
//       targetKey: _buttonKey,
//       // Pops on TOP by default. Change placement as needed:
//       placement: OverlayPlacement.topCenter,
//       autoFlipIfNoSpace: true,
//       width: 320,
//       maxHeightFraction: 0.6,
//       builder: (ctx) {
//         return Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: const [
//             Text(
//               'Popover Title',
//               style: TextStyle(fontWeight: FontWeight.bold),
//             ),
//             SizedBox(height: 8),
//             Text('This content scrolls if it exceeds max height.'),
//             SizedBox(height: 8),
//             Text('Add any widgets you like here.'),
//           ],
//         );
//       },
//     );

//     _controller = popover.show(context);
//   }

//   @override
//   void dispose() {
//     _controller?.hide();
//     super.dispose();
//   }
// }
