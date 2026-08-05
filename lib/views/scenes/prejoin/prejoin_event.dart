import 'package:livekit_client/livekit_client.dart';
import 'package:meet/rust/proton_meet/user_config.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
import 'package:meet/views/scenes/prejoin/prejoin_meeting_preview.dart';
import 'package:meet/views/scenes/prejoin/prejoin_state.dart';

abstract class PreJoinEvent {}

class PreJoinInitialized extends PreJoinEvent {
  final JoinArgs args;
  final String displayName;
  PreJoinInitialized(this.args, this.displayName);
}

class PreJoinToggleAudio extends PreJoinEvent {}

class PreJoinToggleVideo extends PreJoinEvent {}

class RequestCameraPermission extends PreJoinEvent {}

class CameraPermissionSettingsConsumed extends PreJoinEvent {}

class MicrophonePermissionSettingsConsumed extends PreJoinEvent {}

class RequestMicrophonePermission extends PreJoinEvent {}

class ToggleE2EE extends PreJoinEvent {}

class SelectVideoDevice extends PreJoinEvent {
  final MediaDevice device;
  SelectVideoDevice(this.device);
}

class SelectAudioDevice extends PreJoinEvent {
  final MediaDevice device;
  SelectAudioDevice(this.device);
}

class SelectSpeakerDevice extends PreJoinEvent {
  final MediaDevice device;
  SelectSpeakerDevice(this.device);
}

class SelectVideoResolution extends PreJoinEvent {
  final VideoResolution resolution;
  SelectVideoResolution(this.resolution);
}

class JoinRoom extends PreJoinEvent {}

class WaitingRoomChanged extends PreJoinEvent {
  final bool enabled;
  // ignore: avoid_positional_boolean_parameters
  WaitingRoomChanged(this.enabled);
}

class WaitingRoomSettingErrorConsumed extends PreJoinEvent {}

class VideoCodecChanged extends PreJoinEvent {
  final VideoCodec codec;
  VideoCodecChanged(this.codec);
}

class CreateMeeting extends PreJoinEvent {}

class UpdateDisplayName extends PreJoinEvent {
  final String displayName;
  UpdateDisplayName(this.displayName);
}

class SetDisplayNameFieldError extends PreJoinEvent {
  final String message;
  SetDisplayNameFieldError(this.message);
}

class ResetLoadingState extends PreJoinEvent {
  final bool isLoggingIn;
  final bool isLoggingOut;
  ResetLoadingState({this.isLoggingIn = false, this.isLoggingOut = false});
}

class SetSpeakerPhoneEnabled extends PreJoinEvent {
  final bool enabled;
  SetSpeakerPhoneEnabled({required this.enabled});
}

class PreJoinAudioOutputDevicesChanged extends PreJoinEvent {
  final bool hasExternalAudioOutput;
  final bool hasBluetoothAudioOutput;
  PreJoinAudioOutputDevicesChanged({
    required this.hasExternalAudioOutput,
    required this.hasBluetoothAudioOutput,
  });
}

class SwapVideo extends PreJoinEvent {}

class PreJoinToggleCameraBackgroundBlur extends PreJoinEvent {}

class ToggleKeepDisplayName extends PreJoinEvent {
  final bool keep;
  ToggleKeepDisplayName({required this.keep});
}

class PreJoinPaidUserResolved extends PreJoinEvent {
  final bool isPaidUser;
  PreJoinPaidUserResolved({required this.isPaidUser});
}

/// Authenticates the meeting link when the user presses Join.
class PreJoinAttemptJoin extends PreJoinEvent {
  final String displayName;

  PreJoinAttemptJoin(this.displayName);
}

class PreJoinHostMeetingContextResolved extends PreJoinEvent {
  final bool waitingRoomEnabled;
  final String? roomName;

  PreJoinHostMeetingContextResolved({
    required this.waitingRoomEnabled,
    this.roomName,
  });
}

class PreJoinHostMeetingContextLoadFinished extends PreJoinEvent {}

/// SRP auth + getMeetingInfo resolved for direct-link / non-dashboard entry.
class PreJoinMeetingContextResolved extends PreJoinEvent {
  final PreJoinJoinAuthResult auth;

  PreJoinMeetingContextResolved({required this.auth});
}

class PreJoinMeetingContextLoadFinished extends PreJoinEvent {}

class PreJoinMeetingContextFailed extends PreJoinEvent {
  final Object error;

  PreJoinMeetingContextFailed(this.error);
}

class PreJoinNavigateToWaitingRoomConsumed extends PreJoinEvent {}

class PreJoinStartWaitingRoomAdmission extends PreJoinEvent {
  final String displayName;
  PreJoinStartWaitingRoomAdmission(this.displayName);
}

class PreJoinPollGroupInfo extends PreJoinEvent {}

class PreJoinWaitingRoomCountdownTick extends PreJoinEvent {}

/// Waits for host Welcome after [PreJoinStartWaitingRoomAdmission] submitted a join request.
class PreJoinWaitForWaitingRoomWelcome extends PreJoinEvent {}

class PreJoinLeaveWaitingRoomAdmission extends PreJoinEvent {}

class PreJoinWaitingRoomAdmissionTimedOut extends PreJoinEvent {}

class PreJoinHostAcceptProceedConsumed extends PreJoinEvent {}

class PreJoinJoinRequestRejectedNotificationConsumed extends PreJoinEvent {}

class PreJoinWaitingRoomAdmissionTimedOutNotificationConsumed
    extends PreJoinEvent {}

class PreJoinMeetingLockedBottomSheetConsumed extends PreJoinEvent {}

class PreJoinJoinDecisionReceived extends PreJoinEvent {
  final String requestId;
  final bool admitted;

  PreJoinJoinDecisionReceived({
    required this.requestId,
    required this.admitted,
  });
}
