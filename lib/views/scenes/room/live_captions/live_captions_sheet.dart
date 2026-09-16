import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/constants/test_ids.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/models/live_captions/live_captions_models.dart';
import 'package:meet/rust/proton_meet/models/meet_participant.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/components/test_id.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/utils.dart';

class _LiveCaptionsSheetLayout {
  static const double topCornerRadius = 24;
  static const double borderAlpha = 0.03;
  static const double blurSigma = 10;
  static const double horizontalPadding = 16;
  static const double avatarSize = 32;
  static const double lineSpacing = 16;

  /// Floor for short screens so the header always fits.
  static const double minHeight = 120;

  /// Distance from the bottom of the list that still counts as "following".
  static const double followThreshold = 40;

  static const Duration snapAnimation = Duration(milliseconds: 220);
}

/// In-meeting captions sheet, styled like the other room bottom sheets.
///
/// The sheet is permanently mounted while captions are on: it rests at 20% of
/// the screen height and snaps to 50% / 80% when dragged, but never closes.
/// Turning it off goes through the controls overflow menu (or meeting
/// settings), which clears [RoomState.liveCaptionsWanted].
class LiveCaptionsSheet extends StatefulWidget {
  const LiveCaptionsSheet({
    required this.transcriptions,
    required this.participantNamesByIdentity,
    required this.onSave,
    this.onOpenSettings,
    super.key,
  });

  /// Screen-height fractions the sheet snaps to; the first one is the default.
  static const List<double> snapFractions = [0.2, 0.5, 0.8];

  final Transcriptions transcriptions;
  final Map<String, MeetParticipant> participantNamesByIdentity;
  final VoidCallback onSave;
  final VoidCallback? onOpenSettings;

  @override
  State<LiveCaptionsSheet> createState() => _LiveCaptionsSheetState();
}

class _LiveCaptionsSheetState extends State<LiveCaptionsSheet> {
  final ScrollController _scrollController = ScrollController();

  /// Settled size, as a fraction of the screen height.
  double _snapFraction = LiveCaptionsSheet.snapFractions.first;

  /// Live size while a drag is in progress; null once the drag settles.
  double? _dragFraction;

  /// Whether new lines should keep the list pinned to the newest caption.
  bool _followLatest = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(LiveCaptionsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transcriptions != oldWidget.transcriptions) {
      _scrollToLatestAfterLayout();
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    _followLatest =
        position.maxScrollExtent - position.pixels <=
        _LiveCaptionsSheetLayout.followThreshold;
  }

  void _scrollToLatestAfterLayout() {
    if (!_followLatest) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final position = _scrollController.position;
      if (position.pixels < position.maxScrollExtent) {
        position.jumpTo(position.maxScrollExtent);
      }
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    if (screenHeight <= 0) {
      return;
    }
    final current = _dragFraction ?? _snapFraction;
    setState(() {
      _dragFraction = (current - details.delta.dy / screenHeight).clamp(
        LiveCaptionsSheet.snapFractions.first,
        LiveCaptionsSheet.snapFractions.last,
      );
    });
  }

  void _onDragEnd() {
    final dragged = _dragFraction;
    setState(() {
      _dragFraction = null;
      if (dragged != null) {
        _snapFraction = _nearestSnapFraction(dragged);
      }
    });
    _scrollToLatestAfterLayout();
  }

