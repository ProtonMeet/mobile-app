import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/core/responsive_v2.dart';

import 'room_bloc.dart';

/// Which room auxiliary panel is open (participants, chat, settings, info).
enum RoomSidePanel { participants, chat, settings, meetingInfo }

/// Minimum width to show room panels beside main content instead of a bottom sheet.
bool roomSidePanelUsesSideRail(double width) =>
    width >= ResponsiveBreakpoints.medium;

/// Shared width for room side panels / sheets.
const double roomSidePanelWidth = 380;

/// Shared layout tokens for room side-rail / bottom-sheet panel chrome.
abstract final class RoomSidePanelLayout {
  RoomSidePanelLayout._();

  /// Pinned panel title row height (excludes handle bar inset).
  static const double headerHeight = 36.0;

  /// Space below the title inside the pinned header blur.
  static const double headerBottomPadding = 12.0;

  static const double horizontalPadding = 24.0;
  static const double borderRadiusMedium = 24.0;
  static const double borderRadiusLarge = 40.0;
}

const Duration _roomSideRailAnimationDuration = Duration(milliseconds: 300);
const Curve _roomSideRailAnimationCurve = Curves.easeInOutCubic;

/// Animates the desktop side rail open/close and cross-fades panel switches.
class RoomAnimatedSideRail extends StatefulWidget {
  const RoomAnimatedSideRail({
    required this.isOpen,
    required this.panel,
    required this.panelWidth,
    required this.child,
    super.key,
  });

  final bool isOpen;
  final RoomSidePanel? panel;
  final double panelWidth;
  final Widget child;

  @override
  State<RoomAnimatedSideRail> createState() => _RoomAnimatedSideRailState();
}

