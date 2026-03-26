import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/rust/proton_meet/models/mls_sync_state.dart';
import 'package:meet/rust/proton_meet/models/rejoin_reason.dart';
import 'package:meet/views/components/alerts/rejoining_dialog.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:meet/views/scenes/room/room_state.dart';

/// Widget that provides BlocListener for reconnection-related UI events
/// Handles showing the rejoin failed dialog when rejoin fails
class RoomReconnectionListeners extends StatelessWidget {
  const RoomReconnectionListeners({
    required this.child,
    required this.onLeaveRoom,
    super.key,
  });

  final Widget child;
  final VoidCallback onLeaveRoom;

  /// Check if room connection is healthy (room connected + MLS synced)
  bool _isConnectionHealthy(RoomState state) {
    final isLivekitRoomConnected = state.room.localParticipant != null;
    final isMlsSynced = state.mlsSyncState == MlsSyncState.success;

    return isLivekitRoomConnected && isMlsSynced;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<RoomBloc, RoomState>(
      listenWhen: (prev, curr) {
        return (prev.rejoinStatus != curr.rejoinStatus &&
                curr.rejoinStatus == RejoinStatus.error &&
                curr.rejoinError != null) ||
            (prev.rejoinStatus == RejoinStatus.error &&
                curr.rejoinStatus == RejoinStatus.error &&
                (prev.mlsSyncState != curr.mlsSyncState ||
                    prev.room.localParticipant != curr.room.localParticipant));
      },
      listener: (context, state) {
        final bloc = context.read<RoomBloc>();

        // If rejoin failed and connection is now healthy, auto-clear the error
        if (state.rejoinStatus == RejoinStatus.error &&
            state.rejoinError != null &&
            _isConnectionHealthy(state)) {
          // Close dialog if it's showing
          if (state.isRejoinFailedDialogShowing && context.mounted) {
            Navigator.of(context).pop();
          }
          bloc.add(const CancelRejoinMeeting());
          return;
        }

        // Show dialog when rejoin fails (only if not already showing and connection not healthy)
        if (!state.isRejoinFailedDialogShowing &&
            state.rejoinStatus == RejoinStatus.error &&
            state.rejoinError != null &&
            !_isConnectionHealthy(state)) {
          if (context.mounted) {
            bloc.add(const SetRejoinFailedDialogShowing(isShowing: true));

            showRejoinFailedDialog(
              context,
              error: state.rejoinError!,
              onLeaveRoom: onLeaveRoom,
              onRejoin: () {
                // Check if auto reconnection feature is enabled
                if (!bloc.isMeetAutoReconnectionEnabled()) {
                  return;
                }
                // Clear failed status first (this will trigger the listener again to close dialog)
                bloc.add(const CancelRejoinMeeting());
                bloc.add(const StartRejoinMeeting(reason: RejoinReason.other));
              },
              onClose: () {
                if (bloc.state.rejoinStatus == RejoinStatus.error) {
                  bloc.add(const CancelRejoinMeeting());
                }
                // Trigger the websocket recoonect if user close the dialog manually
                // If the websocket reconnect is successful, the dialog will not showup again
                // If it's not successful, the dialog will showup again
                bloc.add(const TriggerWebsocketReconnect());
              },
            );
          }
        }
      },
      child: child,
    );
  }
}
