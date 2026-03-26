import 'package:flutter/material.dart';

enum EmojiReaction { love, like, cry, surprised, clap, btc, rocket }

const Map<EmojiReaction, String> emojiMap = {
  EmojiReaction.love: '❤️',
  EmojiReaction.like: '👍',
  EmojiReaction.cry: '😢',
  EmojiReaction.surprised: '😮',
  EmojiReaction.clap: '👏',
  EmojiReaction.btc: '₿',
  EmojiReaction.rocket: '🚀',
};

extension EmojiReactionText on EmojiReaction {
  String get toText => emojiMap[this] ?? '';
}

extension EmojiReactionParser on String {
  EmojiReaction? toEmojiReaction() {
    try {
      return emojiMap.entries.firstWhere((entry) => entry.value == this).key;
    } catch (_) {
      return null;
    }
  }
}

class EmojiPicker extends StatelessWidget {
  final Function(EmojiReaction) onSelected;

  const EmojiPicker({required this.onSelected, super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: emojiMap.entries.map((entry) {
              return IconButton(
                onPressed: () => onSelected(entry.key),
                icon: Text(entry.value, style: const TextStyle(fontSize: 24)),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
