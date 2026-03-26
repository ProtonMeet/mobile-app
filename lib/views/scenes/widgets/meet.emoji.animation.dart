// nosemgrep: proton-use-of-insecure-random-in-dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class MeetEmojiInfo {
  final String emoji;
  final String name;
  final int timestamp;

  const MeetEmojiInfo({
    required this.emoji,
    required this.name,
    required this.timestamp,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeetEmojiInfo &&
          runtimeType == other.runtimeType &&
          emoji == other.emoji &&
          name == other.name &&
          timestamp == other.timestamp;

  @override
  int get hashCode => emoji.hashCode ^ name.hashCode;
}

class EmojiAnimation extends StatefulWidget {
  final List<MeetEmojiInfo> emojis;

  const EmojiAnimation({required this.emojis, super.key});

  @override
  State<EmojiAnimation> createState() => _EmojiAnimationState();
}

class _EmojiAnimationState extends State<EmojiAnimation>
    with TickerProviderStateMixin {
  final Map<String, MeetEmojiInfo> _lastShown = {};
  final List<_AnimatedEmoji> _activeEmojis = [];

  @override
  void didUpdateWidget(covariant EmojiAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newMap = {for (var e in widget.emojis) e.name: e};
    final oldMap = _lastShown;

    for (var entry in newMap.entries) {
      final name = entry.key;
      final info = entry.value;

      if (!oldMap.containsKey(name) ||
          oldMap[name]!.emoji != info.emoji ||
          (oldMap[name]?.timestamp ?? 0) <= info.timestamp - 400) {
        _triggerAnimation(info);
        _lastShown[name] = info;
      }
    }
  }

  void _triggerAnimation(MeetEmojiInfo info, {int count = 10}) {
    for (int i = 0; i < count; i++) {
      final controller = AnimationController(
        duration: const Duration(milliseconds: 3000),
        vsync: this,
      );

      final random = Random.secure();
      final dx = (random.nextDouble() - 0.5) * context.width / 4;
      final dy = -100.0 - random.nextDouble() * context.height / 2;

      final offset = Offset(dx, dy);

      final animation = Tween<Offset>(
        begin: Offset.zero,
        end: offset,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));

      final fadeAnimation = CurvedAnimation(
        parent: controller,
        curve: const Interval(0.6, 1.0),
      );

      final emojiWidget = _AnimatedEmoji(
        emoji: info.emoji,
        name: info.name,
        animation: animation,
        fadeAnimation: fadeAnimation,
        controller: controller,
        onCompleted: () {
          setState(() {
            _activeEmojis.removeWhere((e) => e.controller == controller);
          });
          controller.dispose();
        },
      );

      setState(() {
        _activeEmojis.add(emojiWidget);
      });

      controller.forward();
    }
  }

  @override
  void dispose() {
    for (var e in _activeEmojis) {
      e.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_activeEmojis.firstOrNull != null)
          Positioned(
            bottom: 0,
            left: context.width / 2 - 40,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.backgroundNorm.withAlpha(120),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  width: 80,
                  child: Center(
                    child: Text(
                      _activeEmojis.firstOrNull?.name ?? '',
                      style: ProtonStyles.body1Medium(
                        color: context.colors.textNorm,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ..._activeEmojis.map(
          (e) => Positioned(
            bottom: 0,
            left: context.width / 2 - 18,
            child: AnimatedBuilder(
              animation: e.controller,
              builder: (context, _) => Transform.translate(
                offset: e.animation.value,
                child: Opacity(
                  opacity: 1.0 - e.fadeAnimation.value,
                  child: Center(
                    child: Text(e.emoji, style: const TextStyle(fontSize: 36)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedEmoji {
  final String emoji;
  final String name;
  final Animation<Offset> animation;
  final Animation<double> fadeAnimation;
  final AnimationController controller;
  final VoidCallback onCompleted;

  _AnimatedEmoji({
    required this.emoji,
    required this.name,
    required this.animation,
    required this.fadeAnimation,
    required this.controller,
    required this.onCompleted,
  }) {
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        onCompleted();
      }
    });
  }
}
