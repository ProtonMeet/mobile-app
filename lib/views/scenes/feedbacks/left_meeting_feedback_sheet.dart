import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/managers/services/call.quality.form.dart';
import 'package:meet/models/user_activity.model.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet_v2.dart';
import 'package:meet/views/scenes/feedbacks/feedback_low_detail.dart';
import 'package:meet/views/scenes/feedbacks/feedback_sheet_summary.dart';

typedef OnRejoinMeeting = void Function();
typedef OnStartMeetingNow = void Function();

enum _LeftMeetingFeedbackStage { summary, lowDetail }

/// Returns `true` only when [submitMeetingFeedbackToApi] completed successfully for this sheet.
Future<bool> showLeftMeetingBottomSheet(
  BuildContext context, {
  required FrbUpcomingMeeting meetingLink,
  required OnRejoinMeeting onRejoinMeeting,
  required OnStartMeetingNow onStartMeetingNow,
  required bool isHost,
  required bool isPaidUser,
  required bool isMeetMobileShowStartMeetingButtonEnabled,
  bool isKickedOut = false,
  bool showRejoin = true,
  String? title,
  String? content,
  String meetingLinkName = '',
  bool meetFeedbackOnSkipEnabled = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (sheetContext) {
      void closeSheet(skipStoreReviewPrompt) {
        Navigator.of(sheetContext).pop(skipStoreReviewPrompt);
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final isLandscape = context.isLandscape;
          final maxHeight = isLandscape
              ? context.height - 20
              : context.height - 160;
          return _LeftMeetingSheetContent(
            key: ValueKey('${meetingLink.id}-left-meeting'),
            maxHeight: maxHeight,
            meetingLinkName: meetingLinkName,
            meetFeedbackOnSkipEnabled: meetFeedbackOnSkipEnabled,
            isHost: isHost,
            isPaidUser: isPaidUser,
            isKickedOut: isKickedOut,
            isMeetMobileShowStartMeetingButtonEnabled:
                isMeetMobileShowStartMeetingButtonEnabled,
            showRejoin: showRejoin,
            title: title,
            content: content,
            onClose: closeSheet,
            onRejoinMeeting: () {
              closeSheet(true);
              onRejoinMeeting();
            },
            onStartMeetingNow: () {
              closeSheet(true);
              onStartMeetingNow();
            },
          );
        },
      );
    },
  );
  return result ?? false;
}

class _LeftMeetingSheetContent extends StatefulWidget {
  const _LeftMeetingSheetContent({
    required this.maxHeight,
    required this.meetingLinkName,
    required this.meetFeedbackOnSkipEnabled,
    required this.isHost,
    required this.isPaidUser,
    required this.isKickedOut,
    required this.isMeetMobileShowStartMeetingButtonEnabled,
    required this.showRejoin,
    required this.onClose,
    required this.onRejoinMeeting,
    required this.onStartMeetingNow,
    super.key,
    this.title,
    this.content,
  });

  final double maxHeight;
  final String meetingLinkName;
  final bool meetFeedbackOnSkipEnabled;
  final bool isHost;
  final bool isPaidUser;
  final bool isKickedOut;
  final bool isMeetMobileShowStartMeetingButtonEnabled;
  final bool showRejoin;
  final String? title;
  final String? content;
  final ValueChanged<bool> onClose;
  final VoidCallback onRejoinMeeting;
  final VoidCallback onStartMeetingNow;

  @override
  State<_LeftMeetingSheetContent> createState() =>
      _LeftMeetingSheetContentState();
}

class _LeftMeetingSheetContentState extends State<_LeftMeetingSheetContent> {
  _LeftMeetingFeedbackStage _stage = _LeftMeetingFeedbackStage.summary;
  int? _rating;
  final Set<String> _selected = {};
  String _comment = '';
  bool _optionalDetails = false;
  bool _submitting = false;
  final FocusNode _optionalCommentFocus = FocusNode();
  final GlobalKey _lowFeedbackSubmitKey = GlobalKey();

  bool get _feedbackEnabled => widget.meetingLinkName.isNotEmpty;

  @override
  void dispose() {
    _optionalCommentFocus.dispose();
    super.dispose();
  }

