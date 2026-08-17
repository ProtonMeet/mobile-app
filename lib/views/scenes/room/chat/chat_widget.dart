import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:meet/constants/app.keys.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/views/scenes/room/chat/chat_controller.dart';
import 'package:meet/views/scenes/room/chat/chat_emoji_picker.dart';
import 'package:meet/views/scenes/room/chat/chat_models.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:meet/views/scenes/room/side_panel_widget.dart';
import 'package:meet/views/scenes/utils.dart';
import 'package:url_launcher/url_launcher.dart';

/// Signature for sending a chat message. When [replyToId] / [topicId] are set,
/// the message is a thread reply.
typedef ChatSendCallback =
    Future<void> Function(String text, {String? replyToId, String? topicId});

/// Signature for toggling an emoji reaction on a message.
typedef ChatReactionCallback =
    Future<void> Function(String messageId, String emoji);

class ChatWidget extends StatefulWidget {
  final ChatController controller;
  final String localIdentity;
  final String localName;
  final bool chatThreadsEnabled;
  final ChatSendCallback onSend;
  final ChatReactionCallback onToggleReaction;
  final void Function(RoomChatMessage message)? onRetry;
  final void Function(RoomChatMessage message)? onDiscard;
  final List<ParticipantInfo>? participantTracks;

  const ChatWidget({
    required this.controller,
    required this.localIdentity,
    required this.localName,
    required this.onSend,
    required this.onToggleReaction,
    this.chatThreadsEnabled = false,
    this.onRetry,
    this.onDiscard,
    this.participantTracks,
    super.key,
  });

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetConstants {
  static const double inputButtonSize = 54.0;
  static const double sendIconSize = 24.0;
  static const double avatarSize = 40.0;
  static const double replyAvatarSize = 28.0;
  static const double replyActionButtonSize = 32.0;
  static const double emptyStateIconSize = 48.0;

  static const double verticalPadding = 8.0;
  static const double inputPadding = 8.0;
  static const double inputBottomPadding = 4.0;
  static const double spacingSmall = 4.0;
  static const double spacingMedium = 8.0;
  static const double spacingLarge = 16.0;
  static const double spacingXLarge = 70.0;

  static const double borderRadiusXLarge = 200.0;
  static const double borderRadiusAvatar = 20002.0;

  static const double chatWidthPortrait = 375.0;
  static const double chatWidthThreshold = 400.0;
  static const double minHeightDefault = 300.0;
  static const double maxHeightDefault = double.infinity;
  static const double minHeightPortrait = 500.0;
  static const double heightAdjustment = 24.0;
  static const double minHeightRatio = 0.6;
  static const double maxMinHeight = 500.0;

  static const int scrollAnimationDuration = 150;
  static const int scrollAnimationDurationLong = 250;
  static const int inputScrollAnimationDuration = 100;
  static const int paddingAnimationDuration = 160;

  static const double sendButtonVerticalPadding = 6.0;

  static const Color inputBackgroundColor = Color(0xFF1A1A28);
  static const Color sendButtonColor = Color(0xFFABABF8);
  static const Color textTertiary = Color(0xFF818199);
  static const Color threadLineColor = Color(0xFF3A3A4A);
  static const Color reactionPillColor = Color(0xFF2A2A38);
  static const Color reactionPillActiveColor = Color(0xFF3D3A5C);
  static const Color missingRootAvatarColor = Color(0xFF393B51);
  static const Color joinLeaveMeetingNameColor = Color(0xFF968AEF);
  static const double threadLineWidth = 2.0;

  /// Left offset so the thread line is centered under the root avatar.
  static const double threadLineLeft = avatarSize / 2 - threadLineWidth / 2;

  /// Gap between the thread line and thread text / replies.
  static const double threadLineContentGap = spacingMedium;

  /// Horizontal offset where thread content begins (after line + gap).
  static const double threadContentLeft =
      threadLineLeft + threadLineWidth + threadLineContentGap;
}

class _ChatWidgetState extends State<ChatWidget> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _inputScrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  /// Per-thread reply composer controllers (keyed by root id).
  final Map<String, TextEditingController> _replyControllers = {};
  final Map<String, FocusNode> _replyFocusNodes = {};

  final Map<String, ({Color backgroundColor, Color profileTextColor})>
  _colorCache = {};
  final Map<String, String> _initialsCache = {};

  bool _isAtBottom = true;
  bool _isScrollingToBottom = false;
  int _newMessagesOverlayCount = 0;
  final Set<String> _trackedMessageIds = {};
  final Set<String> _handledLocalRootScrollIds = {};

