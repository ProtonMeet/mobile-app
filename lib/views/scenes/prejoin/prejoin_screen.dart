import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/strings.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/managers/channels/platform_info_channel.dart';
import 'package:meet/views/components/button.v5.dart';
import 'package:meet/views/components/button.v6.dart';
import 'package:meet/views/components/custom.loading.dart';
import 'package:meet/views/components/textfield.text.v2.dart';
import 'package:meet/views/scenes/dashboard/schedule/waiting_room_sheet.dart';
import 'package:meet/views/scenes/prejoin/remember_checkbox.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:meet/views/scenes/waiting.room/waiting_room_view.dart';

import 'prejoin_arguments.dart';
import 'prejoin_bloc.dart';
import 'prejoin_event.dart';
import 'prejoin_state.dart';
import 'video_preview_with_controls.dart';

class PreJoinScreen extends StatelessWidget {
  const PreJoinScreen({
    required this.bloc,
    required this.authBloc,
    required this.displayNameController,
    required this.roomNameController,
    required this.displayNameFocusNode,
    required this.meetingLinkFocusNode,
    super.key,
  });

  static const _topSpacerHeight = 56.0;
  static const _previewBottomGap = 20.0;
  static const _topChromeHeight = _topSpacerHeight + _previewBottomGap;

  /// Join form body (display name card + optional waiting-room notice), excluding action button block.
  static const _joinFormBodyHeight = 180.0;
  static const _waitingRoomNoticeHeight = 28.0;

  /// Waiting-room admission copy (countdown / host-not-started), excluding action button block.
  static const _waitingAdmissionBodyHeight = 180.0;

  /// Gap + button + bottom padding below the main bottom content.
  static const _actionBlockHeight = 16.0 + 60.0 + 16.0;

  static bool _shouldShowWaitingRoomStatus(PreJoinState state) {
    if (state.preJoinType != PreJoinType.join ||
        !state.isMeetingHost) {
      return false;
    }
    
    return state.isWaitingRoomFeatureEnabled;
  }

  /// Keep the bottom slot tall enough for both join and waiting-room admission UIs so
  /// the video preview height does not change when admission starts.
  static double _bottomSectionHeight(PreJoinState state) {
    if (state.preJoinType == PreJoinType.create) {
      return 245.0 + _actionBlockHeight;
    }

    final joinSectionHeight =
        _joinFormBodyHeight +
        _actionBlockHeight +
        (_shouldShowWaitingRoomStatus(state) ? _waitingRoomNoticeHeight : 0.0);
    if (!state.hasWaitingRoom || state.isMeetingHost) {
      return joinSectionHeight;
    }

    final waitingSectionHeight =
        _waitingAdmissionBodyHeight + _actionBlockHeight;
    return joinSectionHeight > waitingSectionHeight
        ? joinSectionHeight
        : waitingSectionHeight;
  }

  @protected
  final PreJoinBloc bloc;
  final AuthBloc authBloc;

  final TextEditingController displayNameController;
  final TextEditingController roomNameController;
  final FocusNode displayNameFocusNode;
  final FocusNode meetingLinkFocusNode;