  void _onToggleOptionalDetails() {
    final expanded = !_optionalDetails;
    setState(() => _optionalDetails = expanded);
    if (!expanded) {
      _optionalCommentFocus.unfocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _optionalCommentFocus.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final target = _lowFeedbackSubmitKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: 1.0,
          );
        }
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          final ctx = _lowFeedbackSubmitKey.currentContext;
          if (ctx != null && ctx.mounted) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: 1.0,
            );
          }
        });
      });
    });
  }

  Future<void> _submitHigh(int score) async {
    if (!_feedbackEnabled || _submitting) return;
    setState(() => _submitting = true);
    try {
      await submitMeetingFeedbackToApi(
        context: context,
        meetingLinkName: widget.meetingLinkName,
        score: score,
        feedbackParts: const [],
      );
      final skipStoreReviewPrompt = score < kFeedbackDislikeStarsMaxExclusive;
      if (mounted) widget.onClose(skipStoreReviewPrompt);
    } catch (e) {
      if (mounted) {
        showMeetingFeedbackApiError(context, e);

        /// return true to avoid show store review prompt
        widget.onClose(true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitLow({required bool skip}) async {
    if (!_feedbackEnabled || _submitting) return;
    setState(() => _submitting = true);
    try {
      final score = _rating ?? 1;
      if (skip) {
        if (widget.meetFeedbackOnSkipEnabled) {
          await submitMeetingFeedbackToApi(
            context: context,
            meetingLinkName: widget.meetingLinkName,
            score: score,
            feedbackParts: _selected.toList(),
          );
        } else {
          /// return true to avoid show store review prompt
          if (mounted) widget.onClose(true);
          return;
        }
      } else {
        final parts = <String>[..._selected];
        if (_optionalDetails && _comment.trim().isNotEmpty) {
          parts.add(_comment.trim());
        }
        await submitMeetingFeedbackToApi(
          context: context,
          meetingLinkName: widget.meetingLinkName,
          score: score,
          feedbackParts: parts,
        );
      }
      if (mounted) widget.onClose(true);
    } catch (e) {
      if (mounted) {
        showMeetingFeedbackApiError(context, e);

        /// return true to avoid show store review prompt
        widget.onClose(true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onStarTap(int value) {
    if (!_feedbackEnabled || _submitting) return;
    setState(() => _rating = value);
    if (value >= kMeetingFeedbackRatingThreshold) {
      _submitHigh(value);
    } else {
      setState(() => _stage = _LeftMeetingFeedbackStage.lowDetail);
    }
  }

  String _subtitleText(BuildContext context) {
    if (!widget.isPaidUser && !widget.isHost) {
      return context.local.left_meeting_subtitle_guest_free;
    }
    if (widget.isPaidUser && !widget.isHost) {
      return context.local.left_meeting_subtitle_guest_paid;
    }
    if (!widget.isPaidUser && widget.isHost) {
      return context.local.left_meeting_subtitle_host_free;
    }
    return context.local.left_meeting_subtitle_host_paid;
  }

  void _onOptionToggled(String label) {
    setState(() {
      if (_selected.contains(label)) {
        _selected.remove(label);
      } else {
        _selected.add(label);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final sheetHeight = (widget.maxHeight - bottomInset).clamp(320.0, 900.0);
    final isLandscape = context.isLandscape;

    final kicked = widget.isKickedOut;
    final titleText =
        widget.title ??
        (kicked
            ? context.local.kicked_out_bottom_sheet_title
            : context.local.left_meeting_title);
    final contentText =
        widget.content ??
        (kicked
            ? context.local.kicked_out_bottom_sheet_content
            : _subtitleText(context));
    final showRejoin = kicked ? false : widget.showRejoin;
    final showStart =
        !kicked &&
        !widget.isPaidUser &&
        !widget.isHost &&
        showRejoin &&
        widget.isMeetMobileShowStartMeetingButtonEnabled;

    final List<Widget> slivers;
    if (_stage == _LeftMeetingFeedbackStage.summary) {
      slivers = buildLeftMeetingSummarySlivers(
        context: context,
        titleText: titleText,
        contentText: contentText,
        showStartMeetingButton: showStart,
        showRejoin: showRejoin,
        onStartMeetingNow: widget.onStartMeetingNow,
        onRejoinMeeting: widget.onRejoinMeeting,
        feedbackEnabled: !kicked && _feedbackEnabled,
        submitting: _submitting,
        rating: _rating,
        onStarTap: _onStarTap,
        isKickedOut: kicked,
      );
    } else {
      slivers = buildLeftMeetingLowFeedbackSlivers(
        context: context,
        rating: _rating,
        selectedLabels: _selected,
        onOptionToggled: _onOptionToggled,
        optionalDetailsExpanded: _optionalDetails,
        onToggleOptionalDetails: _onToggleOptionalDetails,
        onCommentChanged: (v) => _comment = v,
        submitting: _submitting,
        onSubmit: () => _submitLow(skip: false),
        onSkip: () => _submitLow(skip: true),
        optionalCommentFocus: _optionalCommentFocus,
        submitButtonKey: _lowFeedbackSubmitKey,
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: BaseBottomSheetV2.withPinnedSliverScroll(
        key: ValueKey(_stage),
        isLandscape: isLandscape,
        modalOnBackdropTap: () => widget.onClose(true),
        modalMaxHeight: sheetHeight,
        outerEnableHandleDragPassthrough: true,
        blurSigma: 14,
        borderSideAlpha: 0.04,
        toolbarHeight: 76,
        onPinnedHeaderBack: _stage == _LeftMeetingFeedbackStage.lowDetail
            ? () => setState(() => _stage = _LeftMeetingFeedbackStage.summary)
            : null,
        pinnedHeaderBackEnabled: !_submitting,
        slivers: slivers,
      ),
    );
  }
}
