import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/room/participant/participant.dart';
import 'package:meet/views/scenes/room/reaction_stream/reaction_stream_item.dart';
import 'package:meet/views/scenes/room/reaction_stream/reaction_stream_layout.dart';

/// Screen-wide stream of emoji reactions (parity with web [ReactionStream]).
///
/// The raised hand stays on the participant tile; other reactions animate here.
class ReactionStream extends StatefulWidget {
  const ReactionStream({
    required this.activeReactions,
    required this.localParticipantIdentity,
    required this.displayNameForIdentity,
    super.key,
  });

  final Map<String, ParticipantReaction> activeReactions;
  final String? localParticipantIdentity;
  final String Function(String identity) displayNameForIdentity;

  @override
  State<ReactionStream> createState() => _ReactionStreamState();
}

class _ReactionStreamState extends State<ReactionStream> {
  final List<ReactionStreamItemData> _items = [];
  Map<String, int>? _seenTimestampsByIdentity;

  @override
  void didUpdateWidget(covariant ReactionStream oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromActiveReactions(widget.activeReactions);
  }

  @override
  void initState() {
    super.initState();
    _seenTimestampsByIdentity = {
      for (final entry in widget.activeReactions.entries)
        entry.key: entry.value.timestamp,
    };
  }

  void _syncFromActiveReactions(
    Map<String, ParticipantReaction> activeReactions,
  ) {
    final seen = _seenTimestampsByIdentity;
    if (seen == null) {
      return;
    }

    final added = <ReactionStreamItemData>[];

    for (final entry in activeReactions.entries) {
      final identity = entry.key;
      final reaction = entry.value;
      if (seen[identity] == reaction.timestamp) {
        continue;
      }
      seen[identity] = reaction.timestamp;

      if (reaction.emoji == raisedHandEmoji) {
        continue;
      }

      added.add(
        createReactionStreamItem(
          identity: identity,
          emoji: reaction.emoji,
          timestamp: reaction.timestamp,
        ),
      );
    }

    if (added.isEmpty) {
      return;
    }

    setState(() {
      _items.addAll(added);
      if (_items.length > kReactionStreamMaxVisible) {
        _items.removeRange(0, _items.length - kReactionStreamMaxVisible);
      }
    });
  }

  void _removeItem(String id) {
    setState(() {
      _items.removeWhere((item) => item.id == id);
    });
  }

  String? _senderLabel(BuildContext context, String identity) {
    if (identity == widget.localParticipantIdentity) {
      final you = context.local.you;
      if (you.length >= 2 && you.startsWith('(') && you.endsWith(')')) {
        return you.substring(1, you.length - 1);
      }
      return you;
    }
    final name = widget.displayNameForIdentity(identity);
    return name.isEmpty ? null : name;
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const SizedBox.shrink();
    }

    return ExcludeSemantics(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final item in _items)
            ReactionStreamItem(
              key: ValueKey(item.id),
              item: item,
              senderLabel: _senderLabel(context, item.identity),
              onDone: () => _removeItem(item.id),
            ),
        ],
      ),
    );
  }
}
