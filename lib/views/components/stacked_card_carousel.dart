// fork reference, credit: https://github.com/grihlo/stacked_card_carousel
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:meet/constants/constants.dart';

enum StackedCardCarouselType { cardsStack, fadeOutStack }

typedef OnPageChanged = void Function(int pageIndex);

typedef StackedCardCarouselItemBuilder =
    Widget Function(
      BuildContext context,
      VoidCallback onClose, {
      required bool isActive,
    });

class StackedCardCarouselItem {
  const StackedCardCarouselItem({required this.id, required this.builder});

  final String id;
  final StackedCardCarouselItemBuilder builder;
}

class StackedCardCarousel extends StatefulWidget {
  StackedCardCarousel({
    required List<StackedCardCarouselItem> items,
    super.key,
    StackedCardCarouselType type = StackedCardCarouselType.cardsStack,
    double initialOffset = 40.0,
    double spaceBetweenItems = 400,
    int? initialPage,
    bool scrollEnabled = true,
    PageController? pageController,
    OnPageChanged? onPageChanged,
    ValueChanged<String>? onItemDismissed,
  }) : assert(items.isNotEmpty),
       _items = items,
       _type = type,
       _initialOffset = initialOffset,
       _spaceBetweenItems = spaceBetweenItems,
       _initialPage = _resolveInitialPage(initialPage, items.length),
       _scrollEnabled = scrollEnabled,
       _pageController = pageController,
       _onPageChanged = onPageChanged,
       _onItemDismissed = onItemDismissed;

  final List<StackedCardCarouselItem> _items;
  final StackedCardCarouselType _type;
  final double _initialOffset;
  final double _spaceBetweenItems;
  final int _initialPage;
  final bool _scrollEnabled;
  final PageController? _pageController;
  final OnPageChanged? _onPageChanged;
  final ValueChanged<String>? _onItemDismissed;

  static int _resolveInitialPage(int? initialPage, int length) {
    final fallback = length - 1; // latest
    final resolved = initialPage ?? fallback;
    if (resolved < 0) return 0;
    if (resolved >= length) return length - 1;
    return resolved;
  }

  @override
  State<StackedCardCarousel> createState() => _StackedCardCarouselState();
}