class _RoomAnimatedSideRailState extends State<RoomAnimatedSideRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sizeAnimation;
  late final Animation<double> _fadeAnimation;

  Widget? _displayChild;
  RoomSidePanel? _displayPanel;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _roomSideRailAnimationDuration,
    );
    _sizeAnimation = CurvedAnimation(
      parent: _controller,
      curve: _roomSideRailAnimationCurve,
      reverseCurve: _roomSideRailAnimationCurve,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
      reverseCurve: const Interval(0.2, 1.0, curve: Curves.easeIn),
    );
    if (widget.isOpen) {
      _displayChild = widget.child;
      _displayPanel = widget.panel;
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant RoomAnimatedSideRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen) {
      _displayChild = widget.child;
      _displayPanel = widget.panel;
      if (!oldWidget.isOpen || _controller.status == AnimationStatus.reverse) {
        _controller.forward();
      }
      return;
    }

    if (oldWidget.isOpen) {
      unawaited(
        _controller.reverse().whenComplete(() {
          if (!mounted || widget.isOpen) {
            return;
          }
          setState(() {
            _displayChild = null;
            _displayPanel = null;
          });
        }),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final panelWidth = widget.panelWidth.clamp(320.0, roomSidePanelWidth);
    const railPadding = 8.0;
    final fullWidth = panelWidth + railPadding;
    final child = _displayChild;

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final progress = _sizeAnimation.value;
            final slotWidth = fullWidth * progress;

            if (child == null || progress == 0) {
              return SizedBox(width: slotWidth, height: height);
            }

            // Outer slot width animates; panel lays out at fixed [fullWidth]
            // via [OverflowBox] and is clipped (no reflow / shrink).
            return SizedBox(
              width: slotWidth,
              height: height,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerRight,
                  minWidth: fullWidth,
                  maxWidth: fullWidth,
                  minHeight: height,
                  maxHeight: height,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SizedBox(
                      width: fullWidth,
                      height: height,
                      child: Padding(
                        padding: const EdgeInsets.only(right: railPadding),
                        child: SizedBox(
                          width: panelWidth,
                          height: height,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            layoutBuilder: (currentChild, previousChildren) {
                              return Stack(
                                alignment: Alignment.topCenter,
                                children: [...previousChildren, ?currentChild],
                              );
                            },
                            transitionBuilder: (switchChild, animation) {
                              final slide = Tween<Offset>(
                                begin: const Offset(0.04, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: slide,
                                  child: switchChild,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey(_displayPanel),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Room panel sheets opened via [SidePanelOrSheet]. Tracked globally because
/// switching Row ↔ Column on resize recreates the panel [State] while the route
/// can remain on the root navigator.
int _roomPanelSheetRouteCount = 0;

/// Pops a room panel bottom sheet from the root navigator when still visible
/// after a layout breakpoint change.
void dismissRoomPanelBottomSheetIfPresent() {
  if (_roomPanelSheetRouteCount <= 0) return;
  final navigator = Coordinator.rootNavigatorKey.currentState;
  if (navigator != null && navigator.canPop()) {
    navigator.pop();
  }
}

/// Layout hints for room panel content embedded in [SidePanelOrSheet].
///
/// - [showSheetHeader]: pinned title row (Participants, Chat, etc.)
/// - [showHandleBar]: [BottomSheetHandleBar] drag handle above the title
class RoomSidePanelScope extends InheritedWidget {
  const RoomSidePanelScope({
    required this.showSheetHeader,
    required this.showHandleBar,
    required super.child,
    super.key,
  });

  final bool showSheetHeader;
  final bool showHandleBar;

  static bool showSheetHeaderOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<RoomSidePanelScope>()
            ?.showSheetHeader ??
        true;
  }

  static bool showHandleBarOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<RoomSidePanelScope>()
            ?.showHandleBar ??
        true;
  }

  @override
  bool updateShouldNotify(RoomSidePanelScope oldWidget) =>
      showSheetHeader != oldWidget.showSheetHeader ||
      showHandleBar != oldWidget.showHandleBar;
}

/// Top inset above a panel title (handle row in sheets, compact padding in rail).
double roomSidePanelHeaderTopInset({
  required bool isLandscape,
  required bool showHandleBar,
  bool showSheetHeader = true,
}) {
  if (!showSheetHeader) return 0;
  if (isLandscape) return 8.0;
  return showHandleBar ? 36.0 : 24.0;
}

/// Total pinned header height for panel scroll views.
double roomSidePanelToolbarHeight({
  required double titleHeight,
  required bool isLandscape,
  required bool showHandleBar,
  required bool showSheetHeader,
}) {
  if (!showSheetHeader) return 0;
  return titleHeight +
      roomSidePanelHeaderTopInset(
        isLandscape: isLandscape,
        showHandleBar: showHandleBar,
        showSheetHeader: showSheetHeader,
      );
}

/// Shared scroll shell for room side panels (info, settings, participants, chat).
///
/// Wraps [BaseBottomSheetV2.withPinnedSliverScroll] with [RoomSidePanelLayout]
/// tokens, pinned header chrome, and optional [footer] (e.g. chat input).
class RoomSidePanelScroll extends StatelessWidget {
  const RoomSidePanelScroll({
    required this.header,
    required this.slivers,
    this.scrollController,
    this.footer,
    this.fillHeight = true,
    this.headerBlurSigma = 14,
    super.key,
  });

  final Widget header;
  final List<Widget> slivers;
  final ScrollController? scrollController;
  final Widget? footer;

  /// When false, height follows content + [footer] (mobile chat sheet).
  final bool fillHeight;

  /// Blur strength for the pinned header [BackdropFilter].
  final double headerBlurSigma;

  @override
  Widget build(BuildContext context) {
    final isLandscape = context.isLandscape && mobile;
    final showSheetHeader = RoomSidePanelScope.showSheetHeaderOf(context);
    final showHandleBar = RoomSidePanelScope.showHandleBarOf(context);
    final headerTopInset = roomSidePanelHeaderTopInset(
      isLandscape: isLandscape,
      showHandleBar: showHandleBar,
      showSheetHeader: showSheetHeader,
    );
    final headerHeight = roomSidePanelToolbarHeight(
      titleHeight: RoomSidePanelLayout.headerHeight,
      isLandscape: isLandscape,
      showHandleBar: showHandleBar,
      showSheetHeader: showSheetHeader,
    );

    const shellRadius = BorderRadius.all(
      Radius.circular(RoomSidePanelLayout.borderRadiusLarge),
    );

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.deferToChild,
      child: BaseBottomSheetV2.withPinnedSliverScroll(
        isLandscape: isLandscape,
        showPinnedHeader: showSheetHeader,
        toolbarHeight: headerHeight,
        scrollController: scrollController,
        bottomPadding: 0,
        borderColor: context.colors.appBorderNorm,
        shellBorderRadius: shellRadius,
        fillHeight: fillHeight,
        headerOuterCornerRadius: RoomSidePanelLayout.borderRadiusLarge,
        headerBlurSigma: headerBlurSigma,
        innerEnableHandleDragPassthrough: showSheetHeader && showHandleBar,
        flexibleSpaceChild: _RoomSidePanelHeaderSpace(
          headerTopInset: headerTopInset,
          headerHeight: headerHeight,
          child: header,
        ),
        headerVisualOverlay: showSheetHeader && showHandleBar
            ? _RoomSidePanelHeaderOverlay(
                isLandscape: isLandscape,
                headerTopInset: headerTopInset,
                header: header,
              )
            : null,
        footer: footer,
        slivers: slivers,
      ),
    );
  }
}

class _RoomSidePanelHeaderSpace extends StatelessWidget {
  const _RoomSidePanelHeaderSpace({
    required this.headerTopInset,
    required this.headerHeight,
    required this.child,
  });

  final double headerTopInset;
  final double headerHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: headerHeight,
      padding: EdgeInsets.only(
        left: RoomSidePanelLayout.horizontalPadding,
        right: RoomSidePanelLayout.horizontalPadding,
        bottom: RoomSidePanelLayout.headerBottomPadding,
        top: headerTopInset,
      ),
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }
}

class _RoomSidePanelHeaderOverlay extends StatelessWidget {
  const _RoomSidePanelHeaderOverlay({
    required this.isLandscape,
    required this.headerTopInset,
    required this.header,
  });

  final bool isLandscape;
  final double headerTopInset;
  final Widget header;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (!isLandscape)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 36.0,
            child: BottomSheetHandleBar(),
          ),
        Positioned(
          top: headerTopInset,
          left: 0,
          right: 0,
          height: RoomSidePanelLayout.headerHeight,
          child: Container(
            padding: const EdgeInsets.only(
              left: RoomSidePanelLayout.horizontalPadding,
              right: RoomSidePanelLayout.horizontalPadding,
              bottom: RoomSidePanelLayout.headerBottomPadding,
            ),
            child: Align(alignment: Alignment.centerLeft, child: header),
          ),
        ),
      ],
    );
  }
}

/// Hosts room auxiliary panels (participants, chat, settings, info).
///
/// - **Wide** ([ResponsiveBreakpoints.medium]+): fixed-width rail beside main
///   content (parent must use a [Row] with [Expanded] main area).
/// - **Narrow**: modal bottom sheet (same as mobile).
class SidePanelOrSheet extends StatefulWidget {
  const SidePanelOrSheet({
    required this.child,
    required this.isScreenSharing,
    required this.isCameraView,
    required this.maxWidth,
    this.onDismissed,
    this.sheetBlocProviders = const [],
    super.key,
  });

  final Widget child;
  final bool isScreenSharing;
  final bool isCameraView;
  final VoidCallback? onDismissed;
  final double maxWidth;

  /// Extra blocs replayed into the modal bottom sheet route (narrow layout).
  /// The sheet builder only inherits [RoomBloc] unless these are provided.
  final List<BlocProvider> sheetBlocProviders;

  @override
  State<SidePanelOrSheet> createState() => _SidePanelOrSheetState();
}

class _SidePanelOrSheetState extends State<SidePanelOrSheet> {
  bool _sheetOpen = false;
  bool _closingSheetForLayoutSwitch = false;

  bool _useSideRail(BuildContext context) =>
      roomSidePanelUsesSideRail(MediaQuery.sizeOf(context).width);

  void _dismissBottomSheet({required bool forLayoutSwitch}) {
    _closingSheetForLayoutSwitch = forLayoutSwitch;

    if (_sheetOpen) {
      final navigator = Coordinator.rootNavigatorKey.currentState;
      navigator?.pop();
      return;
    }

    if (forLayoutSwitch) {
      dismissRoomPanelBottomSheetIfPresent();
    }
  }

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
    if (_useSideRail(context)) {
      _dismissBottomSheet(forLayoutSwitch: true);
      return;
    }

    if (!_sheetOpen) {
      _openBottomSheet();
    }
  }

  double _calculateMaxHeight(bool isLandscape, double screenHeight) {
    return isLandscape ? screenHeight : screenHeight * 0.84;
  }

  Future<void> _openBottomSheet() async {
    if (_useSideRail(context) || _sheetOpen) return;

    _sheetOpen = true;
    _roomPanelSheetRouteCount++;

    final rootContext = Coordinator.rootNavigatorKey.currentContext;
    if (rootContext == null) {
      _sheetOpen = false;
      _roomPanelSheetRouteCount = (_roomPanelSheetRouteCount - 1).clamp(0, 999);
      return;
    }

    final roomBloc = context.read<RoomBloc>();
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;

    await showModalBottomSheet<void>(
      context: rootContext,
      useRootNavigator: true,
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

        return MultiBlocProvider(
          providers: [
            BlocProvider<RoomBloc>.value(value: roomBloc),
            ...widget.sheetBlocProviders,
          ],
          child: RoomSidePanelScope(
            showSheetHeader: true,
            showHandleBar: true,
            child: _RoundedDraggableSheet(
              maxHeight: maxHeight,
              maxWidth: widget.maxWidth,
              isLandscape: builderIsLandscape,
              child: widget.child,
            ),
          ),
        );
      },
    ).whenComplete(() {
      _roomPanelSheetRouteCount = (_roomPanelSheetRouteCount - 1).clamp(0, 999);
      if (!mounted) {
        _sheetOpen = false;
        _closingSheetForLayoutSwitch = false;
        return;
      }
      setState(() {
        _sheetOpen = false;
      });
      final closedForLayoutSwitch = _closingSheetForLayoutSwitch;
      _closingSheetForLayoutSwitch = false;
      if (!closedForLayoutSwitch) {
        widget.onDismissed?.call();
      }
    });
  }

  Widget _buildSideRail(BuildContext context) {
    final panelWidth = widget.maxWidth.clamp(320.0, roomSidePanelWidth);

    return SizedBox(
      width: panelWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(color: context.colors.clear),
        child: ClipRRect(
          child: SizedBox(
            width: panelWidth,
            height: double.infinity,
            child: RoomSidePanelScope(
              showSheetHeader: true,
              showHandleBar: false,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_useSideRail(context)) {
      return _buildSideRail(context);
    }

    // Narrow layout: panel content lives inside the bottom sheet.
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
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(RoomSidePanelLayout.borderRadiusLarge),
      ),
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
      behavior: HitTestBehavior.translucent,
      onTap: () => Navigator.of(context).pop(),
      child: DraggableScrollableSheet(
        initialChildSize: childSize,
        minChildSize: minSize,
        maxChildSize: childSize,
        builder: (ctx, controller) {
          return Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: _buildSheetContent(context),
            ),
          );
        },
      ),
    );
  }
}