  @override
  Widget build(BuildContext context) {
    return BlocListener<PreJoinBloc, PreJoinState>(
      listenWhen: (previous, current) =>
          !previous.shouldNavigateToWaitingRoom &&
          current.shouldNavigateToWaitingRoom,
      listener: (context, state) async {
        bloc.add(PreJoinNavigateToWaitingRoomConsumed());
        final displayName = state.displayName.trim();
        if (displayName.isEmpty || state.meetingLink == null) {
          return;
        }
        await _navigateToWaitingRoom(
          context,
          state,
          displayName,
          reuseMlsJoin: false,
        );
      },
      child: BlocListener<PreJoinBloc, PreJoinState>(
        listenWhen: (previous, current) =>
            !previous.shouldProceedToJoinAfterHostAccept &&
            current.shouldProceedToJoinAfterHostAccept,
        listener: (context, state) async {
          bloc.add(PreJoinHostAcceptProceedConsumed());
          await _proceedToJoinAfterHostAccept(context, state);
        },
        child: BlocSelector<PreJoinBloc, PreJoinState, PreJoinState>(
        selector: (PreJoinState state) => state,
        builder: (context, state) {
          final screenWidth = MediaQuery.of(context).size.width;
          final padding = 16.0;
          const buttonHeight = 60.0;

          return LayoutBuilder(
            builder: (context, constraints) {
              final viewportHeight = constraints.maxHeight;
              final bottomSectionHeight = _bottomSectionHeight(state);

              // Calculate available preview height:
              // Top chrome: spacer (56) + preview bottom gap (20) = 76
              //
              // Bottom section (_bottomSectionHeight), kept fixed so preview does not
              // resize when switching between join form and waiting-room admission:
              //   Create: form body (245) + action block (92) = 337
              //     display name field + remember checkbox + spacing
              //   Join: form body (180) + action block (92) = 272
              //     display name card + remember-display-name switch row
              //   Join (host + waiting-room feature): + notice row (28) = 300
              //   Join (guest + waiting room): max(join section, admission section)
              //     admission body (180) + action block (92) = 272
              // Action block: gap (16) + button (60) + bottom padding (16) = 92
              //
              // previewHeight = viewportHeight - top chrome (76) - bottom section
              final previewHeight =
                  (viewportHeight - _topChromeHeight - bottomSectionHeight)
                      .clamp(300.0, double.infinity);

              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  children: [
                    const SizedBox(height: _topSpacerHeight),

                    // Video preview - fixed height shared across join and waiting-room admission.
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      child: Container(
                        decoration: BoxDecoration(color: context.colors.clear),
                        height: previewHeight,
                        child: VideoPreviewWithControls(
                          width: screenWidth - (padding * 2),
                          height: previewHeight,
                          isVideoEnabled: state.isVideoEnabled,
                          isAudioEnabled: state.isAudioEnabled,
                          isCameraPermissionGranted:
                              state.isCameraPermissionGranted,
                          isMicrophonePermissionGranted:
                              state.isMicrophonePermissionGranted,
                          videoTrack: state.videoTrack,
                          audioTrack: state.audioTrack,
                          displayName: state.displayName,
                          isCameraBackgroundBlurFeatureEnabled:
                              state.isCameraBackgroundBlurFeatureEnabled,
                          cameraBackgroundBlurEnabled:
                              state.cameraBackgroundBlurEnabled,
                          onCameraBackgroundBlurToggle: () =>
                              bloc.add(PreJoinToggleCameraBackgroundBlur()),
                          onVideoToggle: () => bloc.add(PreJoinToggleVideo()),
                          onAudioToggle: () => bloc.add(PreJoinToggleAudio()),
                          onSwapVideo: () => bloc.add(SwapVideo()),
                          videoDevices: state.videoDevices,
                          speakerDevices: state.speakerDevices,
                          selectedVideoDevice: state.selectedVideoDevice,
                          audioDevices: state.audioDevices,
                          selectedAudioDevice: state.selectedAudioDevice,
                          selectedSpeakerDevice: state.selectedSpeakerDevice,
                          onCameraPermissionRequest: () =>
                              bloc.add(RequestCameraPermission()),
                          onMicrophonePermissionRequest: () =>
                              bloc.add(RequestMicrophonePermission()),
                          onVideoDeviceChanged: (device) {
                            if (device != null) {
                              bloc.add(SelectVideoDevice(device));
                            }
                          },
                          onAudioDeviceChanged: (device) {
                            if (device != null) {
                              bloc.add(SelectAudioDevice(device));
                            }
                          },
                          onSpeakerDeviceChanged: (device) {
                            if (device != null) {
                              bloc.add(SelectSpeakerDevice(device));
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: _previewBottomGap),

                    // Fixed-height bottom slot so preview size stays stable across states.
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: padding),
                      child: SizedBox(
                        height: bottomSectionHeight,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (state.isInWaitingRoomAdmission)
                              BlocSelector<
                                PreJoinBloc,
                                PreJoinState,
                                ({
                                  WaitingRoomAdmissionPhase phase,
                                  int countdownSeconds,
                                  String joinRequestId,
                                })
                              >(
                                bloc: bloc,
                                selector: (s) => (
                                  phase: s.waitingRoomAdmissionPhase,
                                  countdownSeconds:
                                      s.waitingRoomCountdownSeconds,
                                  joinRequestId: s.waitingRoomJoinRequestId,
                                ),
                                builder: (context, admission) =>
                                    _buildWaitingRoomAdmissionContent(
                                      context,
                                      admission,
                                      screenWidth - (padding * 2),
                                      buttonHeight,
                                    ),
                              )
                            else ...[
                              if (state.preJoinType == PreJoinType.join)
                                _buildMeetingIDForJoin(context, state),
                              if (state.preJoinType == PreJoinType.create)
                                _buildMeetingIDForCreate(context, state),
                              const SizedBox(height: 16),
                              if (state.preJoinType == PreJoinType.join)
                                ButtonV6(
                                  onPressed: () =>
                                      _onJoinPressed(context, state),
                                  enable:
                                      !state.isJoinAuthenticating &&
                                      !state.isInWaitingRoomAdmission &&
                                      !PlatformInfoChannel.isInForceUpgradeState(),
                                  isLoading: state.isJoinAuthenticating,
                                  text: context.local.join_meeting_button,
                                  width: screenWidth - (padding * 2),
                                  backgroundColor:
                                      context.colors.interActionNormMajor1,
                                  borderColor: context.colors.clear,
                                  textStyle: ProtonStyles.body1Medium(
                                    color: context.colors.textInverted,
                                  ),
                                  height: buttonHeight,
                                ),
                              if (state.preJoinType == PreJoinType.create)
                                ButtonV5(
                                  onPressed: () async {
                                    if (PlatformInfoChannel.isInForceUpgradeState()) {
                                      return;
                                    }
                                    final sanitizedDisplayName =
                                        displayNameController.text.sanitize(
                                          maxLength: maxDisplayNameLength,
                                        );
                                    if (sanitizedDisplayName == null) {
                                      bloc.add(
                                        SetDisplayNameFieldError(
                                          context.local.display_name_required,
                                        ),
                                      );
                                      displayNameFocusNode.requestFocus();
                                      return;
                                    }

                                    final args = state.buildJoinLoaderArgs(
                                      authBloc: authBloc,
                                      displayName: sanitizedDisplayName,
                                    );
                                    bloc.add(
                                      UpdateDisplayName(sanitizedDisplayName),
                                    );
                                    await Navigator.push<void>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => WaitingRoomPage(
                                          args,
                                          preJoinType: PreJoinType.create,
                                          isVideoEnabled: state.isVideoEnabled,
                                          isAudioEnabled: state.isAudioEnabled,
                                          enableE2EE: true,
                                          selectedVideoDevice:
                                              state.selectedVideoDevice,
                                          selectedAudioDevice:
                                              state.selectedAudioDevice,
                                          selectedSpeakerDevice:
                                              state.selectedSpeakerDevice,
                                          selectedVideoPosition:
                                              state.selectedVideoPosition,
                                          selectedVideoParameters:
                                              state.selectedVideoParameters,
                                          cameraBackgroundBlurEnabled:
                                              state.cameraBackgroundBlurEnabled,
                                        ),
                                      ),
                                    );
                                  },
                                  enable:
                                      !PlatformInfoChannel.isInForceUpgradeState(),
                                  text: context.local.create_meeting_button,
                                  width: screenWidth - (padding * 2),
                                  backgroundColor: context.colors.protonBlue,
                                  borderColor: context.colors.clear,
                                  textStyle: ProtonStyles.body1Medium(
                                    color: context.colors.textInverted,
                                  ),
                                  height: buttonHeight,
                                ),
                              const SizedBox(height: 16),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    ),
    );
  }

  DecoratedBox _buildMeetingIDForJoin(
    BuildContext context,
    PreJoinState state,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.clear,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
      ),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.backgroundCard,
              borderRadius: const BorderRadius.all(Radius.circular(18)),
              border: Border.all(color: context.colors.borderCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.local.display_name,
                        style: ProtonStyles.bodySmallSemibold(
                          color: context.colors.textWeak,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: displayNameController,
                        focusNode: displayNameFocusNode,
                        maxLength: maxDisplayNameLength,
                        style: ProtonStyles.body1Medium(
                          color: context.colors.textNorm,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          counterText: '',
                          errorText: state.displayNameFieldError,
                          errorStyle: ProtonStyles.bodySmallSemibold(
                            color: context.colors.notificationError,
                          ),
                        ),
                        textInputAction: TextInputAction.done,
                        onChanged: (value) {
                          bloc.add(UpdateDisplayName(value));
                        },
                      ),
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: context.colors.borderCard,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.local.use_this_name_next_time,
                          style: ProtonStyles.body2Medium(
                            color: context.colors.textNorm,
                          ),
                        ),
                      ),
                      Switch.adaptive(
                        value: state.keepDisplayNameOnDevice,
                        onChanged: (value) {
                          bloc.add(ToggleKeepDisplayName(keep: value));
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_shouldShowWaitingRoomStatus(state)) ...[
            const SizedBox(height: 10),
            _buildWaitingRoomStatus(context, state),
          ],
        ],
      ),
    );
  }

  Widget _buildWaitingRoomStatus(BuildContext context, PreJoinState state) {
    final waitingRoomEnabled = state.isMeetingHost
        ? state.waitingRoomEnabled
        : state.hasWaitingRoom;
    final waitingRoomLabel = waitingRoomEnabled
        ? context.local.schedule_waiting_room_on
        : context.local.schedule_waiting_room_off;

    final label = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          waitingRoomLabel,
          style: ProtonStyles.body1Medium(color: context.colors.protonBlue),
        ),
      ),
    );

    if (!state.isMeetingHost || !state.isWaitingRoomFeatureEnabled) {
      return label;
    }

    return GestureDetector(
      onTap: () {
        showWaitingRoomSheet(
          context,
          selected: state.waitingRoomEnabled,
          isOnOptionEnabled: state.isMeetingHost, // state.isPaidUser
          onSelect: (enabled) {
            bloc.add(WaitingRoomChanged(enabled));
          },
        );
      },
      child: label,
    );
  }

