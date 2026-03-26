import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:meet/constants/app.keys.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';
import 'package:meet/views/scenes/utils.dart';
import 'package:url_launcher/url_launcher.dart';

class ChatWidget extends StatefulWidget {
  final List<types.Message> messages;
  final void Function(types.PartialText) onSendPressed;
  final List<ParticipantInfo>? participantTracks;

  const ChatWidget({
    required this.messages,
    required this.onSendPressed,
    this.participantTracks,
    super.key,
  });

  @override
  State<ChatWidget> createState() => _ChatWidgetState();
}

class _ChatWidgetConstants {
  static const double headerHeight = 51.0;
  static const double inputButtonSize = 54.0;
  static const double sendIconSize = 24.0;
  static const double avatarSize = 40.0;
  static const double emptyStateIconSize = 48.0;

  static const double horizontalPadding = 24.0;
  static const double verticalPadding = 8.0;
  static const double inputPadding = 8.0;
  static const double inputBottomPadding = 4.0;
  static const double spacingSmall = 4.0;
  static const double spacingMedium = 8.0;
  static const double spacingLarge = 16.0;
  static const double spacingXLarge = 70.0;

  static const double borderRadiusMedium = 24.0;
  static const double borderRadiusLarge = 40.0;
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
  static const double borderColorAlpha = 0.03;
}

