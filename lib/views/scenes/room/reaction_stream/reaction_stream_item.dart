import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

import 'reaction_stream_layout.dart';

class ReactionStreamItem extends StatefulWidget {
  const ReactionStreamItem({
    required this.item,
    required this.senderLabel,
    required this.onDone,
    super.key,
  });

  final ReactionStreamItemData item;
  final String? senderLabel;
  final VoidCallback onDone;

  @override
  State<ReactionStreamItem> createState() => _ReactionStreamItemState();
}

class _ReactionStreamItemState extends State<ReactionStreamItem>
    with TickerProviderStateMixin {
  late final AnimationController _mainController;
  late final AnimationController _swayController;
  late final Animation<double> _riseAnimation;
  late final bool _reduceMotion;
  bool _doneCalled = false;

  static bool _platformReduceMotion() {
    return WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
  }

  @override
  void initState() {
    super.initState();
    _reduceMotion = _platformReduceMotion();

    _mainController = AnimationController(
      vsync: this,
      duration: _reduceMotion
          ? kReactionStreamReducedMotionDuration
          : kReactionStreamAnimationDuration,
    );

    _riseAnimation = CurvedAnimation(
      parent: _mainController,
      curve: const Cubic(0.25, 0.46, 0.45, 0.94),
    );

    _swayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    if (!_reduceMotion) {
      _swayController.value = 0.5;
      _swayController.repeat(reverse: true);
    }

    _mainController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _notifyDone();
      }
    });

    _mainController.forward();
  }

  void _notifyDone() {
    if (_doneCalled) return;
    _doneCalled = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _mainController.dispose();
    _swayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final riseDistance = viewportHeight * widget.item.riseVh / 100;
    final left =
        MediaQuery.sizeOf(context).width * widget.item.leftPercent / 100;
    final drift = widget.item.driftPx;
    final label = widget.senderLabel;

    return Positioned(
      left: left,
      bottom: kReactionStreamBottomInset,
      child: AnimatedBuilder(
        animation: Listenable.merge([_mainController, _swayController]),
        builder: (context, child) {
          final t = _mainController.value;
          final riseOffset = _reduceMotion
              ? 0.0
              : -riseDistance * _riseAnimation.value;
          final opacity = _reduceMotion
              ? reactionStreamReducedMotionOpacity(t)
              : reactionStreamAppearOpacity(t);
          final scale = _reduceMotion ? 1.0 : reactionStreamAppearScale(t);

          final swayT = _reduceMotion
              ? 0.0
              : Curves.easeInOut.transform(_swayController.value);
          final swayOffset = lerpDouble(-drift, drift, swayT)!;

          return Transform.translate(
            offset: Offset(swayOffset, riseOffset),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(scale: scale, child: child),
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.item.emoji,
              style: const TextStyle(
                fontSize: kReactionStreamEmojiSize,
                height: 1,
              ),
            ),
            if (label != null && label.isNotEmpty) ...[
              const SizedBox(height: 4),
              _ReactionStreamNamePill(label: label),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReactionStreamNamePill extends StatelessWidget {
  const _ReactionStreamNamePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          constraints: const BoxConstraints(
            maxWidth: kReactionStreamNameMaxWidth,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colors.interActionWeakMinor3.withValues(alpha: 0.6),
            border: Border.all(color: colors.appBorderNorm),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ProtonStyles.captionSemibold(color: colors.textNorm),
          ),
        ),
      ),
    );
  }
}
