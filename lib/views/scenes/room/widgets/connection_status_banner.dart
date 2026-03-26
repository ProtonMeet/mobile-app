import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:meet/views/scenes/room/room_state_exts.dart';

/// Banner widget that displays network and livekit/MLS connection status
/// Shows rejoin status or MLS sync state when applicable
class ConnectionStatusBanner extends StatefulWidget {
  const ConnectionStatusBanner({super.key});

  @override
  State<ConnectionStatusBanner> createState() => _ConnectionStatusBannerState();
}

class _ConnectionStatusBannerState extends State<ConnectionStatusBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      RoomBloc,
      RoomState,
      (MlsSyncState?, bool, RejoinStatus?, bool, bool, bool)
    >(
      selector: (state) => (
        state.mlsSyncState,
        state.isRejoining,
        state.rejoinStatus,
        state.isRoomInitialized && state.isTrackInitialized,
        state.forceShowConnectionStatusBanner,
        state.isLiveKitReconnecting,
      ),
      builder: (context, data) {
        final mlsSyncState = data.$1;
        final isRejoining = data.$2;
        final rejoinStatus = data.$3;
        final isRoomReady = data.$4;
        final forceShow = data.$5;
        final isLivekitReconnecting = data.$6;

        // Determine if banner should be shown
        // Priority: 1. Force show (highest), 2. Rejoin status, 3. MLS sync state, 4. LiveKit reconnecting (lowest/general)
        final shouldShowRejoinBanner = isRejoining && rejoinStatus != null;
        final shouldShowMlsBanner =
            !shouldShowRejoinBanner &&
            mlsSyncState != null &&
            mlsSyncState.shouldShowBanner;
        final shouldShowLivekitReconnectingBanner =
            !shouldShowRejoinBanner &&
            !shouldShowMlsBanner &&
            isLivekitReconnecting;

        // If force show is enabled, always show banner (highest priority)
        final shouldShowBanner =
            forceShow ||
            shouldShowRejoinBanner ||
            shouldShowMlsBanner ||
            shouldShowLivekitReconnectingBanner;

        // Determine which status to display
        // Priority: 1. Rejoin status, 2. MLS sync state, 3. LiveKit reconnecting (general), 4. Force show (show MLS state if available, otherwise show default)
        Object? displayStatus;
        if (shouldShowRejoinBanner) {
          displayStatus = rejoinStatus;
        } else if (mlsSyncState != null && mlsSyncState.shouldShowBanner) {
          displayStatus = mlsSyncState;
        } else if (shouldShowLivekitReconnectingBanner) {
          displayStatus = 'livekit_reconnecting';
        } else if (forceShow) {
          // When force show is enabled but no other status, show MLS state if available, otherwise use a placeholder
          displayStatus = mlsSyncState ?? 'force_show';
        }

        if (!shouldShowBanner || displayStatus == null || !isRoomReady) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.all(defaultPadding),
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: context.colors.interActionWeekMinor1,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  displayStatus is RejoinStatus
                      ? displayStatus.message(context)
                      : displayStatus is MlsSyncState
                      ? displayStatus.message(context)
                      : displayStatus == 'livekit_reconnecting'
                      ? context.local.trying_to_reconnect
                      : 'Connection status', // Default message for force show when no other status
                  style: ProtonStyles.captionSemibold(
                    color: context.colors.textNorm,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (displayStatus is RejoinStatus ||
                  displayStatus == 'livekit_reconnecting' ||
                  (forceShow && displayStatus == 'force_show'))
                RotationTransition(
                  turns: _rotationController,
                  child: context.images.iconReload.svg(width: 24, height: 24),
                ),
            ],
          ),
        );
      },
    );
  }
}