  Widget _buildMeetingIDForCreate(BuildContext context, PreJoinState state) {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.clear,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Column(
            children: [
              TextFieldTextV2(
                labelFontSize: 14.0,
                hintFontSize: 16.0,
                textController: displayNameController,
                myFocusNode: displayNameFocusNode,
                errorMessageOverride: state.displayNameFieldError,
                labelText: context.local.display_name,
                hintText: context.local.enter_display_name,
                backgroundColor: context.colors.backgroundCard,
                borderColor: context.colors.borderCard,
                borderRadius: BorderRadius.all(Radius.circular(18)),
                textInputAction: TextInputAction.done,
                maxLength: maxDisplayNameLength,
                onChanged: (value) {
                  bloc.add(UpdateDisplayName(value));
                },
                validation: (String value) {
                  return "";
                },
                onFinish: () {},
                suffixIcon: const SizedBox.shrink(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),
        RememberCheckbox(
          value: state.keepDisplayNameOnDevice,
          onChanged: (value) {
            bloc.add(ToggleKeepDisplayName(keep: value));
          },
        ),
      ],
    );
  }

  Future<void> _onJoinPressed(BuildContext context, PreJoinState state) async {
    if (PlatformInfoChannel.isInForceUpgradeState()) {
      return;
    }
    if (state.isJoinAuthenticating || state.isInWaitingRoomAdmission) {
      return;
    }
    final sanitizedDisplayName = displayNameController.text.sanitize(
      maxLength: maxDisplayNameLength,
    );
    if (sanitizedDisplayName == null) {
      bloc.add(SetDisplayNameFieldError(context.local.display_name_required));
      displayNameFocusNode.requestFocus();
      return;
    }
    if (state.meetingLink == null) {
      LocalToast.showToast(
        context,
        context.local.please_enter_valid_meeting_link,
      );
      return;
    }

    bloc.add(PreJoinAttemptJoin(sanitizedDisplayName));
  }

  /// Host-admission path: MLS join is already complete via Welcome.
  Future<void> _proceedToJoinAfterHostAccept(
    BuildContext context,
    PreJoinState state,
  ) async {
    final displayName = state.waitingRoomAdmissionDisplayName.trim();
    if (displayName.isEmpty || state.meetingLink == null) {
      return;
    }
    await _navigateToWaitingRoom(
      context,
      state,
      displayName,
      reuseMlsJoin: true,
    );
  }

  Future<void> _navigateToWaitingRoom(
    BuildContext context,
    PreJoinState state,
    String displayName, {
    required bool reuseMlsJoin,
  }) async {
    final args = state.buildJoinLoaderArgs(
      authBloc: authBloc,
      displayName: displayName,
      reuseMlsJoin: reuseMlsJoin,
    );

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => WaitingRoomPage(
          args,
          preJoinType: PreJoinType.join,
          isVideoEnabled: state.isVideoEnabled,
          isAudioEnabled: state.isAudioEnabled,
          enableE2EE: true,
          selectedVideoDevice: state.selectedVideoDevice,
          selectedAudioDevice: state.selectedAudioDevice,
          selectedSpeakerDevice: state.selectedSpeakerDevice,
          selectedVideoPosition: state.selectedVideoPosition,
          selectedVideoParameters: state.selectedVideoParameters,
          cameraBackgroundBlurEnabled: state.cameraBackgroundBlurEnabled,
        ),
      ),
    );
  }

  Widget _buildWaitingRoomAdmissionContent(
    BuildContext context,
    ({
      WaitingRoomAdmissionPhase phase,
      int countdownSeconds,
      String joinRequestId,
    })
    admission,
    double buttonWidth,
    double buttonHeight,
  ) {
    final isHostNotStarted =
        admission.phase == WaitingRoomAdmissionPhase.hostNotStarted;

    return Column(
      children: [
        if (isHostNotStarted) ...[
          CustomLoading(
            size: 24,
            strokeWidth: 2,
            color: context.colors.textNorm,
          ),
          const SizedBox(height: 20),
          Text(
            context.local.waiting_room_host_not_started_title,
            textAlign: TextAlign.center,
            style: ProtonStyles.headline(color: context.colors.textNorm),
          ),
          const SizedBox(height: 8),
          Text(
            context.local.waiting_room_host_not_started_description,
            textAlign: TextAlign.center,
            style: ProtonStyles.body2Medium(color: context.colors.textWeak),
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.colors.interActionWeak,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              context.local.waiting_room_expires_in(
                _formatCountdown(admission.countdownSeconds),
              ),
              style: ProtonStyles.body2Medium(color: context.colors.textWeak),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.local.waiting_room_awaiting_admission_title,
            textAlign: TextAlign.center,
            style: ProtonStyles.headline(color: context.colors.textNorm),
          ),
          const SizedBox(height: 8),
          Text(
            context.local.waiting_room_awaiting_admission_description,
            textAlign: TextAlign.center,
            style: ProtonStyles.body2Medium(color: context.colors.textWeak),
          ),
          if (admission.joinRequestId.isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(
              admission.joinRequestId,
              textAlign: TextAlign.center,
              style: ProtonStyles.captionRegular(
                color: context.colors.textHint,
              ).copyWith(fontFamily: 'monospace'),
            ),
          ],
        ],
        const SizedBox(height: 32),
        ButtonV6(
          text: context.local.leave,
          width: buttonWidth,
          height: buttonHeight,
          backgroundColor: context.colors.drawerBackground,
          borderColor: context.colors.clear,
          textStyle: ProtonStyles.body1Semibold(color: context.colors.textNorm),
          onPressed: () async {
            await bloc.leaveWaitingRoomAdmission();
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  static String _formatCountdown(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
