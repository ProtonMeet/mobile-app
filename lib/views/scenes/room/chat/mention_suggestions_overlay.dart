import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/utils/mentions/mention_label.dart';
import 'package:meet/utils/mentions/mention_suggestions.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:meet/views/scenes/utils.dart';

/// Styled `@` suggestion list shown above the chat composer.
class MentionSuggestionsOverlay extends StatelessWidget {
  const MentionSuggestionsOverlay({
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelected,
    required this.participantTracks,
    required this.everyoneSubtitle,
    this.onEnsureComposerFocus,
    super.key,
  });

  static const double itemHeight = 52;
  static const double avatarSize = 32;
  static const double overlayMinWidth = 280;
  static const double containerRadius = 16;
  static const double itemRadius = 12;
  static const Color containerBorderColor = Color(0xFF393B51);

  final List<MentionSuggestion> suggestions;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<ParticipantInfo>? participantTracks;
  final String everyoneSubtitle;
  final VoidCallback? onEnsureComposerFocus;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.backgroundCard,
          borderRadius: BorderRadius.circular(containerRadius),
          border: Border.all(color: containerBorderColor),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < suggestions.length; index++) ...[
              if (index > 0) const SizedBox(height: 4),
              _SuggestionRow(
                suggestion: suggestions[index],
                keyboardSelected: selectedIndex >= 0 && index == selectedIndex,
                participantTracks: participantTracks,
                everyoneSubtitle: everyoneSubtitle,
                onEnsureComposerFocus: onEnsureComposerFocus,
                onTap: () => onSelected(index),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.keyboardSelected,
    required this.participantTracks,
    required this.everyoneSubtitle,
    required this.onTap,
    this.onEnsureComposerFocus,
  });

  final MentionSuggestion suggestion;
  final bool keyboardSelected;
  final List<ParticipantInfo>? participantTracks;
  final String everyoneSubtitle;
  final VoidCallback onTap;
  final VoidCallback? onEnsureComposerFocus;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  bool _hovered = false;

  bool get _highlighted => widget.keyboardSelected || _hovered;

  void _setHovered(bool value) {
    if (_hovered == value || !mounted) {
      return;
    }
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          widget.onEnsureComposerFocus?.call();
          widget.onTap();
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _highlighted
                ? context.colors.cardHighlightColor
                : Colors.transparent,
            borderRadius: BorderRadius.circular(
              MentionSuggestionsOverlay.itemRadius,
            ),
          ),
          child: SizedBox(
            height: MentionSuggestionsOverlay.itemHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  _SuggestionAvatar(
                    suggestion: widget.suggestion,
                    participantTracks: widget.participantTracks,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.suggestion.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ProtonStyles.body2Medium(
                        color: context.colors.textNorm,
                      ),
                    ),
                  ),
                  if (widget.suggestion.isEveryone) ...[
                    const SizedBox(width: 8),
                    Text(
                      widget.everyoneSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ProtonStyles.captionMedium(
                        color: context.colors.textDisable,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionAvatar extends StatelessWidget {
  const _SuggestionAvatar({
    required this.suggestion,
    required this.participantTracks,
  });

  final MentionSuggestion suggestion;
  final List<ParticipantInfo>? participantTracks;

  @override
  Widget build(BuildContext context) {
    final colors = getMentionDisplayColors(
      context,
      suggestion.id,
      participantTracks: participantTracks,
    );

    return Container(
      width: MentionSuggestionsOverlay.avatarSize,
      height: MentionSuggestionsOverlay.avatarSize,
      decoration: BoxDecoration(
        color: colors.backgroundColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: suggestion.isEveryone
            ? Icon(
                Icons.alternate_email,
                size: 16,
                color: colors.profileTextColor,
              )
            : Text(
                getInitials(suggestion.name),
                style: ProtonStyles.captionMedium(
                  color: colors.profileTextColor,
                ),
              ),
      ),
    );
  }
}
