import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/strings.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/managers/channels/platform_info_channel.dart';
import 'package:meet/views/components/button.v5.dart';
import 'package:meet/views/components/textfield.text.v2.dart';
import 'package:meet/views/scenes/prejoin/meeting_link_action.dart';
import 'package:meet/views/scenes/prejoin/remember_checkbox.dart';
import 'package:meet/views/scenes/waiting.room/waiting_room_view.dart';

import 'prejoin_arguments.dart';
import 'prejoin_bloc.dart';
import 'prejoin_event.dart';
import 'prejoin_state.dart';
import 'video_preview_with_controls.dart';

class PreJoinScreen extends StatelessWidget {
  const PreJoinScreen({
    required this.bloc,
    required this.displayNameController,
    required this.roomNameController,
    required this.displayNameFocusNode,
    required this.meetingLinkFocusNode,
    super.key,
  });

  @protected
  final PreJoinBloc bloc;

  final TextEditingController displayNameController;
  final TextEditingController roomNameController;
  final FocusNode displayNameFocusNode;
  final FocusNode meetingLinkFocusNode;

  @override
  Widget build(BuildContext context) {
    return BlocSelector<PreJoinBloc, PreJoinState, PreJoinState>(
      selector: (PreJoinState state) => state,
      builder: (context, state) {
        final screenWidth = MediaQuery.of(context).size.width;
        final padding = 16.0;
        const buttonHeight = 60.0;

        return LayoutBuilder(
          builder: (context, constraints) {
            final viewportHeight = constraints.maxHeight;
            // Calculate available height based on preJoinType:
            // Join: Spacer (56) + gap(20) + meeting link field (80) + display name field (80) + button (60) + padding/spacing (~30) = 260
            // Create: Spacer (56) + gap (20) + display name field (80) + button (60) + padding/spacing (~30) = 241

            // Join: has meeting link (80) + display name (80) fields + remember display name checkbox (50)
            // Create: has only display name (80) field + remember display name checkbox (50)
            final estimatedBottomContentHeight =
                (state.preJoinType == PreJoinType.join ? 330.0 : 245.0) +
                buttonHeight;
            final availableHeight =
                viewportHeight - estimatedBottomContentHeight;
            // Ensure preview fills available space but doesn't cause overflow
            final previewHeight = availableHeight.clamp(300.0, double.infinity);

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                children: [
                  // Spacer for close button (top left is handled in parent)
                  SizedBox(height: 56.0),

                  // Video preview - fill available space
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
                  const SizedBox(height: 20),

                  // Meeting link and display name
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: padding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Meeting link and display name
                        if (state.preJoinType == PreJoinType.join)
                          _buildMeetingIDForJoin(context, state),
                        if (state.preJoinType == PreJoinType.create)
                          _buildMeetingIDForCreate(context, state),

                        const SizedBox(height: 16),

                        // Join meeting button
                        if (state.preJoinType == PreJoinType.join)
                          ButtonV5(
                            onPressed: () async {
                              if (PlatformInfoChannel.isInForceUpgradeState()) {
                                return;
                              }
                              if (displayNameController.text.isEmpty ||
                                  state.meetingLink == null) {
                                LocalToast.showToast(
                                  context,
                                  context.local.please_enter_valid_meeting_link,
                                );
                                return;
                              }

                              final sanitizedDisplayName =
                                  displayNameController.text.sanitize() ??
                                  'Anonymous user';

                              final args = JoinArgs(
                                meetingLink: state.meetingLink!,
                                displayName: sanitizedDisplayName,
                                isVideoEnabled: state.isVideoEnabled,
                                isAudioEnabled: state.isAudioEnabled,
                                e2ee: state.enableE2EE,
                                preferredCodec: state.videoCodec.toString(),
                                isSpeakerPhoneEnabled:
                                    state.isSpeakerPhoneEnabled,
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
                                    isSpeakerPhoneEnabled:
                                        state.isSpeakerPhoneEnabled,
                                  ),
                                ),
                              );
                            },
                            enable:
                                state.displayName.isNotEmpty &&
                                !PlatformInfoChannel.isInForceUpgradeState(),
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

                        // Create meeting button
                        if (state.preJoinType == PreJoinType.create)
                          ButtonV5(
                            onPressed: () async {
                              if (PlatformInfoChannel.isInForceUpgradeState()) {
                                return;
                              }
                              if (displayNameController.text.isEmpty) {
                                LocalToast.showToast(
                                  context,
                                  context.local.please_enter_valid_meeting_link,
                                );
                                return;
                              }

                              final sanitizedDisplayName =
                                  displayNameController.text.sanitize() ??
                                  'Anonymous user';

                              final args = JoinArgs(
                                meetingLink: null,
                                displayName: sanitizedDisplayName,
                                isVideoEnabled: state.isVideoEnabled,
                                isAudioEnabled: state.isAudioEnabled,
                                e2ee: state.enableE2EE,
                                preferredCodec: state.videoCodec.toString(),
                                isSpeakerPhoneEnabled:
                                    state.isSpeakerPhoneEnabled,
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
                                    isSpeakerPhoneEnabled:
                                        state.isSpeakerPhoneEnabled,
                                  ),
                                ),
                              );
                            },
                            enable:
                                state.displayName.isNotEmpty &&
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
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  DecoratedBox _buildMeetingIDForJoin(
    BuildContext context,
    PreJoinState state,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.clear,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Column(
        children: [
          // Meeting link field (read-only)
          TextFieldTextV2(
            textController: TextEditingController(
              text: state.meetingLink?.meetingLinkName ?? "",
            ),
            myFocusNode: meetingLinkFocusNode,
            labelText: context.local.meeting_link,
            backgroundColor: context.colors.backgroundCard,
            borderColor: context.colors.borderCard,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
            ),
            textInputAction: TextInputAction.done,
            readOnly: true,
            hideBottomBorder: true,
            validation: (String value) {
              return "";
            },
            showFinishButton: false,
            onFinish: () {},
            suffixIcon: MeetingLinkActions(
              hideImport: true,
              onCopy: () {
                Clipboard.setData(
                  ClipboardData(text: state.meetingLinkUrl ?? ""),
                ).then((_) {
                  if (context.mounted) {
                    LocalToast.showToast(
                      context,
                      context.local.copied_to_clipboard,
                    );
                  }
                });
              },
              onImport: () {},
            ),
          ),
          // Display name field
          TextFieldTextV2(
            textController: displayNameController,
            myFocusNode: displayNameFocusNode,
            labelText: context.local.display_name,
            hintText: context.local.enter_display_name,
            backgroundColor: context.colors.backgroundCard,
            borderColor: context.colors.borderCard,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
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

          const SizedBox(height: 10),
          RememberCheckbox(
            value: state.keepDisplayNameOnDevice,
            onChanged: (value) {
              bloc.add(ToggleKeepDisplayName(keep: value));
            },
          ),
        ],
      ),
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
}