class _StackedCardCarouselState extends State<StackedCardCarousel>
    with SingleTickerProviderStateMixin {
  late final PageController _controller =
      widget._pageController ??
      PageController(initialPage: widget._initialPage);
  double _pageValue = 0.0;
  int _activeIndex = 0;

  final Set<String> _dismissedIds = <String>{};
  late List<StackedCardCarouselItem> _displayItems = List.of(
    widget._items.where((e) => !_dismissedIds.contains(e.id)),
  );
  String? _removingId;

  late final AnimationController _removeController = AnimationController(
    vsync: this,
    duration: defaultAnimationDuration,
  );
  late final Animation<double> _removeOpacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 70,
    ),
    TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 30),
  ]).animate(_removeController);
  late final Animation<double> _removeSize = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 70),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 30,
    ),
  ]).animate(_removeController);

  void _onScroll() {
    if (!mounted) return;
    final p = _controller.page;
    if (p == null) return;
    setState(() {
      _pageValue = p;
      _activeIndex = p.round().clamp(0, _displayItems.length - 1);
    });
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    // Initialize with initialPage so first build is stable.
    _pageValue = _controller.initialPage.toDouble();
    _activeIndex = _controller.initialPage.clamp(0, _displayItems.length - 1);
  }

  @override
  void didUpdateWidget(covariant StackedCardCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_removingId != null) {
      // While removing, keep existing display list until removal completes.
      return;
    }

    // Keep locally dismissed items hidden even if parent rebuilds with same list.
    final newItems = widget._items
        .where((e) => !_dismissedIds.contains(e.id))
        .toList();

    final oldIds = oldWidget._items.map((e) => e.id).toSet();
    final newIds = widget._items.map((e) => e.id).toSet();
    final removedIds = oldIds.difference(newIds).toList();

    if (removedIds.isNotEmpty) {
      // Parent removed an item; animate it out using oldWidget.
      final id = removedIds.first;
      final removedItem = oldWidget._items.firstWhere(
        (e) => e.id == id,
        orElse: () => oldWidget._items.first,
      );
      final oldIndex = oldWidget._items.indexWhere((e) => e.id == id);
      _displayItems = List.of(newItems);
      final insertAt = oldIndex.clamp(0, _displayItems.length);
      _displayItems.insert(insertAt, removedItem);
      _startRemove(id, indexHint: insertAt, notifyParent: false);
    } else {
      _displayItems = List.of(newItems);
    }

    // Keep active index in range.
    if (_displayItems.isNotEmpty) {
      final maxIdx = _displayItems.length - 1;
      if (_activeIndex > maxIdx) {
        _activeIndex = maxIdx;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _controller.jumpToPage(_activeIndex);
        });
      }
    }
  }

  int _targetPageDuringRemoval(int removingIndex) {
    final n = _displayItems.length;
    if (n <= 1) return 0;

    // If you remove something at/before the current active page, the logical page
    // after removal shifts up by 1.
    final shift = removingIndex <= _activeIndex ? 1 : 0;

    // Page we want to animate to while the card is shrinking/fading.
    final target = (_activeIndex - shift).clamp(0, n - 1);
    return target;
  }

  Future<void> _startRemove(
    String id, {
    required int indexHint,
    required bool notifyParent,
  }) async {
    if (_removingId != null) return;

    final removingIndex = indexHint.clamp(0, _displayItems.length - 1);
    final targetPage = _targetPageDuringRemoval(removingIndex);

    setState(() {
      _removingId = id;

      // Optional: update active index immediately so "isActive" switches while animating.
      // This helps if your card UI changes when active.
      _activeIndex = targetPage.clamp(0, _displayItems.length - 1);
    });

    // Run BOTH animations at the same time.
    final futures = <Future<void>>[
      _removeController.forward(from: 0),

      // Drive the stacked layout to the next card during removal.
      // (This is what makes the "behind card moves to top" happen simultaneously.)
      _controller.animateToPage(
        targetPage,
        duration:
            _removeController.duration ?? const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    ];

    // If animateToPage can't run (rare), don’t fail the removal animation.
    try {
      await Future.wait(futures);
    } catch (_) {
      await _removeController.forward(from: 0);
    }

    if (!mounted) return;

    setState(() {
      _displayItems.removeWhere((e) => e.id == id);
      _removingId = null;
    });

    _removeController.reset();

    // Keep it hidden even if parent rebuilds before removing from its state.
    _dismissedIds.add(id);

    // Keep active index in range after list shrink.
    if (_displayItems.isNotEmpty) {
      _activeIndex = _activeIndex.clamp(0, _displayItems.length - 1);
    } else {
      _activeIndex = 0;
    }

    // Only AFTER both animations finish, notify parent to remove from its state.
    if (notifyParent) {
      widget._onItemDismissed?.call(id);
    }
  }

  void _requestDismiss(String id) {
    if (_removingId != null) return;
    final idx = _displayItems.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    _startRemove(id, indexHint: idx, notifyParent: true);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _removeController.dispose();
    if (widget._pageController == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClickThroughStack(
      children: <Widget>[
        IgnorePointer(
          ignoring: _removingId != null,
          child: _stackedCards(context),
        ),
        PageView.builder(
          scrollDirection: Axis.vertical,
          controller: _controller,
          physics: widget._scrollEnabled
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          itemCount: _displayItems.length,
          onPageChanged: widget._onPageChanged,
          itemBuilder: (BuildContext context, int index) {
            // Only used for gestures/scrolling.
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }

  Widget _stackedCards(BuildContext context) {
    final double textScaleFactor = 1.0;
    final List<Widget> positionedCards = _displayItems.asMap().entries.map((
      MapEntry<int, StackedCardCarouselItem> item,
    ) {
      double position = -widget._initialOffset;
      if (_pageValue < item.key) {
        position +=
            (_pageValue - item.key) *
            widget._spaceBetweenItems *
            textScaleFactor;
      }

      final isActive = item.key == _activeIndex;
      Widget child = item.value.builder(
        context,
        () => _requestDismiss(item.value.id),
        isActive: isActive,
      );
      if (item.value.id == _removingId) {
        child = FadeTransition(
          opacity: _removeOpacity,
          child: ClipRect(
            child: SizeTransition(
              sizeFactor: _removeSize,
              axisAlignment: -1,
              child: child,
            ),
          ),
        );
      }

      switch (widget._type) {
        case StackedCardCarouselType.fadeOutStack:
          double opacity = 1.0;
          double scale = 1.0;
          if (item.key - _pageValue < 0) {
            final double factor = 1 + (item.key - _pageValue);
            opacity = factor < 0.0 ? 0.0 : pow(factor, 1.5).toDouble();
            scale = factor < 0.0 ? 0.0 : pow(factor, 0.1).toDouble();
          }
          return Positioned.fill(
            top: -position,
            child: Align(
              alignment: Alignment.topCenter,
              child: Wrap(
                children: <Widget>[
                  Transform.scale(
                    scale: scale,
                    child: Opacity(opacity: opacity, child: child),
                  ),
                ],
              ),
            ),
          );

        case StackedCardCarouselType.cardsStack:
          double scale = 1.0;
          // Make cards progressively smaller based on distance from active index.
          final distanceFromActive = (item.key - _activeIndex).abs();
          final isInactive = distanceFromActive > 0;
          if (isInactive) {
            // Second card: 0.9, third card: 0.8, etc.
            scale = 1.0 - (distanceFromActive * 0.1).clamp(0.0, 0.3);
          }
          return Positioned.fill(
            top: -position + (20.0 * item.key),
            child: Align(
              alignment: Alignment.topCenter,
              child: Wrap(
                children: <Widget>[
                  Opacity(
                    opacity: isInactive ? 0.30 : 1.0,
                    child: Transform.scale(scale: scale, child: child),
                  ),
                ],
              ),
            ),
          );
      }
    }).toList();

    return Stack(
      alignment: Alignment.center,
      fit: StackFit.passthrough,
      children: positionedCards,
    );
  }
}

/// To allow all gestures detections to go through
/// https://stackoverflow.com/questions/57466767/how-to-make-a-gesturedetector-capture-taps-inside-a-stack
class ClickThroughStack extends Stack {
  const ClickThroughStack({required super.children, super.key});

  @override
  ClickThroughRenderStack createRenderObject(BuildContext context) {
    return ClickThroughRenderStack(
      alignment: alignment,
      textDirection: textDirection ?? Directionality.of(context),
      fit: fit,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant ClickThroughRenderStack renderObject,
  ) {
    renderObject
      ..alignment = alignment
      ..textDirection = textDirection ?? Directionality.of(context)
      ..fit = fit;
  }
}

class ClickThroughRenderStack extends RenderStack {
  ClickThroughRenderStack({
    required super.alignment,
    required super.fit,
    super.textDirection,
  });

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    bool stackHit = false;

    final List<RenderBox> children = getChildrenAsList();

    for (final RenderBox child in children) {
      final StackParentData childParentData =
          child.parentData! as StackParentData;

      final bool childHit = result.addWithPaintOffset(
        offset: childParentData.offset,
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) {
          assert(transformed == position - childParentData.offset);
          return child.hitTest(result, position: transformed);
        },
      );

      if (childHit) {
        stackHit = true;
      }
    }

    return stackHit;
  }
}
