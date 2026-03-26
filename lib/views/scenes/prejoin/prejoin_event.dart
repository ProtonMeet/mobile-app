import 'package:livekit_client/livekit_client.dart';
import 'package:meet/rust/proton_meet/user_config.dart';
import 'package:meet/views/scenes/prejoin/prejoin_arguments.dart';
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

class VideoCodecChanged extends PreJoinEvent {
  final VideoCodec codec;
  VideoCodecChanged(this.codec);
}

class CreateMeeting extends PreJoinEvent {}

class UpdateDisplayName extends PreJoinEvent {
  final String displayName;
  UpdateDisplayName(this.displayName);
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

class SwapVideo extends PreJoinEvent {}

class ToggleKeepDisplayName extends PreJoinEvent {
  final bool keep;
  ToggleKeepDisplayName({required this.keep});
}
