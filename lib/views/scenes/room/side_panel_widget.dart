import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';

import 'room_bloc.dart';

class SidePanelOrSheet extends StatefulWidget {
  const SidePanelOrSheet({
    required this.child,
    required this.isScreenSharing,
    required this.isCameraView,
    required this.maxWidth,
    this.onDismissed,
    super.key,
  });

  final Widget child;
  final bool isScreenSharing;
  final bool isCameraView;
  final VoidCallback? onDismissed;
  final double maxWidth;

  @override
  State<SidePanelOrSheet> createState() => _SidePanelOrSheetState();
}

class _SidePanelOrSheetState extends State<SidePanelOrSheet> {
  bool _sheetOpen = false;

  bool get _isMobile => mobile;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleEnsureSheetState();
  }

  @override
  void didUpdateWidget(covariant SidePanelOrSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasStateChange =
        oldWidget.isScreenSharing != widget.isScreenSharing ||
        oldWidget.isCameraView != widget.isCameraView;

    if (hasStateChange) {
      _scheduleEnsureSheetState();
    }
  }

  void _scheduleEnsureSheetState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureSheetState();
    });
  }

  void _ensureSheetState() {
    // Mobile -> ensure bottom sheet is open
    if (_isMobile && !_sheetOpen) {
      _openBottomSheet();
      return;
    }

    // Desktop/Web -> ensure bottom sheet is closed if we previously opened it
    if (!_isMobile && _sheetOpen) {
      Navigator.of(context, rootNavigator: true).maybePop();
      widget.onDismissed?.call();
      _sheetOpen = false;
    }
  }

  double _calculateMaxHeight(bool isLandscape, double screenHeight) {
    return isLandscape ? screenHeight : screenHeight * 0.84;
  }

  Future<void> _openBottomSheet() async {
    // Extra safety: if platform changed to non-mobile between scheduling and now
    if (!_isMobile || _sheetOpen) return;

    _sheetOpen = true;

    final roomBloc = context.read<RoomBloc>();
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: !isLandscape,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final builderMedia = MediaQuery.of(ctx);
        final builderIsLandscape =
            builderMedia.size.width > builderMedia.size.height;
        final maxHeight = _calculateMaxHeight(
          builderIsLandscape,
          builderMedia.size.height,
        );

        return BlocProvider.value(
          value: roomBloc,
          child: _RoundedDraggableSheet(
            maxHeight: maxHeight,
            maxWidth: widget.maxWidth,
            isLandscape: builderIsLandscape,
            child: widget.child,
          ),
        );
      },
    ).whenComplete(() {
      // When sheet is closed in any way
      if (!mounted) {
        _sheetOpen = false;
        return;
      }
      setState(() {
        _sheetOpen = false;
      });
      widget.onDismissed?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMobile) {
      final shouldExpand = widget.isScreenSharing && !widget.isCameraView;
      return Padding(
        padding: EdgeInsets.only(
          top: shouldExpand ? 0 : 12,
          right: 8,
          bottom: 12,
        ),
        child: widget.child,
      );
    }

    // On mobile we render nothing; content lives inside the bottom sheet.
    return const SizedBox.shrink();
  }
}

class _RoundedDraggableSheet extends StatelessWidget {
  const _RoundedDraggableSheet({
    required this.child,
    required this.maxHeight,
    required this.isLandscape,
    required this.maxWidth,
  });

  final Widget child;
  final double maxHeight;
  final double maxWidth;
  final bool isLandscape;

  BoxDecoration _buildDecoration(BuildContext context) {
    return BoxDecoration(
      color: context.colors.clear,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    );
  }

  Widget _buildSheetContent(BuildContext context) {
    final decoration = _buildDecoration(context);

    if (isLandscape) {
      return Container(
        height: maxHeight,
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Material(
          color: Colors.transparent,
          child: DecoratedBox(decoration: decoration, child: child),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: maxWidth),
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: decoration,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Expanded(child: child)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final childSize = isLandscape ? 1.0 : 0.95;
    final minSize = isLandscape ? 0.5 : 0.3;

    return GestureDetector(
      // Allow barrier taps to pass through when tapping outside the sheet
      behavior: HitTestBehavior.translucent,
      onTap: () {
        // This allows taps outside the sheet content to dismiss
        Navigator.of(context).pop();
      },
      child: DraggableScrollableSheet(
        initialChildSize: childSize,
        minChildSize: minSize,
        maxChildSize: childSize,
        builder: (ctx, controller) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              // Prevent taps inside the sheet from dismissing
              onTap: () {},
              child: _buildSheetContent(context),
            ),
          );
        },
      ),
    );
  }
}
