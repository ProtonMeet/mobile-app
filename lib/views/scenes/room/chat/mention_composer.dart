import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/utils/mentions/mention_composer_display.dart';
import 'package:meet/utils/mentions/mention_suggestions.dart';
import 'package:meet/views/scenes/room/chat/mention_composer_controller.dart';
import 'package:meet/views/scenes/room/chat/mention_suggestions_overlay.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

typedef MentionTooLongCallback = void Function();

/// Text composer with `@` typeahead that stores mention tokens in [controller].
class MentionComposer extends StatefulWidget {
  const MentionComposer({
    required this.controller,
    required this.focusNode,
    required this.participantTracks,
    required this.localIdentity,
    required this.onSubmitted,
    this.textFieldKey,
    this.hintText,
    this.minLines = 1,
    this.maxLines,
    this.style,
    this.decoration,
    this.scrollController,
    this.constraints,
    this.padding,
    this.onTooLongMentionInsert,
    this.overlayAnchorKey,
    super.key,
  });

  final MentionComposerController controller;
  final FocusNode focusNode;
  final List<ParticipantInfo>? participantTracks;
  final String localIdentity;
  final VoidCallback onSubmitted;
  final Key? textFieldKey;
  final String? hintText;
  final int minLines;
  final int? maxLines;
  final TextStyle? style;
  final InputDecoration? decoration;
  final ScrollController? scrollController;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final MentionTooLongCallback? onTooLongMentionInsert;

  /// Suggestion list width follows this widget (e.g. full input row).
  final GlobalKey? overlayAnchorKey;

  @override
  State<MentionComposer> createState() => _MentionComposerState();
}

class _MentionComposerState extends State<MentionComposer> {
  final GlobalKey _fieldKey = GlobalKey();
  final Object _composerTapGroup = Object();
  OverlayEntry? _overlayEntry;
  static const int _noKeyboardSelection = -1;

  int _selectedSuggestionIndex = _noKeyboardSelection;
  List<MentionSuggestion> _suggestions = const [];
  ({int atIndex, String query})? _activeQuery;

  late final MentionComposerTextInputFormatter _mentionFormatter;

