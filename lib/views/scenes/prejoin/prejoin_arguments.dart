import 'package:meet/rust/proton_meet/models/meeting_info.dart';
import 'package:meet/rust/proton_meet/models/upcoming_meeting.dart';
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
    this.authBloc,
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
    this.isMeetingHost = false,
    this.waitingRoomEnabled = false,
    this.pendingHostWaitingRoomSyncEnabled,
    this.prefetchedMeetingInfo,
    this.prejoinAuthDisplayName = '',
    this.reusePrejoinAuth = false,
    this.reuseMlsJoin = false,
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

  /// True when the signed-in user owns this meeting (from upcoming meetings).
  final bool isMeetingHost;

  /// Host-controlled waiting room toggle from pre-join (host only).
  final bool waitingRoomEnabled;

  /// Host-only: when non-null, room should sync waiting-room policy to this value on enter.
  final bool? pendingHostWaitingRoomSyncEnabled;

  /// True when the host joins with waiting room enabled for MLS join.
  bool get enableWaitingRoomForJoin =>
      isMeetingHost && waitingRoomEnabled;

  /// Meeting limits fetched during pre-join; avoids a second fetch in room.
  final FrbMeetingInfo? prefetchedMeetingInfo;

  /// Display name used for the pre-join SRP auth (must match join display name to reuse).
  final String prejoinAuthDisplayName;

  /// When true, waiting room join skips a second SRP auth.
  final bool reusePrejoinAuth;

  /// When true, MLS join already completed during pre-join waiting-room admission.
  final bool reuseMlsJoin;
  final FrbUpcomingMeeting? meetingLink;
  final String meetingLinkUrl;

  /// Same instance as dashboard / pre-join when the user came through that flow.
  final AuthBloc? authBloc;
}
