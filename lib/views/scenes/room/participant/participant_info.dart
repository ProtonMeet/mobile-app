import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/widgets/sound_waveform.dart';

enum ParticipantInfoType { kName, kAudioStatus }

enum ParticipantTrackType { kUserMedia, kScreenShare }

extension ParticipantTrackTypeExt on ParticipantTrackType {
  TrackSource get lkVideoSourceType => {
    ParticipantTrackType.kUserMedia: TrackSource.camera,
    ParticipantTrackType.kScreenShare: TrackSource.screenShareVideo,
  }[this]!;

  TrackSource get lkAudioSourceType => {
    ParticipantTrackType.kUserMedia: TrackSource.microphone,
    ParticipantTrackType.kScreenShare: TrackSource.screenShareAudio,
  }[this]!;
}

class ParticipantInfo {
  ParticipantInfo({
    required this.participant,
    required this.displayName,
    this.type = ParticipantTrackType.kUserMedia,
  });

  Participant participant;
  final ParticipantTrackType type;
  String displayName;
}

class ParticipantInfoWidget extends StatelessWidget {
  final String? title;
  final bool audioAvailable;
  final AudioTrack? activeAudioTrack;
  final bool isScreenShare;
  final ParticipantInfoType type;
  const ParticipantInfoWidget({
    required this.type,
    this.title,
    this.audioAvailable = true,
    this.activeAudioTrack,
    this.isScreenShare = false,

    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (type == ParticipantInfoType.kName) {
      return _buildName(context);
    } else if (type == ParticipantInfoType.kAudioStatus) {
      return _buildAudioStatus(context);
    }
    return const SizedBox.shrink();
  }

  Widget _buildName(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 8),
        if (title != null)
          Flexible(
            child: Text(
              title ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: ProtonStyles.body1Regular(color: context.colors.textNorm),
            ),
          ),
      ],
    );

    if (isScreenShare) {
      return Align(
        alignment: Alignment.centerLeft,
        child: IntrinsicWidth(
          child: Container(
            margin: const EdgeInsets.only(left: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: context.colors.backgroundDark,
              borderRadius: BorderRadius.circular(16),
            ),
            child: content,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      color: Colors.transparent,
      child: content,
    );
  }

  Widget _buildAudioStatus(BuildContext context) => Container(
    color: Colors.transparent,
    padding: const EdgeInsets.symmetric(
      vertical: 12,
      horizontal: 12,
    ).copyWith(left: 6.0),
    child: CircleAvatar(
      radius: 16,
      backgroundColor: isScreenShare
          ? context.colors.clear
          : context.colors.backgroundNorm,
      child: isScreenShare
          ? const SizedBox.shrink()
          : (!isScreenShare && audioAvailable && activeAudioTrack != null)
          ? SoundWaveformWidget(
              key: ValueKey(activeAudioTrack!.hashCode),
              audioTrack: activeAudioTrack!,
              minHeight: 3,
              maxHeight: 10,
              width: 1,
              barCount: 3,
            )
          : context.images.iconAudioOff.svg(
              width: 14,
              height: 14,
              colorFilter: ColorFilter.mode(
                context.colors.textNorm,
                BlendMode.srcIn,
              ),
            ),
    ),
  );
}
