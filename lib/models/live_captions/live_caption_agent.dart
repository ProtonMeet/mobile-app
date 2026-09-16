import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/live_captions_constants.dart';

/// Participant-list label for the SttAgent worker.
class AgentDisplayInfo {
  const AgentDisplayInfo({required this.displayName, required this.initials});

  final String displayName;
  final String initials;

  /// Default copy for `SttAgent#…` identities.
  static const liveCaptionAgent = AgentDisplayInfo(
    displayName: 'Live caption agent',
    initials: 'CC',
  );
}

/// Whether [identity] belongs to a captions STT agent worker.
bool isCaptionAgentIdentity(String? identity) =>
    identity != null &&
    identity.startsWith(LiveCaptionsConstants.sttAgentPrefix);

/// Whether [participant] is the Meet STT caption agent (not other agent kinds).
bool isCaptionAgent(Participant participant) =>
    participant.kind == ParticipantKind.AGENT &&
    isCaptionAgentIdentity(participant.identity);

/// Whether [participantIdentity] is the in-room STT caption agent sender.
bool isCaptionAgentSender(Room room, String participantIdentity) {
  if (isCaptionAgentIdentity(participantIdentity)) {
    return true;
  }
  final sender = room.remoteParticipants[participantIdentity];
  if (sender == null) {
    return false;
  }
  return isCaptionAgent(sender);
}

/// Room roster helpers that leave the STT caption agent out.
extension CaptionAgentRoomRoster on Room {
  /// Remote participants that are real people (caption agent excluded).
  Iterable<RemoteParticipant> get remoteParticipantsExcludingCaptionAgent =>
      remoteParticipants.values.where(
        (participant) => !isCaptionAgent(participant),
      );
}

/// [AgentDisplayInfo] when [participant] is a caption agent; otherwise null.
AgentDisplayInfo? agentDisplayInfoForParticipant(Participant participant) {
  if (!isCaptionAgent(participant)) {
    return null;
  }
  return AgentDisplayInfo.liveCaptionAgent;
}
