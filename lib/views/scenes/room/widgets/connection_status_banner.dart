import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';
import 'package:meet/views/scenes/room/room_state_exts.dart';

/// What to show in [ConnectionStatusBanner], in priority order.
///
/// Offline → rejoin → MLS banner states → LiveKit reconnecting → debug force-show.
class _ConnectionBannerPresentation {
  const _ConnectionBannerPresentation({
    required this.displayStatus,
    required this.showSpinner,
  });

  final Object displayStatus;
  final bool showSpinner;

  static _ConnectionBannerPresentation? resolve({
    required bool isNetworkAvailable,
    required bool isRejoining,
    required RejoinStatus? rejoinStatus,
    required MlsSyncState? mlsSyncState,
    required bool isLivekitReconnecting,
    required bool forceShow,
  }) {
    if (!isNetworkAvailable) {
      return const _ConnectionBannerPresentation(
        displayStatus: 'no_network',
        showSpinner: false,
      );
    }
    if (isRejoining && rejoinStatus != null) {
      return _ConnectionBannerPresentation(
        displayStatus: rejoinStatus,
        showSpinner: true,
      );
    }
    if (mlsSyncState != null && mlsSyncState.shouldShowBanner) {
      return _ConnectionBannerPresentation(
        displayStatus: mlsSyncState,
        showSpinner: false,
      );
    }
    if (isLivekitReconnecting) {
      return const _ConnectionBannerPresentation(
        displayStatus: 'livekit_reconnecting',
        showSpinner: true,
      );
    }
    if (forceShow) {
      return _ConnectionBannerPresentation(
        displayStatus: mlsSyncState ?? 'force_show',
        showSpinner: mlsSyncState == null,
      );
    }
    return null;
  }
}

String _bannerMessage(BuildContext context, Object displayStatus) {
  if (displayStatus is RejoinStatus) {
    return displayStatus.message(context);
  }
  if (displayStatus is MlsSyncState) {
    return displayStatus.message(context);
  }
  if (displayStatus == 'livekit_reconnecting') {
    return context.local.trying_to_reconnect;
  }
  if (displayStatus == 'no_network') {
    return context.local.no_connection;
  }
  return 'Connection status';
}

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
      (MlsSyncState?, bool, RejoinStatus?, bool, bool, bool, bool)
    >(
      selector: (state) => (
        state.mlsSyncState,
        state.isRejoining,
        state.rejoinStatus,
        state.isRoomInitialized && state.isTrackInitialized,
        state.forceShowConnectionStatusBanner,
        state.isLiveKitReconnecting,
        state.isNetworkAvailable,
      ),
      builder: (context, data) {
        final mlsSyncState = data.$1;
        final isRejoining = data.$2;
        final rejoinStatus = data.$3;
        final isRoomReady = data.$4;
        final forceShow = data.$5;
        final isLivekitReconnecting = data.$6;
        final isNetworkAvailable = data.$7;

        final presentation = _ConnectionBannerPresentation.resolve(
          isNetworkAvailable: isNetworkAvailable,
          isRejoining: isRejoining,
          rejoinStatus: rejoinStatus,
          mlsSyncState: mlsSyncState,
          isLivekitReconnecting: isLivekitReconnecting,
          forceShow: forceShow,
        );

        if (presentation == null || !isRoomReady) {
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
                  _bannerMessage(context, presentation.displayStatus),
                  style: ProtonStyles.captionSemibold(
                    color: context.colors.textNorm,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (presentation.showSpinner)
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
