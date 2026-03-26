import 'dart:math';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/remote_video_track_extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/participant/participant.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

/// Represents a pending subscription update request
class _PendingSubscriptionUpdate {
  final List<ParticipantInfo> visibleWidgets;
  final List<ParticipantInfo> currentWidgets;

  _PendingSubscriptionUpdate({
    required this.visibleWidgets,
    required this.currentWidgets,
  });
}

class ResponsiveCameraLayout extends StatefulWidget {
  final List<ParticipantInfo> participantTracks;
  final Room room;
  final bool hideNavigationIcons;
  final Map<String, ParticipantReaction> reactionsByIdentity;
  final Map<String, bool> raisedHandsByIdentity;

  const ResponsiveCameraLayout({
    required this.participantTracks,
    required this.room,
    this.hideNavigationIcons = false,
    this.reactionsByIdentity = const {},
    this.raisedHandsByIdentity = const {},
    super.key,
  });

  @override
  State<ResponsiveCameraLayout> createState() => _ResponsiveCameraLayoutState();
}

class _ResponsiveCameraLayoutState extends State<ResponsiveCameraLayout> {
  int currentPage = 0;
  String? _lastVisibleSignature;
  String? _lastCurrentSignature;
  // Track pending unsubscribe operations to cancel them if track becomes visible again
  final Map<String, Future<void>?> _pendingUnsubscribes = {};
  // Prevent concurrent subscription updates
  bool _isUpdatingSubscriptions = false;
  // Queue for pending subscription updates during concurrent execution
  _PendingSubscriptionUpdate? _pendingUpdate;