  ChatController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _textController.text = _controller.draftMessage;
    _textController.addListener(_onTextChanged);
    _inputFocusNode.addListener(_onFocusChanged);
    _scrollController.addListener(_onScroll);
    _controller.addListener(_onControllerChanged);
    _trackedMessageIds.addAll(_controller.messages.map((m) => m.id));
  }

  bool _isLocalRootMessage(RoomChatMessage message) {
    return message.isRoot &&
        !message.isSystem &&
        widget.localIdentity.isNotEmpty &&
        message.identity == widget.localIdentity;
  }

  bool _countsTowardNewMessagesOverlay(RoomChatMessage message) {
    if (message.isSystem || message.isReply || _isLocalRootMessage(message)) {
      return false;
    }
    return true;
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final messages = _controller.messages;
    final newMessages = messages
        .where((message) => !_trackedMessageIds.contains(message.id))
        .toList();

    if (newMessages.isEmpty) {
      setState(() {});
      return;
    }

    for (final message in newMessages) {
      _trackedMessageIds.add(message.id);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _handleNewMessages(newMessages);
    });
    setState(() {});
  }

  void _handleNewMessages(List<RoomChatMessage> newMessages) {
    if (!mounted || !_scrollController.hasClients) return;

    final unseenLocalRoots = newMessages
        .where(_isLocalRootMessage)
        .where((message) => !_handledLocalRootScrollIds.contains(message.id))
        .toList();
    if (unseenLocalRoots.isNotEmpty) {
      _handledLocalRootScrollIds.addAll(unseenLocalRoots.map((m) => m.id));
      _scheduleScrollToBottom();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _isAtBottom = true;
        _resetNewMessagesOverlay();
        _controller.markAllSeen();
        setState(() {});
      });
      setState(() {});
      return;
    }

    var overlayDelta = 0;
    for (final message in newMessages) {
      if (_countsTowardNewMessagesOverlay(message)) {
        overlayDelta++;
      }
    }

    final atBottom =
        _scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 24;
    _isAtBottom = atBottom;

    if (atBottom) {
      _resetNewMessagesOverlay(syncMessageCount: false);
      _controller.markAllSeen();
    } else if (_isMessageListScrollable && overlayDelta > 0) {
      _newMessagesOverlayCount += overlayDelta;
    }
    setState(() {});
  }

  bool get _isMessageListScrollable {
    if (!_scrollController.hasClients) return false;
    return _scrollController.position.maxScrollExtent > 24;
  }

  void _resetNewMessagesOverlay({bool syncMessageCount = true}) {
    _newMessagesOverlayCount = 0;
    if (syncMessageCount) {
      _trackedMessageIds
        ..clear()
        ..addAll(_controller.messages.map((m) => m.id));
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final atBottom = position.pixels >= position.maxScrollExtent - 24;
    if (_isAtBottom != atBottom) {
      setState(() => _isAtBottom = atBottom);
      if (atBottom) {
        _resetNewMessagesOverlay();
      }
    }
    if (_newMessagesOverlayCount > 0) {
      setState(_resetNewMessagesOverlay);
    }
  }

  void _onNewMessagesOverlayTap() {
    _resetNewMessagesOverlay();
    _scrollToBottom();
    _controller.markAllSeen();
    setState(() {});
  }

  void _dismissNewMessagesOverlay() {
    setState(_resetNewMessagesOverlay);
  }

  void _onFocusChanged() {
    if (!_inputFocusNode.hasFocus || !_isAtBottom) return;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _inputFocusNode.hasFocus && _isAtBottom) {
        _scheduleScrollToBottom();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToBottom(immediate: true);
    });
  }

  void _scheduleScrollToBottom() {
    if (_isScrollingToBottom) return;
    _isScrollingToBottom = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToBottom();
        _isScrollingToBottom = false;
      }
    });
  }

  void _scrollToBottom({bool immediate = false}) {
    if (!_scrollController.hasClients || !mounted) return;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    if (maxScrollExtent == 0) return;
    final currentPosition = _scrollController.position.pixels;
    final scrollDistance = (maxScrollExtent - currentPosition).abs();
    if (scrollDistance < 5.0) {
      _isScrollingToBottom = false;
      return;
    }
    final isLongScroll = scrollDistance > 500;
    final duration = immediate
        ? 0
        : (isLongScroll
              ? _ChatWidgetConstants.scrollAnimationDurationLong
              : _ChatWidgetConstants.scrollAnimationDuration);
    if (duration == 0) {
      _scrollController.jumpTo(maxScrollExtent);
      _isScrollingToBottom = false;
    } else {
      _scrollController
          .animateTo(
            maxScrollExtent,
            duration: Duration(milliseconds: duration),
            curve: Curves.easeOutCubic,
          )
          .then((_) {
            if (mounted) _isScrollingToBottom = false;
          });
    }
  }

  void _onTextChanged() {
    _controller.setDraftMessage(_textController.text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_inputScrollController.hasClients && _inputFocusNode.hasFocus) {
        final text = _textController.text;
        if (text.contains('\n') &&
            _inputScrollController.position.pixels <
                _inputScrollController.position.maxScrollExtent - 5) {
          _inputScrollController.animateTo(
            _inputScrollController.position.maxScrollExtent,
            duration: const Duration(
              milliseconds: _ChatWidgetConstants.inputScrollAnimationDuration,
            ),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _textController.removeListener(_onTextChanged);
    _inputFocusNode.removeListener(_onFocusChanged);
    _scrollController.removeListener(_onScroll);
    _textController.dispose();
    _scrollController.dispose();
    _inputScrollController.dispose();
    _inputFocusNode.dispose();
    for (final c in _replyControllers.values) {
      c.dispose();
    }
    for (final f in _replyFocusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _handleSendPressed() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _textController.clear();
    _controller.setDraftMessage('');
  }

  TextEditingController _replyController(RoomChatMessage root) {
    return _replyControllers.putIfAbsent(root.id, () {
      final c = TextEditingController(text: root.replyDraft ?? '');
      c.addListener(() => _controller.setThreadReplyDraft(root.id, c.text));
      return c;
    });
  }

  FocusNode _replyFocus(String rootId) {
    return _replyFocusNodes.putIfAbsent(rootId, FocusNode.new);
  }

  void _handleReplySend(RoomChatMessage root) {
    final controller = _replyController(root);
    final text = controller.text.trim();
    if (text.isEmpty) return;
    final topicId = root.topicId ?? root.id;
    widget.onSend(text, replyToId: root.id, topicId: topicId);
    controller.clear();
    _controller.setThreadReplyDraft(root.id, null);
  }

  void _closeThreadReply(RoomChatMessage root) {
    _replyControllers[root.id]?.clear();
    _controller.setThreadReplyDraft(root.id, null);
    final current = _controller.messageById(root.id);
    final threadHasReplies = _controller.threads.any(
      (thread) => thread.root.id == root.id && thread.hasReplies,
    );
    if (current != null && !threadHasReplies && !current.hasReactions) {
      _controller.setThreadExpanded(root.id, false);
    }
    _replyFocus(root.id).unfocus();
  }

  double _calculateChatWidth(double availableWidth, bool isLandscape) {
    if (isLandscape) return availableWidth;
    return availableWidth > _ChatWidgetConstants.chatWidthThreshold
        ? _ChatWidgetConstants.chatWidthPortrait
        : availableWidth;
  }

  ({double maxHeight, double minHeight}) _calculateHeights(
    bool isLandscape,
    double keyboardHeight,
    double screenHeight,
  ) {
    if (isLandscape) {
      if (keyboardHeight > 0) {
        final availableHeight =
            (screenHeight -
                    keyboardHeight -
                    _ChatWidgetConstants.heightAdjustment)
                .clamp(_ChatWidgetConstants.minHeightDefault, double.infinity);
        final minHeight =
            (availableHeight * _ChatWidgetConstants.minHeightRatio).clamp(
              _ChatWidgetConstants.minHeightDefault,
              _ChatWidgetConstants.maxMinHeight,
            );
        return (maxHeight: availableHeight, minHeight: minHeight);
      } else {
        return (maxHeight: screenHeight, minHeight: screenHeight * 0.8);
      }
    }
    return (
      maxHeight: _ChatWidgetConstants.maxHeightDefault,
      minHeight: _ChatWidgetConstants.minHeightPortrait,
    );
  }

  double _calculateInputBottomPadding(double keyboardHeight) {
    return keyboardHeight > 0
        ? keyboardHeight + _ChatWidgetConstants.inputBottomPadding
        : _ChatWidgetConstants.inputBottomPadding;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final screenWidth = mediaQuery.size.width;
    final screenHeight = mediaQuery.size.height;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : screenWidth;
        final isLandscape = screenWidth > screenHeight;
        final chatWidth = _calculateChatWidth(availableWidth, isLandscape);
        final heights = _calculateHeights(
          isLandscape,
          keyboardHeight,
          screenHeight,
        );
        final inputBottomPadding = _calculateInputBottomPadding(keyboardHeight);

        return SizedBox(
          width: chatWidth,
          height: isLandscape ? heights.maxHeight : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: heights.maxHeight,
              minHeight: heights.minHeight,
            ),
            child: RoomSidePanelScroll(
              scrollController: _scrollController,
              fillHeight: isLandscape,
              header: Text(
                context.local.chat_title,
                style: ProtonStyles.headline(
                  fontSize: 18,
                  color: context.colors.textNorm,
                ),
              ),
              footer: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(child: _buildNewMessagesOverlay(context)),
                    RepaintBoundary(
                      child: _buildInputField(context, inputBottomPadding),
                    ),
                    const SizedBox(height: _ChatWidgetConstants.spacingMedium),
                  ],
                ),
              ),
              slivers: _buildMessageSlivers(context),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildMessageSlivers(BuildContext context) {
    final threads = _controller.threads;

    if (threads.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyState(context),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(
          horizontal: RoomSidePanelLayout.horizontalPadding,
        ),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              return RepaintBoundary(
                child: _buildThread(context, threads[index]),
              );
            },
            childCount: threads.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false,
          ),
        ),
      ),
    ];
  }

  // ── New messages overlay (shown while scrolled up) ──
  Widget _buildNewMessagesOverlay(BuildContext context) {
    final count = _newMessagesOverlayCount;
    if (count == 0 || _isAtBottom || !_isMessageListScrollable) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: ShapeDecoration(
          color: _ChatWidgetConstants.sendButtonColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _onNewMessagesOverlayTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_downward,
                    size: 18,
                    color: context.colors.textInverted,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    context.local.chat_new_messages_badge(count),
                    style: ProtonStyles.body2Semibold(
                      color: context.colors.textInverted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _dismissNewMessagesOverlay,
              behavior: HitTestBehavior.opaque,
              child: Icon(
                Icons.close,
                size: 18,
                color: context.colors.textInverted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(BuildContext context, double bottomPadding) {
    return RepaintBoundary(
      child: AnimatedPadding(
        duration: const Duration(
          milliseconds: _ChatWidgetConstants.paddingAnimationDuration,
        ),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          left: RoomSidePanelLayout.horizontalPadding,
          right: RoomSidePanelLayout.horizontalPadding,
          bottom: bottomPadding,
          top: _ChatWidgetConstants.inputPadding,
        ),
        child: Row(
          children: [
            Expanded(child: _buildTextField(context)),
            const SizedBox(width: _ChatWidgetConstants.spacingMedium),
            _buildSendButton(context),
          ],
        ),
      ),
    );
  }

  ({
    double singleLineHeight,
    double maxHeight,
    double lineHeight,
    double twoLinesHeight,
  })?
  _cachedTextFieldHeights;

  ({
    double singleLineHeight,
    double maxHeight,
    double lineHeight,
    double twoLinesHeight,
  })
  _calculateTextFieldHeights() {
    if (_cachedTextFieldHeights != null) return _cachedTextFieldHeights!;
    final textStyle = ProtonStyles.body2Medium(color: context.colors.textNorm);
    final lineHeight = textStyle.height! * textStyle.fontSize!;
    final twoLinesHeight = lineHeight * 2;
    final verticalPadding = _ChatWidgetConstants.spacingLarge * 2;
    final singleLineHeight = lineHeight + verticalPadding;
    final maxHeight = twoLinesHeight + verticalPadding;
    _cachedTextFieldHeights = (
      singleLineHeight: singleLineHeight,
      maxHeight: maxHeight,
      lineHeight: lineHeight,
      twoLinesHeight: twoLinesHeight,
    );
    return _cachedTextFieldHeights!;
  }

  Widget _buildTextField(BuildContext context) {
    final textStyle = ProtonStyles.body2Medium(color: context.colors.textNorm);
    final heights = _calculateTextFieldHeights();
    return RepaintBoundary(
      child: GestureDetector(
        onTap: _inputFocusNode.requestFocus,
        child: Container(
          constraints: BoxConstraints(
            minHeight: heights.singleLineHeight,
            maxHeight: heights.maxHeight,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: RoomSidePanelLayout.horizontalPadding,
            vertical: _ChatWidgetConstants.spacingLarge,
          ),
          decoration: ShapeDecoration(
            color: _ChatWidgetConstants.inputBackgroundColor,
            shape: RoundedRectangleBorder(
              side: const BorderSide(
                color: _ChatWidgetConstants.missingRootAvatarColor,
              ),
              borderRadius: BorderRadius.circular(
                _ChatWidgetConstants.borderRadiusXLarge,
              ),
            ),
          ),
          child: SingleChildScrollView(
            controller: _inputScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: heights.lineHeight,
                maxHeight: heights.twoLinesHeight,
              ),
              child: IntrinsicHeight(
                child: TextField(
                  key: AppKeys.chatMessageTextField,
                  controller: _textController,
                  focusNode: _inputFocusNode,
                  maxLines: null,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  textAlignVertical: TextAlignVertical.top,
                  style: textStyle,
                  decoration: InputDecoration(
                    hintText: context.local.chat_input_hint,
                    hintStyle: ProtonStyles.body2Medium(
                      color: context.colors.textDisable,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _handleSendPressed(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: _handleSendPressed,
        child: Container(
          width: _ChatWidgetConstants.inputButtonSize,
          height: _ChatWidgetConstants.inputButtonSize,
          padding: const EdgeInsets.symmetric(
            horizontal: _ChatWidgetConstants.spacingMedium,
            vertical: _ChatWidgetConstants.sendButtonVerticalPadding,
          ),
          decoration: const ShapeDecoration(
            color: _ChatWidgetConstants.sendButtonColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(500)),
            ),
          ),
          child: Center(
            child: context.images.iconChatSend.svg(
              width: _ChatWidgetConstants.sendIconSize,
              height: _ChatWidgetConstants.sendIconSize,
              colorFilter: ColorFilter.mode(
                context.colors.textInverted,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          context.images.iconChatLogo.svg(
            width: _ChatWidgetConstants.emptyStateIconSize,
            height: _ChatWidgetConstants.emptyStateIconSize,
          ),
          const SizedBox(height: _ChatWidgetConstants.spacingLarge),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: _ChatWidgetConstants.spacingXLarge,
            ),
            child: Text(
              textAlign: TextAlign.center,
              context.local.chat_privacy_message,
              style: ProtonStyles.body2Medium(
                color: context.colors.textDisable,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Thread rendering ──
  Widget _buildThread(BuildContext context, ChatThread thread) {
    final root = thread.root;
    final showCloseButton = root.expanded && !thread.hasReplies;
    final showThreadSection = thread.hasReplies || root.expanded;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: _ChatWidgetConstants.verticalPadding,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(right: showCloseButton ? 28 : 0),
                child: _buildMessageRow(
                  context,
                  root,
                  isReply: false,
                  isMissingRoot: thread.isRootMissing,
                ),
              ),
              if (showThreadSection)
                _buildThreadIndentedSection(context, thread),
            ],
          ),
          if (showCloseButton)
            Positioned(
              top: 0,
              right: 0,
              child: _buildThreadCloseButton(context, root),
            ),
        ],
      ),
    );
  }

  Widget _buildThreadCloseButton(BuildContext context, RoomChatMessage root) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => _closeThreadReply(root),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.close,
            size: 20,
            color: _ChatWidgetConstants.textTertiary,
            semanticLabel: context.local.close,
          ),
        ),
      ),
    );
  }

  Widget _buildThreadIndentedSection(BuildContext context, ChatThread thread) {
    final root = thread.root;

    // Collapsed: toggle only, no vertical line.
    if (thread.hasReplies && !root.expanded) {
      return Padding(
        padding: const EdgeInsets.only(
          left: _ChatWidgetConstants.threadContentLeft,
        ),
        child: _buildThreadToggle(context, thread),
      );
    }

    // Expanded: line from root avatar center down through replies / composer.
    if (root.expanded) {
      return Padding(
        padding: const EdgeInsets.only(
          left: _ChatWidgetConstants.threadLineLeft,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: _ChatWidgetConstants.threadLineColor,
                child: const SizedBox(
                  width: _ChatWidgetConstants.threadLineWidth,
                ),
              ),
              const SizedBox(width: _ChatWidgetConstants.threadLineContentGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (thread.hasReplies) _buildThreadToggle(context, thread),
                    _buildThreadExpandedContent(context, thread),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildThreadToggle(BuildContext context, ChatThread thread) {
    final root = thread.root;
    final count = thread.replies.length;
    final expanded = root.expanded;
    final showBadge = _controller.threadHasUnseenBadge(thread) && !expanded;
    final label = expanded
        ? context.local.chat_thread_replies_count(count)
        : context.local.chat_thread_view_replies(count);
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: _ChatWidgetConstants.spacingSmall,
      ),
      child: InkWell(
        onTap: () => _controller.setThreadExpanded(root.id, !expanded),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                size: 18,
                color: context.colors.protonBlue,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: ProtonStyles.captionSemibold(
                  color: context.colors.protonBlue,
                ),
              ),
              if (showBadge) ...[
                const SizedBox(width: 6),
                _buildNewReplyBadge(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNewReplyBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
        color: _ChatWidgetConstants.reactionPillActiveColor,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _ChatWidgetConstants.sendButtonColor),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: _ChatWidgetConstants.sendButtonColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            context.local.chat_thread_new_reply,
            style: ProtonStyles.captionSemibold(color: context.colors.textNorm),
          ),
        ],
      ),
    );
  }

  Widget _buildThreadExpandedContent(BuildContext context, ChatThread thread) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final reply in thread.replies)
          _buildMessageRow(context, reply, isReply: true),
        if (thread.replies.isNotEmpty)
          const SizedBox(height: _ChatWidgetConstants.spacingSmall),
        _buildReplyComposer(context, thread.root),
      ],
    );
  }

  Widget _buildReplyComposer(BuildContext context, RoomChatMessage root) {
    final controller = _replyController(root);
    final focus = _replyFocus(root.id);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: ShapeDecoration(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: _ChatWidgetConstants.missingRootAvatarColor),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
      child: Row(
        children: [
          _buildLocalUserAvatar(size: _ChatWidgetConstants.replyAvatarSize),
          const SizedBox(width: _ChatWidgetConstants.spacingMedium),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              style: ProtonStyles.body2Medium(color: context.colors.textNorm),
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: context.local.chat_reply_hint,
                hintStyle: ProtonStyles.body2Medium(
                  color: context.colors.textDisable,
                ),
              ),
              onSubmitted: (_) => _handleReplySend(root),
            ),
          ),
          _buildReplyComposerIconButton(
            onTap: () => _openEmojiPickerFor(
              root.id,
              isReaction: false,
              insertInto: controller,
            ),
            child: Icon(
              Icons.emoji_emotions_outlined,
              size: 17.0,
              color: context.colors.textWeak,
            ),
          ),
          const SizedBox(width: 6),
          _buildReplyComposerIconButton(
            onTap: () => _handleReplySend(root),
            child: context.images.iconChatSend.svg(
              width: 15,
              height: 15,
              colorFilter: ColorFilter.mode(
                context.colors.textWeak,
                BlendMode.srcIn,
              ),
            ),
            backgroundColor: context.colors.interActionWeak,
          ),
        ],
      ),
    );
  }

  Widget _buildReplyComposerIconButton({
    required VoidCallback onTap,
    required Widget child,
    Color? backgroundColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _ChatWidgetConstants.replyActionButtonSize,
        height: _ChatWidgetConstants.replyActionButtonSize,
        decoration: ShapeDecoration(
          color: backgroundColor ?? context.colors.controlButtonBackground,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: _ChatWidgetConstants.missingRootAvatarColor,
            ),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Center(child: child),
      ),
    );
  }

  Widget _buildMessageRow(
    BuildContext context,
    RoomChatMessage message, {
    required bool isReply,
    bool isMissingRoot = false,
  }) {
    final avatarSize = isReply
        ? _ChatWidgetConstants.replyAvatarSize
        : _ChatWidgetConstants.avatarSize;

    if (isMissingRoot) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _buildMissingRootAvatar(size: avatarSize),
            const SizedBox(width: _ChatWidgetConstants.spacingLarge),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  context.local.chat_thread_missing_root,
                  style: ProtonStyles.bodySmallSemibold(
                    color: _ChatWidgetConstants.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final showControls =
        widget.chatThreadsEnabled &&
        message.status != ChatMessageStatus.pending;

    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: isReply ? 6 : 8),
      child: SizedBox(
        width: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAvatarForIdentity(
              message.name,
              message.identity,
              size: avatarSize,
            ),
            const SizedBox(width: _ChatWidgetConstants.spacingLarge),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMessageHeader(
                    message.name,
                    message.timestamp,
                    identity: message.identity,
                  ),
                  const SizedBox(height: _ChatWidgetConstants.spacingSmall),
                  if (message.isSystem)
                    _buildSystemMessageContent(
                      message,
                      selectable: !showControls,
                    )
                  else
                    _buildMessageContent(
                      message.message,
                      selectable: !showControls,
                    ),
                  if (message.status == ChatMessageStatus.failed)
                    _buildFailedRow(context, message),
                  if (message.hasReactions)
                    _buildReactionPills(context, message),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (!showControls || message.isSystem) return row;

    return GestureDetector(
      onLongPress: () => _showMessageActions(context, message),
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }

  Widget _buildFailedRow(BuildContext context, RoomChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 14,
            color: context.colors.signalDanger,
          ),
          const SizedBox(width: 4),
          Text(
            context.local.chat_not_delivered,
            style: ProtonStyles.captionMedium(
              color: context.colors.signalDanger,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => widget.onRetry?.call(message),
            child: Text(
              context.local.retry,
              style: ProtonStyles.captionSemibold(
                color: context.colors.protonBlue,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => widget.onDiscard?.call(message),
            child: Text(
              context.local.chat_discard,
              style: ProtonStyles.captionSemibold(
                color: _ChatWidgetConstants.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionPills(BuildContext context, RoomChatMessage message) {
    final entries = message.reactions.entries
        .where((e) => e.value.isNotEmpty)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final entry in entries)
            _buildReactionPill(
              context,
              message.id,
              entry.key,
              entry.value.length,
              entry.value.contains(widget.localIdentity),
            ),
        ],
      ),
    );
  }

  Widget _buildReactionPill(
    BuildContext context,
    String messageId,
    String emoji,
    int count,
    bool mine,
  ) {
    return GestureDetector(
      onTap: () => widget.onToggleReaction(messageId, emoji),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: ShapeDecoration(
          color: mine
              ? _ChatWidgetConstants.reactionPillActiveColor
              : _ChatWidgetConstants.reactionPillColor,
          shape: RoundedRectangleBorder(
            side: mine
                ? const BorderSide(color: _ChatWidgetConstants.sendButtonColor)
                : BorderSide.none,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: ProtonStyles.captionSemibold(
                color: context.colors.textNorm,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissingRootAvatar({
    double size = _ChatWidgetConstants.avatarSize,
  }) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: _ChatWidgetConstants.missingRootAvatarColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            _ChatWidgetConstants.borderRadiusAvatar,
          ),
        ),
      ),
      child: Center(
        child: Text(
          '', // we can add an icon text here if required
          textAlign: TextAlign.center,
          style: ProtonStyles.captionMedium(
            color: _ChatWidgetConstants.textTertiary,
          ),
        ),
      ),
    );
  }

  bool _isLocalUser(String identity) =>
      identity.isNotEmpty && identity == widget.localIdentity;

  String _resolveDisplayName(String name, String identity) {
    if (_isLocalUser(identity)) {
      final local = widget.localName.trim();
      if (local.isNotEmpty && local != widget.localIdentity) return local;
    }
    final trimmed = name.trim();
    if (trimmed.isNotEmpty && trimmed != identity) return trimmed;
    return context.local.unknown;
  }

  Widget _buildLocalUserAvatar({
    double size = _ChatWidgetConstants.avatarSize,
  }) {
    return _buildAvatarForIdentity(
      widget.localName,
      widget.localIdentity,
      size: size,
    );
  }

  Widget _buildAvatarForIdentity(
    String name,
    String identity, {
    double size = _ChatWidgetConstants.avatarSize,
  }) {
    final displayName = _resolveDisplayName(name, identity);
    final initials = _initialsCache.putIfAbsent(
      displayName,
      () => getInitials(displayName),
    );
    final colors = _colorCache.putIfAbsent(identity, () {
      final c = getParticipantDisplayColors(context, identity.hashCode);
      return (
        backgroundColor: c.backgroundColor,
        profileTextColor: c.profileTextColor,
      );
    });
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: colors.backgroundColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            _ChatWidgetConstants.borderRadiusAvatar,
          ),
        ),
      ),
      child: Center(
        child: Text(
          initials,
          textAlign: TextAlign.center,
          style: ProtonStyles.captionMedium(color: colors.profileTextColor),
        ),
      ),
    );
  }

  Widget _buildMessageHeader(
    String authorName,
    int timestamp, {
    required String identity,
  }) {
    final displayName = _resolveDisplayName(authorName, identity);
    final metaStyle = ProtonStyles.captionMedium(
      color: _ChatWidgetConstants.textTertiary,
    );
    final spans = <InlineSpan>[
      TextSpan(
        text: displayName,
        style: ProtonStyles.body2Semibold(color: context.colors.textNorm),
      ),
    ];
    if (_isLocalUser(identity)) {
      spans.addAll([
        const TextSpan(text: ' '),
        TextSpan(text: context.local.you, style: metaStyle),
      ]);
    }
    spans.addAll([
      const TextSpan(text: ' '),
      TextSpan(text: _formatMessageTime(timestamp), style: metaStyle),
    ]);
    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildMessageContent(String text, {bool selectable = true}) {
    final style = ProtonStyles.body2Medium(color: context.colors.textWeak);
    final linkStyle = ProtonStyles.body2Medium(
      color: context.colors.protonBlue,
    ).copyWith(decoration: TextDecoration.underline);
    if (!selectable) {
      return Linkify(
        text: text,
        style: style,
        linkStyle: linkStyle,
        onOpen: _handleLinkOpen,
      );
    }
    return SelectableLinkify(
      text: text,
      style: style,
      linkStyle: linkStyle,
      onOpen: _handleLinkOpen,
    );
  }

  Widget _buildSystemMessageContent(
    RoomChatMessage message, {
    bool selectable = true,
  }) {
    final text = message.message;
    // Special UI case for join/leave messages
    if (message.joinLeaveKind != null &&
        message.joinLeaveMeetingName != null &&
        message.joinLeaveMeetingName!.isNotEmpty) {
      final prefix = message.joinLeaveKind == ChatJoinLeaveKind.joined
          ? context.local.chat_system_joined_prefix
          : context.local.chat_system_left_prefix;
      final style = ProtonStyles.body2Medium(color: context.colors.textWeak);
      final rich = TextSpan(
        style: style,
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: message.joinLeaveMeetingName,
            style: style.copyWith(
              color: _ChatWidgetConstants.joinLeaveMeetingNameColor,
            ),
          ),
        ],
      );
      if (!selectable) {
        return Text.rich(rich);
      }
      return SelectableText.rich(rich);
    }

    if (text.isEmpty) return const SizedBox.shrink();
    final style = ProtonStyles.body2Medium(color: context.colors.textWeak);
    if (!selectable) {
      return Text(text, style: style);
    }
    return SelectableText(text, style: style);
  }

  // ── Message actions (long-press): quick reactions + Reply / Copy ──
  Future<void> _showMessageActions(
    BuildContext context,
    RoomChatMessage message,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildQuickReactionBar(sheetContext, message),
                const SizedBox(height: 12),
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: _ChatWidgetConstants.inputBackgroundColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (message.isRoot)
                        _buildActionTile(
                          sheetContext,
                          icon: Icons.reply,
                          label: context.local.chat_reply,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            _controller.setThreadExpanded(message.id, true);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _replyFocus(message.id).requestFocus();
                            });
                          },
                        ),
                      _buildActionTile(
                        sheetContext,
                        icon: Icons.copy,
                        label: context.local.chat_copy_text,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          Clipboard.setData(
                            ClipboardData(text: message.message),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickReactionBar(
    BuildContext sheetContext,
    RoomChatMessage message,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ShapeDecoration(
        color: _ChatWidgetConstants.inputBackgroundColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final emoji in kQuickReactionEmojis)
            GestureDetector(
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onToggleReaction(message.id, emoji);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
            ),
          GestureDetector(
            onTap: () {
              Navigator.of(sheetContext).pop();
              _openEmojiPickerFor(message.id, isReaction: true);
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: const ShapeDecoration(
                color: _ChatWidgetConstants.reactionPillColor,
                shape: CircleBorder(),
              ),
              child: Icon(
                Icons.more_horiz,
                color: sheetContext.colors.textWeak,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.colors.textNorm),
            const SizedBox(width: 14),
            Text(
              label,
              style: ProtonStyles.body2Medium(color: context.colors.textNorm),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the emoji picker. When [isReaction] is true, the chosen emoji is
  /// toggled as a reaction on [id] (a message id). Otherwise it is inserted
  /// into [insertInto] (a reply composer).
  Future<void> _openEmojiPickerFor(
    String id, {
    required bool isReaction,
    TextEditingController? insertInto,
  }) async {
    final emoji = await showChatEmojiPicker(context);
    if (emoji == null) return;
    if (isReaction) {
      await widget.onToggleReaction(id, emoji);
    } else if (insertInto != null) {
      final selection = insertInto.selection;
      final text = insertInto.text;
      if (selection.isValid) {
        insertInto.text = text.replaceRange(
          selection.start,
          selection.end,
          emoji,
        );
        insertInto.selection = TextSelection.collapsed(
          offset: selection.start + emoji.length,
        );
      } else {
        insertInto.text = text + emoji;
      }
    }
  }

  Future<void> _handleLinkOpen(LinkableElement link) async {
    try {
      final uri = Uri.parse(link.url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      l.logger.e('Error opening link: $e');
    }
  }

  String _formatMessageTime(int timestamp) {
    final messageTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final isToday =
        messageTime.year == now.year &&
        messageTime.month == now.month &&
        messageTime.day == now.day;
    final time = context.formatLocalizedTime(messageTime);
    if (isToday) return time;
    final month = messageTime.month.toString().padLeft(2, '0');
    final day = messageTime.day.toString().padLeft(2, '0');
    return '$month-$day $time';
  }
}
