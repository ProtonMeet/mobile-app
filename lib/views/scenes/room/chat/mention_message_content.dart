import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:linkify/linkify.dart' show linkify;
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/utils/mentions/mention_label.dart';
import 'package:meet/utils/mentions/mention_token.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders stored chat text with inline `@mention` chips and linkified text.
class MentionMessageContent extends StatelessWidget {
  const MentionMessageContent({
    required this.message,
    required this.localIdentity,
    required this.participantNameMap,
    required this.participantTracks,
    this.selectable = true,
    super.key,
  });

  final String message;
  final String localIdentity;
  final Map<String, String> participantNameMap;
  final List<ParticipantInfo>? participantTracks;
  final bool selectable;

  Future<void> _handleLinkOpen(LinkableElement link) async {
    final uri = Uri.parse(link.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final segments = splitMessageIntoMentionSegments(message);
    if (segments.every((segment) => segment is TextSegment)) {
      return _buildPlainLinkify(context);
    }

    final everyoneName = context.local.chat_mention_everyone;
    final unknownName = context.local.unknown;
    final textStyle = ProtonStyles.body2Medium(color: context.colors.textWeak);
    final linkStyle = ProtonStyles.body2Medium(
      color: context.colors.protonBlue,
    ).copyWith(decoration: TextDecoration.underline);

    final children = <InlineSpan>[];
    for (final segment in segments) {
      if (segment is MentionSegment) {
        final label = getMentionLabel(
          segment.id,
          participantName: participantNameMap[segment.id],
          localIdentity: localIdentity,
          everyoneName: everyoneName,
          unknownName: unknownName,
        );
        final colors = getMentionDisplayColors(
          context,
          segment.id,
          participantTracks: participantTracks,
        );
        children.add(
          TextSpan(
            text: '@$label',
            style: textStyle.copyWith(
              color: colors.profileTextColor,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        );
        continue;
      }

      final text = (segment as TextSegment).text;
      if (text.isEmpty) {
        continue;
      }
      final linkified = linkify(
        text,
        options: const LinkifyOptions(humanize: false),
      );
      for (final element in linkified) {
        if (element is LinkableElement) {
          children.add(
            TextSpan(
              text: element.text,
              style: linkStyle,
              recognizer: TapGestureRecognizer()
                ..onTap = () => _handleLinkOpen(element),
            ),
          );
        } else {
          children.add(TextSpan(text: element.text, style: textStyle));
        }
      }
    }

    final rich = TextSpan(children: children);
    if (!selectable) {
      return Text.rich(rich);
    }
    return SelectableText.rich(rich);
  }

  Widget _buildPlainLinkify(BuildContext context) {
    final style = ProtonStyles.body2Medium(color: context.colors.textWeak);
    final linkStyle = ProtonStyles.body2Medium(
      color: context.colors.protonBlue,
    ).copyWith(decoration: TextDecoration.underline);
    if (!selectable) {
      return Linkify(
        text: message,
        style: style,
        linkStyle: linkStyle,
        onOpen: _handleLinkOpen,
      );
    }
    return SelectableLinkify(
      text: message,
      style: style,
      linkStyle: linkStyle,
      onOpen: _handleLinkOpen,
    );
  }
}