  @override
  void didUpdateWidget(ResponsiveCameraLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.participantTracks.length < oldWidget.participantTracks.length) {
      setState(() {
        currentPage = 0;
      });
    }
  }

  //TODO(fix): this logic need move to bloc because here could be triggered multiple times and refesh UI too often in large room.
  /// Subscribe to video tracks for visible participants and unsubscribe from others
  Future<void> _updateVideoSubscriptions(
    List<ParticipantInfo> visibleWidgets,
    List<ParticipantInfo> currentWidgets,
  ) async {
    // If already updating, queue this request
    if (_isUpdatingSubscriptions) {
      _pendingUpdate = _PendingSubscriptionUpdate(
        visibleWidgets: visibleWidgets,
        currentWidgets: currentWidgets,
      );
      return;
    }

    // Collect identities of visible participants
    final visibleIdentities = visibleWidgets
        .map((track) => track.participant.identity)
        .toSet();

    final currentIdentities = currentWidgets
        .map((track) => track.participant.identity)
        .toSet();

    // Skip if visible widgets haven't changed
    final visibleSignature = visibleIdentities.join(',');
    final currentSignature = currentIdentities.join(',');

    if (visibleSignature == _lastVisibleSignature &&
        currentSignature == _lastCurrentSignature) {
      return;
    }

    _isUpdatingSubscriptions = true;

    try {
      _lastVisibleSignature = visibleSignature;
      _lastCurrentSignature = currentSignature;

      // Get a snapshot of all remote participants to ensure we process all of them
      // This includes newly joined participants that might not be in visibleWidgets yet
      final allRemoteParticipants = widget.room.remoteParticipants.values
          .toList();

      // Subscribe to visible participants and unsubscribe from others
      for (final remoteParticipant in allRemoteParticipants) {
        final shouldSubscribe = visibleIdentities.contains(
          remoteParticipant.identity,
        );

        final isCurrentWidgetTrack = currentIdentities.contains(
          remoteParticipant.identity,
        );

        // Process all video track publications for this participant
        final videoPublications = remoteParticipant.videoTrackPublications
            .toList();

        for (final pub in videoPublications) {
          // Always keep screen sharing tracks subscribed
          if (pub.isScreenShare) {
            if (!pub.subscribed) {
              pub.subscribe();
            }
            continue;
          }

          // For regular video tracks, subscribe only if visible
          if (shouldSubscribe) {
            // Cancel any pending unsubscribe for this participant
            final pendingUnsubscribe =
                _pendingUnsubscribes[remoteParticipant.identity];
            if (pendingUnsubscribe != null) {
              // Mark as cancelled by removing from pending map
              _pendingUnsubscribes.remove(remoteParticipant.identity);
            }

            // Subscribe if not already subscribed
            if (!pub.subscribed) {
              pub.subscribe();
              await pub.waitForVideoTrackBound();
            }

            // Set appropriate quality and FPS based on visibility and simulcast support
            if (isCurrentWidgetTrack) {
              // High quality for currently visible/active tracks
              if (pub.videoQuality != VideoQuality.HIGH) {
                pub.setVideoQuality(VideoQuality.HIGH);
              }
              if (pub.fps != 30) {
                pub.setVideoFPS(30);
              }
            } else {
              // Lower quality for cached/background tracks to save bandwidth
              // Only switch quality when simulcast layers exist (meaningful quality change)
              if (pub.simulcasted && pub.videoQuality != VideoQuality.LOW) {
                pub.setVideoQuality(VideoQuality.LOW);
              }
              if (pub.fps != 8) {
                pub.setVideoFPS(8);
              }
            }
          } else {
            // Track is not visible - schedule unsubscribe with delay
            if (pub.subscribed) {
              // Cancel any existing pending unsubscribe for this participant
              _pendingUnsubscribes.remove(remoteParticipant.identity);

              // Add a delay before unsubscribing to prevent rapid subscribe/unsubscribe cycles
              // Capture current state to avoid race conditions with async callback
              final currentVisibleTracks = List<ParticipantInfo>.from(
                currentWidgets,
              );
              final currentCachedTracks = List<ParticipantInfo>.from(
                visibleWidgets,
              );

              // Capture the publication reference for the delayed callback
              final pubRef = pub;
              final participantIdentity = remoteParticipant.identity;

              final unsubscribeFuture = Future.delayed(delayUnsubscribeTrack, () {
                // Check if this operation was cancelled (track became visible again)
                if (!_pendingUnsubscribes.containsKey(participantIdentity)) {
                  return; // Operation was cancelled
                }
                // Remove from pending operations
                _pendingUnsubscribes.remove(participantIdentity);

                // Double-check that the track is still not needed before unsubscribing
                // This prevents unsubscribing tracks that became visible again during the delay
                final stillVisible = currentVisibleTracks.any(
                  (track) => track.participant.identity == participantIdentity,
                );
                final stillCached = currentCachedTracks.any(
                  (track) => track.participant.identity == participantIdentity,
                );

                // Only unsubscribe if still not needed and still subscribed
                if (!stillVisible && !stillCached && pubRef.subscribed) {
                  try {
                    pubRef.unsubscribe();
                  } catch (e) {
                    l.logger.e(
                      'Failed to unsubscribe track for participant $participantIdentity: $e',
                    );
                  }
                }
              });

              // Track the pending unsubscribe operation
              _pendingUnsubscribes[participantIdentity] = unsubscribeFuture;
            }
          }
        }
      }
    } finally {
      _isUpdatingSubscriptions = false;

      // Process any queued update request
      if (_pendingUpdate != null) {
        final pending = _pendingUpdate!;
        _pendingUpdate = null;
        // Schedule the queued update for next frame to avoid stack overflow
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateVideoSubscriptions(
              pending.visibleWidgets,
              pending.currentWidgets,
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight - 10;
        final minWidgetWidth = 48;

        int bestCol = 1;
        int maxWidgets = 1;
        double ratio;

        final orientation = MediaQuery.of(context).orientation;

        final configurations = orientation == Orientation.portrait
            ? [
                [2, 2],
                [1, 2],
                [1, 1],
              ]
            : [
                [3, 1],
                [2, 1],
                [1, 1],
              ];

        int tmpBestCol = 1;
        int tmpMaxWidgets = 1;

        for (var config in configurations) {
          final col = config[0];
          final row = config[1];
          final widgetWidth = screenWidth / col;
          final widgetHeight = screenHeight / row;

          if (widgetWidth >= minWidgetWidth &&
              widgetHeight * row <= screenHeight) {
            tmpBestCol = col;
            tmpMaxWidgets = col * row;
            break;
          }
        }

        bestCol = tmpBestCol;
        maxWidgets = tmpMaxWidgets;

        // Default ratio for non-mobile; may be adjusted for last page below
        final tileW = screenWidth / bestCol;
        final tileH = screenHeight / (maxWidgets / bestCol);
        ratio = tileW / tileH;

        // Pagination
        final totalParticipants = widget.participantTracks.length;
        final totalPages = (totalParticipants / maxWidgets).ceil().clamp(
          1,
          1 << 30,
        );
        // Clamp currentPage in case grid/page-size changed (rotation)
        if (currentPage >= totalPages) {
          currentPage = totalPages - 1;
        } else if (currentPage < 0) {
          currentPage = 0;
        }

        final start = currentPage * maxWidgets;
        final end = min(start + maxWidgets, totalParticipants);
        final currentWidgets = widget.participantTracks.sublist(start, end);

        // Pre-subscribe to a larger window: current page + 2 pages ahead/behind
        // This ensures tracks are ready before switching pages
        final cachePages = 2;
        final cacheStart = max(start - (maxWidgets * cachePages), 0);
        final cacheEnd = min(
          end + (maxWidgets * cachePages),
          totalParticipants,
        );
        final availableWidgets = widget.participantTracks.sublist(
          cacheStart,
          cacheEnd,
        );
        // Subscribe to visible participants and unsubscribe from others
        // Use addPostFrameCallback to ensure this runs after the frame is built
        // This prevents multiple rapid calls during rebuilds
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateVideoSubscriptions(availableWidgets, currentWidgets);
          }
        });

        // Optional: on the last page for non-mobile, try to tighten ratio
        if (currentPage == totalPages - 1) {
          final configurationsForLastPage = orientation == Orientation.portrait
              ? [
                  [1, 1],
                  [1, 2],
                  [2, 2],
                ]
              : [
                  [1, 1],
                  [2, 1],
                  [3, 1],
                ];
          for (var config in configurationsForLastPage) {
            final col = config[0];
            final row = config[1];
            if (col * row >= currentWidgets.length) {
              final widgetWidth = screenWidth / col;
              final widgetHeight = screenHeight / row;
              if (widgetWidth >= minWidgetWidth &&
                  widgetHeight * row <= screenHeight) {
                bestCol = col;
                // Set ratio based on this layout
                ratio = widgetWidth / widgetHeight;
                break;
              }
            }
          }
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                physics: const ClampingScrollPhysics(),
                // Keep nearby items cached to speed up page switches
                cacheExtent: screenHeight * 3,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: bestCol,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: ratio,
                ),
                itemCount: currentWidgets.length,
                itemBuilder: (context, index) {
                  final participantTrack = currentWidgets[index];
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final itemWidth = constraints.maxWidth;
                      final itemHeight = constraints.maxHeight;
                      return RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.all(
                            0,
                          ), // keep cells tight; spacing handled by grid
                          child: KeyedSubtree(
                            key: ValueKey(
                              participantTrack.participant.identity,
                            ),
                            child: ParticipantWidget.widgetFor(
                              itemWidth,
                              itemHeight,
                              getParticipantDisplayColors(
                                context,
                                currentWidgets.indexOf(participantTrack),
                              ),
                              participantTrack,
                              showStatsLayer: false,
                              reaction:
                                  widget.reactionsByIdentity[participantTrack
                                      .participant
                                      .identity],
                              isRaisedHand:
                                  widget.raisedHandsByIdentity[participantTrack
                                      .participant
                                      .identity] ==
                                  true,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (!widget.hideNavigationIcons &&
                totalPages > 1 &&
                currentPage > 0)
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
                      onTap: () => setState(() => currentPage--),
                      child: const Icon(Icons.arrow_back_ios_rounded, size: 28),
                    ),
                  ),
                ),
              ),
            if (!widget.hideNavigationIcons &&
                totalPages > 1 &&
                currentPage < totalPages - 1)
              Positioned(
                right: 10,
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
                      onTap: () => setState(() => currentPage++),
                      child: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    // Cancel all pending unsubscribe operations
    _pendingUnsubscribes.clear();
    // Clear any pending update requests
    _pendingUpdate = null;
    _isUpdatingSubscriptions = false;
    super.dispose();
  }
}