class _ChatWidgetState extends State<ChatWidget> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _inputScrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isAtTop = true;

  // Cache reversed messages to avoid recalculating on every build
  List<types.Message>? _cachedReversedMessages;
  int? _cachedMessagesLength;

  List<types.Message> get _filteredMessages => widget.messages;

  List<types.Message> get _reversedMessages {
    if (_cachedReversedMessages == null ||
        _cachedMessagesLength != widget.messages.length) {
      _cachedReversedMessages = widget.messages.reversed.toList();
      _cachedMessagesLength = widget.messages.length;
    }
    return _cachedReversedMessages!;
  }

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _inputFocusNode.addListener(_onFocusChanged);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final isAtTop = _scrollController.position.pixels <= 0;
    if (_isAtTop != isAtTop) {
      setState(() {
        _isAtTop = isAtTop;
      });
    }
  }

  void _onFocusChanged() {
    if (_inputFocusNode.hasFocus) {
      // Use a small delay to avoid scroll during keyboard animation
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _inputFocusNode.hasFocus) {
          _scheduleScrollToBottom();
        }
      });
    }
  }

  bool _isScrollingToBottom = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Scroll to bottom when chat opens - use immediate scroll for initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToBottom(immediate: true);
      }
    });
  }

  @override
  void didUpdateWidget(ChatWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Invalidate cache when messages change
    if (widget.messages.length != oldWidget.messages.length) {
      _cachedReversedMessages = null;
      _cachedMessagesLength = null;
      // Only scroll if new message was added (length increased)
      if (widget.messages.length > oldWidget.messages.length) {
        _scheduleScrollToBottom();
      }
    }
  }

  void _scheduleScrollToBottom() {
    if (_isScrollingToBottom) return; // Prevent multiple simultaneous scrolls
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

    // If maxScrollExtent is 0, the ListView isn't ready yet
    if (maxScrollExtent == 0) return;

    final currentPosition = _scrollController.position.pixels;
    final scrollDistance = (maxScrollExtent - currentPosition).abs();

    // If already at bottom (within 5px), no need to scroll
    if (scrollDistance < 5.0) {
      _isScrollingToBottom = false;
      return;
    }

    // Use faster animation for shorter distances, slightly longer for large scrolls
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
            if (mounted) {
              _isScrollingToBottom = false;
            }
          });
    }
  }

  void _onTextChanged() {
    // Debounce to avoid excessive operations during typing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_inputScrollController.hasClients && _inputFocusNode.hasFocus) {
        final text = _textController.text;
        final hasMultipleLines = text.contains('\n');
        if (hasMultipleLines &&
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
    _textController.removeListener(_onTextChanged);
    _inputFocusNode.removeListener(_onFocusChanged);
    _scrollController.removeListener(_onScroll);
    _textController.dispose();
    _scrollController.dispose();
    _inputScrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleSendPressed() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    widget.onSendPressed(types.PartialText(text: text));
    _textController.clear();
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
        // Landscape without keyboard - use full screen height
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

  Decoration _buildContainerDecoration(BuildContext context) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(_ChatWidgetConstants.borderRadiusMedium),
      topRight: Radius.circular(_ChatWidgetConstants.borderRadiusMedium),
    );

    return BoxDecoration(
      color: context.colors.blurBottomSheetBackground,
      border: Border.all(
        color: Colors.white.withValues(
          alpha: _ChatWidgetConstants.borderColorAlpha,
        ),
      ),
      borderRadius: borderRadius,
    );
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
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(
                  _ChatWidgetConstants.borderRadiusLarge,
                ),
                topRight: Radius.circular(
                  _ChatWidgetConstants.borderRadiusLarge,
                ),
              ),
              child: RepaintBoundary(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: _buildContainerDecoration(context),
                    child: GestureDetector(
                      onTap: () => FocusScope.of(context).unfocus(),
                      behavior: HitTestBehavior.deferToChild,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: RepaintBoundary(
                              child: _buildMessageListWithSliverAppBar(
                                context,
                                isLandscape,
                              ),
                            ),
                          ),
                          SafeArea(
                            child: RepaintBoundary(
                              child: _buildInputField(
                                context,
                                inputBottomPadding,
                              ),
                            ),
                          ),
                        ],
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
  }

  Widget _buildHeaderWithoutHandle(bool isLandscape) {
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        height:
            _ChatWidgetConstants.headerHeight +
            (!isLandscape ? 36.0 : _ChatWidgetConstants.spacingMedium),
        padding: EdgeInsets.only(
          left: _ChatWidgetConstants.horizontalPadding,
          right: _ChatWidgetConstants.horizontalPadding,
          bottom: _ChatWidgetConstants.horizontalPadding,
          top: !isLandscape ? 36.0 : _ChatWidgetConstants.spacingMedium,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Chat',
            style: ProtonStyles.headline(
              fontSize: 18,
              color: context.colors.textNorm,
            ),
          ),
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
          left: _ChatWidgetConstants.horizontalPadding,
          right: _ChatWidgetConstants.horizontalPadding,
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

  // Cache text field heights to avoid recalculating on every build
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
    if (_cachedTextFieldHeights != null) {
      return _cachedTextFieldHeights!;
    }
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
            horizontal: _ChatWidgetConstants.horizontalPadding,
            vertical: _ChatWidgetConstants.spacingLarge,
          ),
          decoration: ShapeDecoration(
            color: _ChatWidgetConstants.inputBackgroundColor,
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: Colors.white.withValues(
                  alpha: _ChatWidgetConstants.borderColorAlpha,
                ),
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
                    hintText: 'Type an encrypted message…',
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

  Widget _buildMessageListWithSliverAppBar(
    BuildContext context,
    bool isLandscape,
  ) {
    final filteredMessages = _filteredMessages;

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              toolbarHeight:
                  _ChatWidgetConstants.headerHeight +
                  (!isLandscape ? 36.0 : _ChatWidgetConstants.spacingMedium),
              expandedHeight:
                  _ChatWidgetConstants.headerHeight +
                  (!isLandscape ? 36.0 : _ChatWidgetConstants.spacingMedium),
              flexibleSpace: SizedBox.expand(
                child: ClipRRect(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(
                      _ChatWidgetConstants.borderRadiusMedium,
                    ),
                    topRight: Radius.circular(
                      _ChatWidgetConstants.borderRadiusMedium,
                    ),
                  ),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: context.colors.clear,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(
                              _ChatWidgetConstants.borderRadiusMedium,
                            ),
                            topRight: Radius.circular(
                              _ChatWidgetConstants.borderRadiusMedium,
                            ),
                          ),
                        ),
                      ),
                      child: _buildHeaderWithoutHandle(isLandscape),
                    ),
                  ),
                ),
              ),
            ),
            if (filteredMessages.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(context),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _ChatWidgetConstants.horizontalPadding,
                ),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final message = _reversedMessages[index];
                      if (message is types.TextMessage) {
                        return RepaintBoundary(
                          child: _buildMessageBubble(message),
                        );
                      }
                      if (message is types.SystemMessage) {
                        return RepaintBoundary(
                          child: _buildSystemMessageBubble(message),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                    childCount: filteredMessages.length,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries:
                        false, // We're adding RepaintBoundary manually
                  ),
                ),
              ),
          ],
        ),
        // Handle area that allows bottom sheet drag to work.
        // Wrap in AbsorbPointer so gestures bypass the chat content
        // and bubble up to the modal sheet for dragging.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height:
              _ChatWidgetConstants.headerHeight +
              (!isLandscape ? 36.0 : _ChatWidgetConstants.spacingMedium),
          child: AbsorbPointer(
            child: Stack(
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
                  top: !isLandscape ? 36.0 : _ChatWidgetConstants.spacingMedium,
                  left: 0,
                  right: 0,
                  height: _ChatWidgetConstants.headerHeight,
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: _ChatWidgetConstants.horizontalPadding,
                      right: _ChatWidgetConstants.horizontalPadding,
                      bottom: _ChatWidgetConstants.horizontalPadding,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Chat',
                        style: ProtonStyles.headline(
                          fontSize: 18,
                          color: context.colors.textNorm,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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

  Widget _buildMessageBubble(types.TextMessage message) {
    final authorName = message.author.firstName ?? context.local.unknown;
    final authorId = message.author.id;
    final initials = getInitials(authorName);
    // Use index-based colors matching WebApp pattern
    final colors = getParticipantDisplayColorsByIdentity(
      context,
      authorId,
      widget.participantTracks,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: _ChatWidgetConstants.verticalPadding,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(
            initials,
            colors.backgroundColor,
            colors.profileTextColor,
          ),
          const SizedBox(width: _ChatWidgetConstants.spacingLarge),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMessageHeader(authorName, message.createdAt ?? 0),
                const SizedBox(height: _ChatWidgetConstants.spacingSmall),
                _buildMessageContent(message.text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(String initials, Color bgColor, Color textColor) {
    return Container(
      width: _ChatWidgetConstants.avatarSize,
      height: _ChatWidgetConstants.avatarSize,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: bgColor,
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
          style: ProtonStyles.body2Medium(color: textColor),
        ),
      ),
    );
  }

  Widget _buildMessageHeader(String authorName, int timestamp) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$authorName ',
            style: ProtonStyles.body2Semibold(color: context.colors.textNorm),
          ),
          TextSpan(
            text: _formatMessageTime(timestamp),
            style: ProtonStyles.captionMedium(
              color: _ChatWidgetConstants.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageContent(String text) {
    return SelectableLinkify(
      text: text,
      style: ProtonStyles.body2Medium(color: context.colors.textWeak),
      linkStyle: ProtonStyles.body2Medium(
        color: context.colors.protonBlue,
      ).copyWith(decoration: TextDecoration.underline),
      onOpen: _handleLinkOpen,
    );
  }

  Widget _buildSystemMessageBubble(types.SystemMessage message) {
    final authorName = message.author.firstName ?? context.local.unknown;
    final authorId = message.author.id;
    final initials = getInitials(authorName);
    // Use index-based colors matching WebApp pattern
    final colors = getParticipantDisplayColorsByIdentity(
      context,
      authorId,
      widget.participantTracks,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: _ChatWidgetConstants.verticalPadding,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(
            initials,
            colors.backgroundColor,
            colors.profileTextColor,
          ),
          const SizedBox(width: _ChatWidgetConstants.spacingLarge),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMessageHeader(authorName, message.createdAt ?? 0),
                const SizedBox(height: _ChatWidgetConstants.spacingSmall),
                _buildSystemMessageContent(message.text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMessageContent(String text) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    // Split text by spaces to get words
    final words = text.split(' ');
    if (words.isEmpty) {
      return const SizedBox.shrink();
    }

    // Build TextSpan children with proper colors
    final textSpans = <TextSpan>[];

    for (int i = 0; i < words.length; i++) {
      if (i > 0) {
        textSpans.add(const TextSpan(text: ' '));
      }

      final word = words[i];
      final isFirstWord = i == 0;

      textSpans.add(
        TextSpan(
          text: word,
          style: ProtonStyles.body2Medium(
            color: isFirstWord
                ? context.colors.textWeak
                : context.colors.protonBlue,
          ),
        ),
      );
    }

    return SelectableText.rich(TextSpan(children: textSpans));
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

    final hour = _formatHour(messageTime.hour);
    final period = messageTime.hour >= 12 ? 'PM' : 'AM';
    final minute = messageTime.minute.toString().padLeft(2, '0');
    final time = '$hour:$minute $period';

    if (isToday) {
      return time;
    }

    final month = messageTime.month.toString().padLeft(2, '0');
    final day = messageTime.day.toString().padLeft(2, '0');
    return '$month-$day $time';
  }

  int _formatHour(int hour) {
    if (hour > 12) return hour - 12;
    if (hour == 0) return 12;
    return hour;
  }
}
