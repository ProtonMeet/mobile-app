import 'dart:math';

import 'package:flutter/material.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/participant/participant.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

class GridCameraLayout extends StatefulWidget {
  final List<ParticipantInfo> participantTracks;

  const GridCameraLayout({required this.participantTracks, super.key});

  @override
  State<GridCameraLayout> createState() => _GridCameraLayoutState();
}

class _GridCameraLayoutState extends State<GridCameraLayout> {
  int currentPage = 0;

  @override
  void didUpdateWidget(GridCameraLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.participantTracks.length < oldWidget.participantTracks.length) {
      setState(() {
        currentPage = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height - 70 - 50;

    final configurations = [
      [3, 2],
      [3, 1],
      [2, 3],
      [2, 2],
      [2, 1],
      [1, 3],
      [1, 2],
      [1, 1],
    ];

    final configurationsForLastPage = [
      [1, 1],
      [2, 1],
      [3, 1],
      [1, 2],
      [2, 2],
      [3, 2],
      [1, 3],
      [2, 3],
    ];

    int bestCol = 1;
    int maxWidgets = 1;

    for (var config in configurations) {
      final col = config[0];
      final row = config[1];
      final widgetWidth = screenWidth / col;
      final widgetHeight = widgetWidth / (16 / 9);

      if (widgetWidth >= 128 && widgetHeight * row <= screenHeight) {
        bestCol = col;
        maxWidgets = col * row;
        break;
      }
    }

    final totalPages = (widget.participantTracks.length / maxWidgets).ceil();
    final start = currentPage * maxWidgets;
    final end = min(start + maxWidgets, widget.participantTracks.length);
    final currentWidgets = widget.participantTracks.sublist(start, end);

    /// base on currentWidgets, calculate the bestCol and bestRow
    for (var config in configurationsForLastPage) {
      final col = config[0];
      final row = config[1];
      if (col * row >= currentWidgets.length) {
        final widgetWidth = screenWidth / col;
        final widgetHeight = widgetWidth / (16 / 9);
        if (widgetWidth >= 128 && widgetHeight * row <= screenHeight) {
          bestCol = col;
          break;
        }
      }
    }

    return Stack(
      children: [
        Center(
          child: GridView.count(
            shrinkWrap: true,
            crossAxisCount: bestCol,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            padding: const EdgeInsets.all(8),
            childAspectRatio: 16 / 9,
            children: currentWidgets
                .map(
                  (participantTrack) => LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = constraints.maxWidth;
                      final itemHeight = constraints.maxHeight;

                      return Center(
                        child: ParticipantWidget.widgetFor(
                          itemWidth - 16.0,
                          itemHeight - 16.0,
                          getParticipantDisplayColors(
                            context,
                            currentWidgets.indexOf(participantTrack),
                          ),
                          participantTrack,
                          showStatsLayer: false,
                        ),
                      );
                    },
                  ),
                )
                .toList(),
          ),
        ),
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
                      color: currentPage < totalPages - 1 ? null : Colors.grey,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