  @override
  void initState() {
    super.initState();
    _mentionFormatter = MentionComposerTextInputFormatter(widget.controller);
    widget.controller.displayController.addListener(_onTextOrSelectionChanged);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant MentionComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.displayController.removeListener(
        _onTextOrSelectionChanged,
      );
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.displayController.addListener(
        _onTextOrSelectionChanged,
      );
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.displayController.removeListener(
      _onTextOrSelectionChanged,
    );
    widget.controller.removeListener(_onControllerChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _dismissSuggestions() {
    _removeOverlay();
    if (_suggestions.isNotEmpty || _activeQuery != null) {
      setState(() {
        _suggestions = const [];
        _activeQuery = null;
      });
    }
  }

  void _onTextOrSelectionChanged() {
    _updateSuggestions();
  }

  void _updateSuggestions() {
    final text = widget.controller.displayController.text;
    final caret = widget.controller.displayController.selection.baseOffset;
    final lockedRanges = widget.controller.mentionDisplayRanges;
    final active = findActiveMentionQueryInDisplay(
      text,
      caret,
      lockedRanges: lockedRanges,
    );
    final suggestions = active == null
        ? const <MentionSuggestion>[]
        : getMentionSuggestions(
            participantTracks: widget.participantTracks,
            localIdentity: widget.localIdentity,
            everyoneName: context.local.chat_mention_everyone,
            everyoneHint: context.local.chat_mention_everyone_hint,
            query: active.query,
          );

    final previousQuery = _activeQuery?.query;
    final defaultIndex = desktop ? 0 : _noKeyboardSelection;
    setState(() {
      _activeQuery = active;
      _suggestions = suggestions;
      if (previousQuery != active?.query) {
        _selectedSuggestionIndex = defaultIndex;
      } else if (_selectedSuggestionIndex >= suggestions.length) {
        _selectedSuggestionIndex = defaultIndex;
      }
    });

    if (suggestions.isEmpty || active == null) {
      _removeOverlay();
      return;
    }
    _syncOverlay();
  }

  double _overlayHeight(int itemCount) {
    final rows = itemCount * MentionSuggestionsOverlay.itemHeight;
    const padding = 12.0;
    const rowGap = 4.0;
    return padding + rows + (itemCount > 0 ? (itemCount - 1) * rowGap : 0);
  }

  void _syncOverlay() {
    if (_overlayEntry == null) {
      _overlayEntry = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
      return;
    }
    _overlayEntry!.markNeedsBuild();
  }

  RenderBox? _overlayAnchorBox() {
    final anchorContext = widget.overlayAnchorKey?.currentContext;
    if (anchorContext != null) {
      return anchorContext.findRenderObject() as RenderBox?;
    }
    return _fieldKey.currentContext?.findRenderObject() as RenderBox?;
  }

  ({double left, double width}) _overlayGeometry(
    BuildContext context,
    RenderBox anchorBox,
  ) {
    const horizontalMargin = 16.0;
    final anchorOffset = anchorBox.localToGlobal(Offset.zero);
    final anchorWidth = anchorBox.size.width;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = screenWidth - horizontalMargin * 2;

    var width = math.max(
      anchorWidth,
      MentionSuggestionsOverlay.overlayMinWidth,
    );
    width = math.min(width, maxWidth);

    var left = anchorOffset.dx;
    if (width > anchorWidth) {
      left -= (width - anchorWidth) / 2;
    }
    left = left.clamp(horizontalMargin, screenWidth - horizontalMargin - width);

    return (left: left, width: width);
  }

  Widget _buildOverlay(BuildContext context) {
    final anchorBox = _overlayAnchorBox();
    if (anchorBox == null) {
      return const SizedBox.shrink();
    }

    final anchorOffset = anchorBox.localToGlobal(Offset.zero);
    final geometry = _overlayGeometry(context, anchorBox);
    final height = _overlayHeight(_suggestions.length);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _dismissSuggestions,
          ),
        ),
        Positioned(
          left: geometry.left,
          top: anchorOffset.dy - 8 - height,
          width: geometry.width,
          child: TapRegion(
            groupId: _composerTapGroup,
            child: MentionSuggestionsOverlay(
              suggestions: _suggestions,
              selectedIndex: desktop
                  ? _selectedSuggestionIndex
                  : _noKeyboardSelection,
              participantTracks: widget.participantTracks,
              everyoneSubtitle: context.local.chat_mention_everyone_hint,
              onEnsureComposerFocus: _restoreComposerFocus,
              onSelected: _selectSuggestion,
            ),
          ),
        ),
      ],
    );
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _restoreComposerFocus() {
    if (!widget.focusNode.canRequestFocus) {
      return;
    }
    widget.focusNode.requestFocus();
  }

  void _selectSuggestion(int index) {
    final active = _activeQuery;
    if (active == null || index < 0 || index >= _suggestions.length) {
      return;
    }
    final suggestion = _suggestions[index];
    final inserted = widget.controller.insertMention(
      id: suggestion.id,
      label: suggestion.name,
      atIndex: active.atIndex,
      queryLength: active.query.length,
    );
    if (!inserted) {
      widget.onTooLongMentionInsert?.call();
    }
    setState(() {
      _suggestions = const [];
      _activeQuery = null;
    });
    _removeOverlay();
    _restoreComposerFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _restoreComposerFocus();
    });
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (_suggestions.isEmpty || _activeQuery == null) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        if (_selectedSuggestionIndex < 0) {
          _selectedSuggestionIndex = 0;
        } else {
          _selectedSuggestionIndex =
              (_selectedSuggestionIndex + 1) % _suggestions.length;
        }
      });
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_selectedSuggestionIndex <= 0) {
          _selectedSuggestionIndex = _suggestions.length - 1;
        } else {
          _selectedSuggestionIndex = _selectedSuggestionIndex - 1;
        }
      });
      _overlayEntry?.markNeedsBuild();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _dismissSuggestions();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.tab) {
      if (_selectedSuggestionIndex >= 0) {
        _selectSuggestion(_selectedSuggestionIndex);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  TextStyle _effectiveStyle(BuildContext context) {
    return widget.style ?? DefaultTextStyle.of(context).style;
  }

  TextStyle _editableStyle(BuildContext context) {
    return _effectiveStyle(
      context,
    ).copyWith(color: Colors.transparent, decorationColor: Colors.transparent);
  }

  Widget _buildColoredMirror(BuildContext context) {
    final text = widget.controller.displayController.text;
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final baseStyle = _effectiveStyle(context);
    final span = buildComposerMentionTextSpan(
      context: context,
      stored: widget.controller.storedText,
      baseStyle: baseStyle,
      resolveParticipantName: widget.controller.resolveParticipantName,
      localIdentity: widget.controller.localIdentity,
      everyoneName: widget.controller.everyoneName,
      unknownName: widget.controller.unknownName,
      participantTracks: widget.participantTracks,
    );

    return IgnorePointer(
      child: Text.rich(
        span,
        maxLines: widget.maxLines,
        textAlign: TextAlign.start,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final field = Focus(
      onKeyEvent: _handleKey,
      child: Stack(
        alignment: Alignment.topLeft,
        children: [
          _buildColoredMirror(context),
          TextField(
            key: widget.textFieldKey,
            controller: widget.controller.displayController,
            focusNode: widget.focusNode,
            minLines: widget.minLines,
            maxLines: widget.maxLines,
            style: _editableStyle(context),
            cursorColor: _effectiveStyle(context).color,
            decoration: widget.decoration,
            scrollController: widget.scrollController,
            inputFormatters: [_mentionFormatter],
            textInputAction: TextInputAction.newline,
            onSubmitted: (_) {
              if (_suggestions.isNotEmpty) {
                return;
              }
              widget.onSubmitted();
            },
          ),
        ],
      ),
    );

    Widget child = field;
    if (widget.constraints != null || widget.padding != null) {
      child = Container(
        constraints: widget.constraints,
        padding: widget.padding,
        child: field,
      );
    }

    return TapRegion(
      groupId: _composerTapGroup,
      child: KeyedSubtree(key: _fieldKey, child: child),
    );
  }
}
