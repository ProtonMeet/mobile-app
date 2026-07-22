import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/constants/test_ids.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/views/components/alerts/media_permission_dialog.dart';
import 'package:meet/views/components/alerts/meeting_locked_error.dart';
import 'package:meet/views/components/close_button_v1.dart';
import 'package:meet/views/components/custom.loading.dart';
import 'package:meet/views/components/test_id.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:meet/views/scenes/signin/auth_state.dart';

import 'prejoin_arguments.dart';
import 'prejoin_bloc.dart';
import 'prejoin_event.dart';
import 'prejoin_screen.dart';
import 'prejoin_state.dart';

class PreJoinPage extends StatefulWidget {
  final PreJoinBloc bloc;
  final AuthBloc authBloc;
  final JoinArgs? joinArgs;
  static const String routeName = '/preJoin';
  const PreJoinPage({
    required this.bloc,
    required this.authBloc,
    this.joinArgs,
    super.key,
  });

  @override
  State<PreJoinPage> createState() => _PreJoinPageState();
}

class _PreJoinPageState extends State<PreJoinPage> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _roomNameController;
  late final FocusNode _displayNameFocusNode;
  late final FocusNode _meetingLinkFocusNode;

  /// Route args (e.g. rejoin from room) carry the last in-meeting name; auth may
  /// be empty for guests. Prefer args over auth so PreJoinInitialized can load
  /// prefs / fallbacks correctly.
  String get _displayNameForBlocInit {
    final fromArgs = (widget.joinArgs?.displayName ?? '').trim();
    if (fromArgs.isNotEmpty) {
      return fromArgs;
    }
    return widget.authBloc.state.displayName;
  }

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _roomNameController = TextEditingController();
    _displayNameFocusNode = FocusNode();
    _meetingLinkFocusNode = FocusNode();
    _displayNameController.text = _displayNameForBlocInit;

    // Defer heavy initialization until after first frame to make navigation feel instant
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Dispatch initialization event after page is shown
        if (widget.joinArgs != null) {
          widget.bloc.add(
            PreJoinInitialized(widget.joinArgs!, _displayNameForBlocInit),
          );
        }

        // Sync display name from BLoC state
        if ((_displayNameController.text.isEmpty ||
                widget.bloc.state.shouldOverrideAuthDisplayName) &&
            widget.bloc.state.displayName.isNotEmpty &&
            !_displayNameFocusNode.hasFocus) {
          _displayNameController.text = widget.bloc.state.displayName;
        }
      }
    });
  }

  @override
  void dispose() {
    unawaited(widget.bloc.close());
    _displayNameController.dispose();
    _roomNameController.dispose();
    _displayNameFocusNode.dispose();
    _meetingLinkFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handlePreJoinClose(BuildContext context) async {
    if (widget.bloc.state.isInWaitingRoomAdmission) {
      await widget.bloc.leaveWaitingRoomAdmission();
    }
    if (context.mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // Provide existing instances safely
        BlocProvider<PreJoinBloc>.value(value: widget.bloc),
        BlocProvider<AuthBloc>.value(value: widget.authBloc),
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<AuthBloc, AuthState>(
            listenWhen: (prev, curr) =>
                prev.displayName != curr.displayName &&
                curr.displayName.isNotEmpty,
            listener: (context, state) {
              // Only update controller if it's empty and user is not actively typing
              if (_displayNameController.text.isEmpty &&
                  !_displayNameFocusNode.hasFocus) {
                _displayNameController.text = state.displayName;
                widget.bloc.add(UpdateDisplayName(state.displayName));
              }
            },
          ),
          BlocListener<PreJoinBloc, PreJoinState>(
            listenWhen: (prev, curr) {
              // Trigger when:
              // 1. Display name changes and is not empty
              // 2. Loading completes (isLoading: true -> false) and we have a display name
              return (prev.displayName != curr.displayName &&
                      curr.displayName.isNotEmpty) ||
                  (prev.isLoading &&
                      !curr.isLoading &&
                      curr.displayName.isNotEmpty);
            },
            listener: (context, state) {
              // Sync display name from BLoC state to controller if controller is empty
              // (e.g. saved preference or auth name after init).
              if ((_displayNameController.text.isEmpty ||
                      state.shouldOverrideAuthDisplayName) &&
                  !_displayNameFocusNode.hasFocus &&
                  state.displayName.isNotEmpty) {
                _displayNameController.text = state.displayName;
              }
            },
          ),
          BlocListener<PreJoinBloc, PreJoinState>(
            listenWhen: (prev, curr) =>
                prev.isLoading &&
                !curr.isLoading &&
                curr.displayName.trim().isEmpty,
            listener: (context, state) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _displayNameFocusNode.requestFocus();
                }
              });
            },
          ),
          BlocListener<PreJoinBloc, PreJoinState>(
            listenWhen: (prev, curr) =>
                prev.error != curr.error &&
                curr.error != null &&
                curr.error!.isNotEmpty,
            listener: (context, state) {
              LocalToast.showToast(context, state.error!);
            },
          ),
          BlocListener<PreJoinBloc, PreJoinState>(
            listenWhen: (prev, curr) =>
                !prev.shouldShowMeetingLockedBottomSheet &&
                curr.shouldShowMeetingLockedBottomSheet,
            listener: (context, state) {
              final meetingLink = state.meetingLink?.meetingLinkName;
              showMeetingLockedBottomSheet(context, meetingLink: meetingLink);
              widget.bloc.add(PreJoinMeetingLockedBottomSheetConsumed());
            },
          ),
          BlocListener<PreJoinBloc, PreJoinState>(
            listenWhen: (prev, curr) =>
                !prev.shouldShowJoinRequestRejectedNotification &&
                curr.shouldShowJoinRequestRejectedNotification,
            listener: (context, state) {
              context.showGlobalNotification(
                context.local.waiting_room_join_request_rejected,
                backgroundColor: context.colors.notificationError,
              );
              widget.bloc.add(PreJoinJoinRequestRejectedNotificationConsumed());
            },
          ),
          BlocListener<PreJoinBloc, PreJoinState>(
            listenWhen: (prev, curr) =>
                !prev.shouldShowWaitingRoomAdmissionTimedOutNotification &&
                curr.shouldShowWaitingRoomAdmissionTimedOutNotification,
            listener: (context, state) {
              context.showGlobalNotification(
                context.local.waiting_room_admission_timed_out,
                backgroundColor: context.colors.notificationError,
              );
              widget.bloc.add(
                PreJoinWaitingRoomAdmissionTimedOutNotificationConsumed(),
              );
            },
          ),
          BlocListener<PreJoinBloc, PreJoinState>(
            listenWhen: (prev, curr) =>
                prev.shouldShowCameraPermissionSettings !=
                    curr.shouldShowCameraPermissionSettings &&
                curr.shouldShowCameraPermissionSettings,
            listener: (context, state) async {
              await showMediaPermissionSettingsDialog(
                context,
                cameraDenied: !state.isCameraPermissionGranted,
                microphoneDenied: !state.isMicrophonePermissionGranted,
                onReturned: () {},
              );
              if (context.mounted) {
                widget.bloc.add(CameraPermissionSettingsConsumed());
              }
            },
          ),
          BlocListener<PreJoinBloc, PreJoinState>(
            listenWhen: (prev, curr) =>
                prev.shouldShowMicrophonePermissionSettings !=
                    curr.shouldShowMicrophonePermissionSettings &&
                curr.shouldShowMicrophonePermissionSettings,
            listener: (context, state) async {
              await showMediaPermissionSettingsDialog(
                context,
                cameraDenied: !state.isCameraPermissionGranted,
                microphoneDenied: !state.isMicrophonePermissionGranted,
                onReturned: () {},
              );
              if (context.mounted) {
                widget.bloc.add(MicrophonePermissionSettingsConsumed());
              }
            },
          ),
        ],
        child: BlocSelector<PreJoinBloc, PreJoinState, bool>(
          selector: (state) => state.isInWaitingRoomAdmission,
          builder: (context, isInWaitingRoomAdmission) {
            return PopScope(
              canPop: !isInWaitingRoomAdmission,
              onPopInvokedWithResult: (didPop, _) async {
                if (didPop) {
                  return;
                }
                await _handlePreJoinClose(context);
              },
              child: BlocSelector<AuthBloc, AuthState, AuthState>(
                selector: (s) => s,
                builder: (context, state) {
                  return TestId(
                    id: TestIds.prejoinScreen,
                    child: Scaffold(
                      backgroundColor: context.colors.backgroundNorm,
                      resizeToAvoidBottomInset: true,
                      body: SafeArea(
                        child: Stack(
                          children: [
                            ColoredBox(
                              color: context.colors.clear,
                              child: PreJoinScreen(
                                bloc: widget.bloc,
                                authBloc: widget.authBloc,
                                displayNameController: _displayNameController,
                                roomNameController: _roomNameController,
                                displayNameFocusNode: _displayNameFocusNode,
                                meetingLinkFocusNode: _meetingLinkFocusNode,
                              ),
                            ),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: _PreJoinTopBar(
                                onClose: () => _handlePreJoinClose(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PreJoinTopBar extends StatelessWidget {
  const _PreJoinTopBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<
      PreJoinBloc,
      PreJoinState,
      ({
        bool showRoomNameLoading,
        String roomName,
        String meetingLinkName,
        String? meetingLinkUrl,
        PreJoinType type,
      })
    >(
      selector: (state) {
        final roomName = state.roomName.trim();
        return (
          showRoomNameLoading:
              roomName.isEmpty &&
              (state.isJoinAuthenticating ||
                  state.waitingRoomAdmissionPhase ==
                      WaitingRoomAdmissionPhase.hostNotStarted),
          roomName: roomName,
          meetingLinkName: state.meetingLink?.meetingLinkName.trim() ?? '',
          meetingLinkUrl: state.meetingLinkUrl,
          type: state.preJoinType,
        );
      },
      builder: (context, data) {
        final meetingCode = data.meetingLinkName;
        final copyText = (data.meetingLinkUrl?.trim().isNotEmpty ?? false)
            ? data.meetingLinkUrl!.trim()
            : meetingCode;

        return Padding(
          padding: const EdgeInsets.only(left: 8, right: 16),
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                if (data.type == PreJoinType.join) ...[
                  Expanded(
                    child: data.showRoomNameLoading
                        ? _PreJoinLoadingTitle(
                            label: context.local.loading.trim(),
                          )
                        : data.roomName.isNotEmpty
                        ? Text(
                            data.roomName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ProtonStyles.body2Semibold(
                              color: context.colors.protonBlue,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (meetingCode.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      meetingCode,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ProtonStyles.body2Medium(
                        color: context.colors.textWeak,
                      ),
                    ),
                    TestId(
                      id: TestIds.prejoinCopyMeetingCode,
                      button: true,
                      child: IconButton(
                        onPressed: copyText.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(
                                  ClipboardData(text: copyText),
                                ).then((_) {
                                  if (context.mounted) {
                                    LocalToast.showToast(
                                      context,
                                      context.local.copied_to_clipboard,
                                    );
                                  }
                                });
                              },
                        icon: context.images.iconCopy.svg20(
                          color: context.colors.interActionNorm,
                        ),
                      ),
                    ),
                  ],
                ] else
                  const Spacer(),
                CloseButtonV1(
                  testId: TestIds.prejoinClose,
                  onPressed: onClose,
                  backgroundColor: Colors.transparent,
                  iconSize: 24,
                  iconColor: context.colors.textNorm.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PreJoinLoadingTitle extends StatelessWidget {
  const _PreJoinLoadingTitle({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ProtonStyles.body2Semibold(
                color: context.colors.protonBlue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CustomLoading(
            size: 16,
            strokeWidth: 2,
            color: context.colors.protonBlue,
          ),
        ],
      ),
    );
  }
}
