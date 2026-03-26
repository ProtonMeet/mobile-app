import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/alerts/join_meeting_error.dart';
import 'package:meet/views/components/alerts/meeting_locked_error.dart';
import 'package:meet/views/components/loading_view.dart';
import 'package:meet/views/scenes/core/responsive_v2.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/room/room.dart';

import 'waiting_room_bloc.dart';
import 'waiting_room_error_code.dart';
import 'waiting_room_event.dart';
import 'waiting_room_state.dart';

class WaitingRoomPage extends StatefulWidget {
  final JoinArgs args;
  final PreJoinType preJoinType;
  final bool isVideoEnabled;
  final bool isAudioEnabled;
  final bool enableE2EE;
  final MediaDevice? selectedVideoDevice;
  final MediaDevice? selectedAudioDevice;
  final MediaDevice? selectedSpeakerDevice;
  final CameraPosition? selectedVideoPosition;
  final VideoParameters selectedVideoParameters;
  final bool isSpeakerPhoneEnabled;

  const WaitingRoomPage(
    this.args, {
    required this.preJoinType,
    required this.isVideoEnabled,
    required this.isAudioEnabled,
    required this.enableE2EE,
    this.selectedVideoDevice,
    this.selectedAudioDevice,
    this.selectedSpeakerDevice,
    this.selectedVideoPosition,
    this.selectedVideoParameters = VideoParametersPresets.h720_169,
    this.isSpeakerPhoneEnabled = false,
    super.key,
  });

  @override
  State<WaitingRoomPage> createState() => _WaitingRoomPageState();
}

class _WaitingRoomPageState extends State<WaitingRoomPage>
    with SingleTickerProviderStateMixin {
  String? _previousError;
  bool _hasNavigated = false;
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => WaitingRoomBloc()
        ..add(
          WaitingRoomInitialized(
            args: widget.args,
            preJoinType: widget.preJoinType,
            isVideoEnabled: widget.isVideoEnabled,
            isAudioEnabled: widget.isAudioEnabled,
            enableE2EE: widget.enableE2EE,
            selectedVideoDevice: widget.selectedVideoDevice,
            selectedAudioDevice: widget.selectedAudioDevice,
            selectedSpeakerDevice: widget.selectedSpeakerDevice,
            selectedVideoPosition: widget.selectedVideoPosition,
            selectedVideoParameters: widget.selectedVideoParameters,
            isSpeakerPhoneEnabled: widget.isSpeakerPhoneEnabled,
          ),
        ),
      child: MultiBlocListener(
        listeners: [
          BlocListener<WaitingRoomBloc, WaitingRoomState>(
            listenWhen: (previous, current) =>
                previous.error != current.error && current.error != null,
            listener: (context, state) {
              // Show error dialog when an error occurs (only once per error)
              if (state.error != null &&
                  state.error != _previousError &&
                  context.mounted) {
                _previousError = state.error;

                // Disconnect from LiveKit room immediately to prevent other users from seeing failed participant
                context.read<WaitingRoomBloc>().add(
                  WaitingRoomDisconnectOnError(),
                );

                final meetingLink =
                    state.meetLink?.meetingLinkName ??
                    state.args.meetingLink?.meetingLinkName;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    if (state.error ==
                        WaitingRoomErrorCode.meetingLocked.name) {
                      showMeetingLockedBottomSheet(
                        context,
                        meetingLink: meetingLink,
                      );
                    } else {
                      showJoinMeetingErrorBottomSheet(
                        context,
                        errorMessage: state.error!,
                        errorDetails: state.error,
                        meetingLink: meetingLink,
                      );
                    }
                  }
                });
              }
            },
          ),
          BlocListener<WaitingRoomBloc, WaitingRoomState>(
            listenWhen: (previous, current) =>
                !previous.shouldNavigateToRoom &&
                current.shouldNavigateToRoom &&
                current.room != null &&
                current.roomKey != null,
            listener: (context, state) {
              // Navigate only once when conditions are met
              if (!_hasNavigated && context.mounted) {
                _hasNavigated = true;
                _navigateToRoom(context, state);
              }
            },
          ),
        ],
        child: BlocBuilder<WaitingRoomBloc, WaitingRoomState>(
          builder: (context, state) {
            return Scaffold(
              backgroundColor: context.colors.interActionWeakMinor3,
              body: SafeArea(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: ResponsiveV2(
                    xlarge: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: _buildWaitingContent(context, state),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _navigateToRoom(BuildContext context, WaitingRoomState state) {
    // Pre-build the room page widget for smoother transition
    final roomPage = RoomPage(
      state.room!,
      state.listener!,
      state.roomKey!,
      widget.args.displayName,
      state.meetLink!.meetingLinkName,
      state.meetInfo!,
      state.meetLink!,
      widget.preJoinType,
      isSpeakerPhoneEnabled: widget.isSpeakerPhoneEnabled,
    );

    // Use a custom fade transition for smoother animation
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => roomPage,
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Fade transition for smoother navigation
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
      ),
    ).then((_) {
      // Mark navigation as complete when route is popped
      if (mounted) {
        _hasNavigated = false;
      }
    });

    // Notify bloc that navigation has occurred
    context.read<WaitingRoomBloc>().add(WaitingRoomNavigateToRoom());
  }

  Widget _buildWaitingContent(BuildContext context, WaitingRoomState state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Use RepaintBoundary to isolate text updates from animation
        LoadingView(
          title: state.currentStatus,
          description: state.statusDescription.isNotEmpty
              ? state.statusDescription
              : null,
        ),
      ],
    );
  }
}