  double _nearestSnapFraction(double fraction) {
    var nearest = LiveCaptionsSheet.snapFractions.first;
    var smallestDistance = (fraction - nearest).abs();
    for (final candidate in LiveCaptionsSheet.snapFractions.skip(1)) {
      final distance = (fraction - candidate).abs();
      if (distance < smallestDistance) {
        smallestDistance = distance;
        nearest = candidate;
      }
    }
    return nearest;
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final isDragging = _dragFraction != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final requested = (_dragFraction ?? _snapFraction) * screenHeight;
        // Never collapse below the header, and never grow past the media area.
        final height = math.min(
          math.max(requested, _LiveCaptionsSheetLayout.minHeight),
          constraints.maxHeight,
        );

        return Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedContainer(
            duration: isDragging
                ? Duration.zero
                : _LiveCaptionsSheetLayout.snapAnimation,
            curve: Curves.easeOutCubic,
            width: double.infinity,
            height: height,
            child: _buildSheet(context),
          ),
        );
      },
    );
  }

  Widget _buildSheet(BuildContext context) {
    const borderRadius = BorderRadius.vertical(
      top: Radius.circular(_LiveCaptionsSheetLayout.topCornerRadius),
    );

    return TestId(
      id: TestIds.roomLiveCaptionsSheet,
      // Opaque so taps on the sheet never reach the media area behind it
      // (which would toggle fullscreen).
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: Semantics(
          liveRegion: true,
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: borderRadius,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: _LiveCaptionsSheetLayout.blurSigma,
                  sigmaY: _LiveCaptionsSheetLayout.blurSigma,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.blurBottomSheetBackground,
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: _LiveCaptionsSheetLayout.borderAlpha,
                      ),
                    ),
                    borderRadius: borderRadius,
                  ),
                  child: Column(
                    children: [
                      _buildHeader(context),
                      Expanded(child: _buildBody(context)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Handle bar + title row. The whole strip is the drag target that resizes
  /// the sheet between the snap points.
  Widget _buildHeader(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: (_) => _onDragEnd(),
      onVerticalDragCancel: _onDragEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BottomSheetHandleBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _LiveCaptionsSheetLayout.horizontalPadding,
              0,
              8,
              4,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.local.live_captions,
                    style: ProtonStyles.headline(
                      fontSize: 18,
                      color: context.colors.textNorm,
                    ),
                  ),
                ),
                if (!kDebugMode) ...[
                  TestId(
                    id: TestIds.roomLiveCaptionsSave,
                    button: true,
                    child: TextButton(
                      onPressed: widget.onSave,
                      child: Text(
                        context.local.save,
                        style: ProtonStyles.body2Semibold(
                          color: context.colors.textNorm,
                        ),
                      ),
                    ),
                  ),
                ],
                if (widget.onOpenSettings != null)
                  TestId(
                    id: TestIds.roomLiveCaptionsSettings,
                    button: true,
                    child: IconButton(
                      onPressed: widget.onOpenSettings,
                      tooltip: context.local.live_captions_settings,
                      icon: context.images.iconSettings.svg20(
                        color: context.colors.textNorm,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final segments = widget.transcriptions.segments;
    final status = widget.transcriptions.status;

    if (status != CaptionsStatus.active || segments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            _statusMessage(context, status),
            textAlign: TextAlign.center,
            style: ProtonStyles.body2Regular(color: context.colors.textWeak),
          ),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(
        _LiveCaptionsSheetLayout.horizontalPadding,
        4,
        _LiveCaptionsSheetLayout.horizontalPadding,
        16,
      ),
      itemCount: segments.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: _LiveCaptionsSheetLayout.lineSpacing),
      itemBuilder: (context, index) {
        final segment = segments[index];
        return _CaptionLine(
          segment: segment,
          speakerName: _speakerName(segment.speakerIdentity),
        );
      },
    );
  }

  String? _speakerName(String speakerIdentity) {
    if (speakerIdentity.isEmpty) {
      return null;
    }
    final displayName = widget
        .participantNamesByIdentity[speakerIdentity]
        ?.displayName
        ?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    return speakerIdentity;
  }

  String _statusMessage(BuildContext context, CaptionsStatus status) {
    return switch (status) {
      CaptionsStatus.loading => context.local.live_captions_loading,
      CaptionsStatus.ready => context.local.live_captions_ready,
      CaptionsStatus.failing => context.local.live_captions_failing,
      CaptionsStatus.active => context.local.live_captions_ready,
    };
  }
}

/// One merged caption line: speaker avatar, speaker name, transcript text.
class _CaptionLine extends StatelessWidget {
  const _CaptionLine({required this.segment, required this.speakerName});

  final CaptionSegment segment;
  final String? speakerName;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      segment.text,
      style: ProtonStyles.body1Regular(color: context.colors.textNorm),
    );

    final name = speakerName;
    if (name == null) {
      return text;
    }

    final colors = getParticipantDisplayColors(
      context,
      segment.speakerIdentity.hashCode,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Avatar(
          initials: getInitials(name),
          backgroundColor: colors.backgroundColor,
          textColor: colors.profileTextColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$name:',
                style: ProtonStyles.body2Semibold(
                  color: colors.profileTextColor,
                ),
              ),
              const SizedBox(height: 2),
              text,
            ],
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initials,
    required this.backgroundColor,
    required this.textColor,
  });

  final String initials;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _LiveCaptionsSheetLayout.avatarSize,
      height: _LiveCaptionsSheetLayout.avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Text(
        initials,
        style: ProtonStyles.captionMedium(color: textColor),
      ),
    );
  }
}
