import 'package:flutter/material.dart';
import 'package:meet/constants/assets.gen.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/room/participant/participant_info.dart';

/// Returns display colors for a participant based on their index in the sorted list.
///
/// This matches the WebApp approach which assigns colors based on participant position:
/// - Colors cycle through 6 options: `(index % 6) + 1`
/// - The same participant will always get the same color based on their position
///
/// Parameters:
/// - `context`: BuildContext to access theme colors
/// - `index`: The participant's index in the sorted participant list (0-based)
///
/// Returns:
/// A map containing:
/// - `profileColor`: Background color for the avatar circle
/// - `backgroundColor`: Background color for the participant tile
/// - `profileTextColor`: Text color for the avatar initials
class ParticipantDisplayColors {
  final Color profileColor;
  final Color backgroundColor;
  final Color profileTextColor;
  final Color actionBackgroundColor;

  final SvgGenImage? meetingLogo;
  final SvgGenImage? roomLogo;
  final SvgGenImage? personalLogo;

  ParticipantDisplayColors({
    required this.profileColor,
    required this.backgroundColor,
    required this.profileTextColor,
    required this.actionBackgroundColor,
    required this.meetingLogo,
    required this.roomLogo,
    required this.personalLogo,
  });
}

/// Gets participant display colors based on index (matching WebApp pattern).
///
/// WebApp uses: `(index % 6) + 1` to cycle through 6 colors.
/// Colors are assigned in this order (matching WebApp):
/// 1. Purple
/// 2. Green
/// 3. Blue (interaction-norm)
/// 4. Blue
/// 5. Red
/// 6. Orange
///
/// The local participant is typically at index 0, followed by sorted remote participants.
ParticipantDisplayColors getParticipantDisplayColors(
  BuildContext context,
  int index,
) {
  // Cycle through 6 colors (0-5), matching WebApp's modulo pattern
  // WebApp: (index % 6) + 1 gives 1-6
  // Meet-app: (index % 6) gives 0-5
  final colorIndex = index % 6;

  // Match WebApp color order: Purple, Green, Blue (interaction-norm), Blue, Red, Orange
  final List<Color> profileColors = [
    context.colors.avatarPurple1Text, // 1. Purple
    context.colors.avatarGreen1Text, // 2. Green
    context.colors.avatarBlue2Text, // 3. Blue (interaction-norm)
    context.colors.avatarBlue1Text, // 4. Blue
    context.colors.avatarRed1Text, // 5. Red
    context.colors.avatarOrange1Text, // 6. Orange
  ];

  final List<Color> backgroundColors = [
    context.colors.avatarPurple1Background, // 1. Purple
    context.colors.avatarGreen1Background, // 2. Green
    context.colors.avatarBlue2Background, // 3. Blue (interaction-norm)
    context.colors.avatarBlue1Background, // 4. Blue
    context.colors.avatarRed1Background, // 5. Red
    context.colors.avatarOrange1Background, // 6. Orange
  ];

  final List<Color> actionBackgroundColors = [
    context.colors.interActionPurpleMinor1, // 1. Purple
    context.colors.greenInteractionNormMajor1, // 2. Green
    context.colors.interActionNorm, // 3. Blue (interaction-norm)
    context.colors.avatarBlue1Text, // 4. Blue
    context.colors.redInteractionNormMajor1, // 5. Red
    context.colors.signalWaning, // 6. Orange
  ];

  final List<SvgGenImage> meetingLogos = [
    context.images.logoSchedulePurple, // 1. Purple
    context.images.logoScheduleGreen, // 2. Green
    context.images.logoSchedulePurple, // 3. Blue
    context.images.logoScheduleBlue, // 4. Blue
    context.images.logoScheduleRed, // 5. Red
    context.images.logoScheduleOrange, // 6. Orange
  ];

  final List<SvgGenImage> roomLogos = [
    context.images.logoRoomPurple, // 1. Purple
    context.images.logoRoomGreen, // 2. Green
    context.images.logoRoomPurple, // 3. Blue
    context.images.logoRoomBlue, // 4. Blue
    context.images.logoRoomRed, // 5. Red
    context.images.logoRoomOrange, // 6. Orange
  ];

  return ParticipantDisplayColors(
    profileColor: profileColors[colorIndex],
    backgroundColor: backgroundColors[colorIndex],
    profileTextColor: profileColors[colorIndex],
    meetingLogo: meetingLogos[colorIndex],
    roomLogo: roomLogos[colorIndex],
    actionBackgroundColor: actionBackgroundColors[colorIndex],
    personalLogo: context.images.logoRoomPersonal,
  );
}

/// Gets participant display colors by finding the participant's index in the sorted list.
///
/// This is useful for chat messages where we have the participant identity but not the index.
/// Falls back to hash-based color assignment if participant is not found in the list.
ParticipantDisplayColors getParticipantDisplayColorsByIdentity(
  BuildContext context,
  String? participantIdentity,
  List<ParticipantInfo>? participantTracks,
) {
  // Try to find the participant's index in the sorted list
  if (participantIdentity != null && participantTracks != null) {
    final index = participantTracks.indexWhere(
      (info) => info.participant.identity == participantIdentity,
    );
    if (index != -1) {
      return getParticipantDisplayColors(context, index);
    }
  }

  // Fallback to hash-based assignment (consistent but not matching WebApp index-based)
  final identifier = participantIdentity ?? 'default';
  final hash = identifier.hashCode;
  final colorIndex = hash.abs() % 6;

  // Match WebApp color order: Purple, Green, Blue (interaction-norm), Blue, Red, Orange
  final List<Color> profileColors = [
    context.colors.avatarPurple1Text, // 1. Purple
    context.colors.avatarGreen1Text, // 2. Green
    context.colors.interActionNorm, // 3. Blue (interaction-norm)
    context.colors.avatarBlue1Text, // 4. Blue
    context.colors.signalDanger, // 5. Red
    context.colors.avatarOrange1Text, // 6. Orange
  ];

  final List<Color> backgroundColors = [
    context.colors.avatarPurple1Background, // 1. Purple
    context.colors.avatarGreen1Background, // 2. Green
    context.colors.interActionNormMinor3, // 3. Blue (interaction-norm)
    context.colors.avatarBlue1Background, // 4. Blue
    context.colors.signalDangerMajor3, // 5. Red
    context.colors.avatarOrange1Background, // 6. Orange
  ];

  final List<Color> actionBackgroundColors = [
    context.colors.interActionPurpleMinor1, // 1. Purple
    context.colors.greenInteractionNormMajor1, // 2. Green
    context.colors.interActionNorm, // 3. Blue (interaction-norm)
    context.colors.avatarBlue1Text, // 4. Blue
    context.colors.redInteractionNormMajor1, // 5. Red
    context.colors.signalWaning, // 6. Orange
  ];

  return ParticipantDisplayColors(
    profileColor: profileColors[colorIndex],
    backgroundColor: backgroundColors[colorIndex],
    profileTextColor: profileColors[colorIndex],
    actionBackgroundColor: actionBackgroundColors[colorIndex],
    meetingLogo: null,
    roomLogo: null,
    personalLogo: context.images.logoRoomPersonal,
  );
}
