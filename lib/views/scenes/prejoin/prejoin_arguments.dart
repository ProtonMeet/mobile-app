import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
import 'package:meet/views/scenes/prejoin/prejoin_state.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';

enum PrejoinRole { host, guest }

enum PreJoinType { join, create }

class PreJoinArgs {
  PreJoinArgs({required this.authBloc, this.type = PreJoinType.join});

  final PreJoinType type;
  final AuthBloc authBloc;
}

class JoinArgs {
  JoinArgs({
    required this.meetingLink,
    this.meetingLinkUrl = '',
    this.displayName = '',
    this.role = PrejoinRole.guest,
    this.type = PreJoinType.join,
    this.e2ee = false,
    this.e2eeKey,
    this.simulcast = true,
    this.adaptiveStream = true,
    this.dynacast = true,
    // Default to VP8, will be overridden by unleash flag
    this.preferredCodec = 'VP8',
    this.enableBackupVideoCodec = true,
    this.isVideoEnabled = true,
    this.isAudioEnabled = true,
    this.isSpeakerPhoneEnabled = false,
  });

  final String displayName;
  final PrejoinRole role;
  final PreJoinType type;
  final bool e2ee;
  final String? e2eeKey;
  final bool simulcast;
  final bool adaptiveStream;
  final bool dynacast;
  final String preferredCodec;
  final bool enableBackupVideoCodec;
  final bool isVideoEnabled;
  final bool isAudioEnabled;
  final bool isSpeakerPhoneEnabled;
  final FrbUpcomingMeeting? meetingLink;
  final String meetingLinkUrl;
}
