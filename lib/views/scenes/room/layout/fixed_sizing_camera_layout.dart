import 'package:flutter/material.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/participant/participant.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

class FixedSizingCameraLayout extends StatefulWidget {
  final List<ParticipantInfo> participantTracks;
  final double spacing;
  final Map<String, ParticipantReaction> reactionsByIdentity;
  final Map<String, bool> raisedHandsByIdentity;

  const FixedSizingCameraLayout({
    required this.participantTracks,
    this.spacing = 0.4,
    this.reactionsByIdentity = const {},
    this.raisedHandsByIdentity = const {},
    super.key,
  });

  @override
  State<FixedSizingCameraLayout> createState() =>
      _FixedSizingCameraLayoutState();
}

class _FixedSizingCameraLayoutState extends State<FixedSizingCameraLayout> {
  int currentPage = 0;

  @override
  void didUpdateWidget(FixedSizingCameraLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.participantTracks.length < oldWidget.participantTracks.length) {
      setState(() {
        currentPage = 0;
      });
    }
  }

  int _calculateRowCount(int total) {
    if (total <= 2) return 1;
    if (total <= 4) return 2;
    return 2;
  }

  int _calculateColumnCount(int total) {
    if (total <= 1) return 1;
    if (total <= 4) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        final int columns = _calculateColumnCount(
          widget.participantTracks.length,
        );
        final int rows = _calculateRowCount(widget.participantTracks.length);
        final int itemsPerPage = columns * rows;
        final totalPages = (widget.participantTracks.length / itemsPerPage)
            .ceil();
        final start = currentPage * itemsPerPage;
        final end = start + itemsPerPage;
        final currentWidgets = widget.participantTracks.sublist(
          start,
          end > widget.participantTracks.length
              ? widget.participantTracks.length
              : end,
        );

        final int totalParticipants = currentWidgets.length;
        final int lastRowItems = totalParticipants % columns;

        double verticalOffset = 0.0;
        double horizontalOffset = 0.0;
        // 16:9
        double itemWidth = screenWidth / columns;
        double itemHeight = itemWidth * 9 / 16;
        final double totalHeight = itemHeight * rows;
        verticalOffset = (screenHeight - totalHeight) / 2;

        if (totalHeight > screenHeight) {
          itemHeight = screenHeight / rows;
          itemWidth = itemHeight * 16 / 9;
          verticalOffset = 0.0;
          horizontalOffset = (screenWidth - itemWidth * columns) / 2;
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ...List.generate(currentWidgets.length, (index) {
                    final row = index ~/ columns;
                    final column = index % columns;

                    /// calculate last row offset
                    double lastRowOffset = 0.0;
                    if (row == rows - 1 && lastRowItems > 0) {
                      lastRowOffset =
                          (screenWidth -
                              horizontalOffset * 2 -
                              (itemWidth * lastRowItems)) /
                          2;
                    }

                    return Positioned(
                      left:
                          column * itemWidth + horizontalOffset + lastRowOffset,
                      top: row * itemHeight + verticalOffset,
                      width: itemWidth,
                      height: itemHeight,
                      child: Container(
                        margin: EdgeInsets.all(widget.spacing),
                        child: ParticipantWidget.widgetFor(
                          itemWidth - widget.spacing * 2,
                          itemHeight - widget.spacing * 2,
                          getParticipantDisplayColors(context, index),
                          currentWidgets[index],
                          showStatsLayer: false,
                          roundedBorder: false,
                          reaction:
                              widget.reactionsByIdentity[currentWidgets[index]
                                  .participant
                                  .identity],
                          isRaisedHand:
                              widget.raisedHandsByIdentity[currentWidgets[index]
                                  .participant
                                  .identity] ==
                              true,
                        ),
                      ),
                    );
                  }),
                  ...[
                    if (totalPages > 1 && currentPage > 0)
                      Positioned(
                        left: 10,
                        bottom: 10,
                        height: 40,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(100),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: GestureDetector(
                              onTap: currentPage > 0
                                  ? () => setState(() => currentPage--)
                                  : null,
                              child: Icon(
                                Icons.arrow_back_ios_rounded,
                                size: 28,
                                color: currentPage > 0 ? null : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (totalPages > 1 && currentPage < totalPages - 1)
                      Positioned(
                        bottom: 10,
                        right: 10,
                        height: 40,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(100),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: GestureDetector(
                              onTap: currentPage < totalPages - 1
                                  ? () => setState(() => currentPage++)
                                  : null,
                              child: Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 28,
                                color: currentPage < totalPages - 1
                                    ? null
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
