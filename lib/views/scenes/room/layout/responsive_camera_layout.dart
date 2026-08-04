import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/remote_video_track_extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/subscribe_retry_backoff.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';
import 'package:meet/views/scenes/room/layout/camera_grid_layout_config.dart';
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
  final bool compactParticipantOverlay;
  final bool isPipMode;
  final Map<String, ParticipantReaction> reactionsByIdentity;
  final Map<String, bool> raisedHandsByIdentity;
  final void Function(String)? onLowerHandByIdentity;

  /// When set, keep this remote participant's camera subscribed (iOS PiP off-grid).
  final String iosPipRemoteCameraSubscriptionIdentity;

  const ResponsiveCameraLayout({
    required this.participantTracks,
    required this.room,
    this.hideNavigationIcons = false,
    this.compactParticipantOverlay = false,
    this.isPipMode = false,
    this.reactionsByIdentity = const {},
    this.raisedHandsByIdentity = const {},
    this.onLowerHandByIdentity,
    this.iosPipRemoteCameraSubscriptionIdentity = '',
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
  Timer? _bindRetryTimer;
  int _bindRetryAttempt = 0;

  /// True when a visible remote participant has a camera publication that is
  /// not subscribed or whose media track is not yet bound.
  bool _hasUnboundVisibleCameraTracks(Set<String> visibleIdentities) {
    for (final remoteParticipant in widget.room.remoteParticipants.values) {
      if (!visibleIdentities.contains(remoteParticipant.identity)) {
        continue;
      }
      for (final pub in remoteParticipant.videoTrackPublications) {
        if (pub.isScreenShare) continue;
        if (!pub.subscribed || pub.track == null) {
          return true;
        }
      }
    }
    return false;
  }

  void _scheduleSubscriptionRetry(
    List<ParticipantInfo> visibleWidgets,
    List<ParticipantInfo> currentWidgets,
  ) {
    if (!mounted) return;
    if (_bindRetryAttempt >= maxVideoSubscriptionBindRetries) {
      l.logger.w(
        '[ResponsiveCameraLayout] visible camera bind retries exhausted '
        '(attempt=$_bindRetryAttempt)',
      );
      return;
    }

    _bindRetryTimer?.cancel();
    final delay = subscribeRetryBackoffWithJitter(
      baseDelay: videoSubscriptionBindRetryDelay,
      retryIndex: _bindRetryAttempt,
    );
    _bindRetryAttempt++;
    // Force the next pass to run even when visible identities are unchanged.
    _lastVisibleSignature = null;
    _lastCurrentSignature = null;

    l.logger.d(
      '[ResponsiveCameraLayout] scheduling camera bind retry in '
      '${delay.inMilliseconds}ms (attempt=$_bindRetryAttempt)',
    );

    _bindRetryTimer = Timer(delay, () {
      if (!mounted) return;
      _updateVideoSubscriptions(visibleWidgets, currentWidgets);
    });
  }

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
        currentSignature == _lastCurrentSignature &&
        !_hasUnboundVisibleCameraTracks(currentIdentities)) {
      return;
    }

    _isUpdatingSubscriptions = true;

    try {
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

            if (!pub.subscribed) {
              pub.subscribe();
            }
            // Wait when subscribed-but-not-yet-bound (RPC in flight) or after
            // a fresh subscribe() above.
            if (pub.track == null) {
              final bound = await pub.waitForVideoTrackBound();
              if (!bound) {
                l.logger.w(
                  '[ResponsiveCameraLayout] camera bind timeout for '
                  '${remoteParticipant.identity} sid=${pub.sid}',
                );
              }
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

      if (_hasUnboundVisibleCameraTracks(currentIdentities)) {
        _scheduleSubscriptionRetry(visibleWidgets, currentWidgets);
      } else {
        _bindRetryAttempt = 0;
        _bindRetryTimer?.cancel();
        _bindRetryTimer = null;
        _lastVisibleSignature = visibleSignature;
        _lastCurrentSignature = currentSignature;
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
        final orientation = MediaQuery.of(context).orientation;
        // Grid presets and breakpoints: see CameraGridLayoutConfig.
        final minWidgetWidth = CameraGridLayoutConfig.minTileWidth(screenWidth);
        final configurations = CameraGridLayoutConfig.configurationsFor(
          screenWidth,
          orientation,
        );

        final selected = CameraGridLayoutConfig.selectBest(
          screenWidth: screenWidth,
          screenHeight: screenHeight,
          configurations: configurations,
          minWidgetWidth: minWidgetWidth,
        );
        var bestCol = selected.cols;
        final maxWidgets = selected.maxWidgets;
        double ratio;

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

        // Pre-subscribe to nearby pages; radius scales down on large grids.
        // See CameraGridLayoutConfig.subscriptionCachePageRadius.
        final cachePages = CameraGridLayoutConfig.subscriptionCachePageRadius(
          maxWidgets,
        );
        final cacheStart = max(start - (maxWidgets * cachePages), 0);
        final cacheEnd = min(
          end + (maxWidgets * cachePages),
          totalParticipants,
        );
        final availableWidgets = widget.participantTracks.sublist(
          cacheStart,
          cacheEnd,
        );

        final pipId = widget.iosPipRemoteCameraSubscriptionIdentity;
        ParticipantInfo? pipExtra;
        if (pipId.isNotEmpty) {
          for (final t in widget.participantTracks) {
            if (t.participant.identity == pipId) {
              pipExtra = t;
              break;
            }
          }
        }

        List<ParticipantInfo> availableForSubscribe = availableWidgets;
        List<ParticipantInfo> currentForSubscribe = currentWidgets;
        if (pipExtra != null) {
          if (!availableForSubscribe.any(
            (t) => t.participant.identity == pipId,
          )) {
            availableForSubscribe = [...availableForSubscribe, pipExtra];
          }
          if (!currentForSubscribe.any(
            (t) => t.participant.identity == pipId,
          )) {
            currentForSubscribe = [...currentForSubscribe, pipExtra];
          }
        }

        // Subscribe to visible participants and unsubscribe from others
        // Use addPostFrameCallback to ensure this runs after the frame is built
        // This prevents multiple rapid calls during rebuilds
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateVideoSubscriptions(
              availableForSubscribe,
              currentForSubscribe,
            );
          }
        });

        if (currentPage == totalPages - 1) {
          final lastPageConfigurations =
              CameraGridLayoutConfig.lastPageConfigurationsFor(
                screenWidth,
                orientation,
              );
          final lastPage = CameraGridLayoutConfig.selectBestForLastPage(
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            configurations: lastPageConfigurations,
            minWidgetWidth: minWidgetWidth,
            itemCount: currentWidgets.length,
          );
          if (lastPage != null) {
            bestCol = lastPage.cols;
            ratio = lastPage.ratio;
          }
        }

        return Stack(
          children: [
            Positioned.fill(
              child: GridView.builder(
                scrollCacheExtent: ScrollCacheExtent.pixels(screenHeight * 3),
                padding: const EdgeInsets.all(8),
                physics: const ClampingScrollPhysics(),
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
                                participantTrack.participant.identity.hashCode,
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
                              compactOverlay: widget.compactParticipantOverlay,
                              isPipMode: widget.isPipMode,
                              onLowerHand: widget.onLowerHandByIdentity == null
                                  ? null
                                  : () {
                                      widget.onLowerHandByIdentity!(
                                        participantTrack.participant.identity,
                                      );
                                    },
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
    _bindRetryTimer?.cancel();
    // Cancel all pending unsubscribe operations
    _pendingUnsubscribes.clear();
    // Clear any pending update requests
    _pendingUpdate = null;
    _isUpdatingSubscriptions = false;
    super.dispose();
  }
}
