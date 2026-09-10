import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/settings/settings_choice_row.dart';
import 'package:meet/views/components/settings/settings_section.dart';
import 'package:meet/views/components/settings/settings_toggle_row.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_state.dart';

/// In-meeting video and audio settings.
class InRoomVideoAudioSettingsSection extends StatelessWidget {
  const InRoomVideoAudioSettingsSection({required this.state, super.key});

  final InRoomSettingsState state;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: context.local.settings_section_video_audio,
      rows: [
        SettingsToggleRow(
          title: context.local.incoming_video,
          value: state.incomingVideoEnabled,
          onChanged: state.onIncomingVideoChanged,
        ),
        SettingsToggleRow(
          title: context.local.self_view,
          value: state.selfViewEnabled,
          onChanged: state.onSelfViewChanged,
        ),
        if (state.showPreviewSettings)
          SettingsToggleRow(
            title: context.local.picture_in_picture_while_sharing,
            value: false,
          ),
        if (state.showAudioDenoise && state.onAudioDenoiseChanged != null)
          SettingsToggleRow(
            title: context.local.audio_noise_cancellation,
            value: state.audioDenoiseEnabled,
            onChanged: state.onAudioDenoiseChanged,
          ),
        if (state.showAudioDenoiseTypes)
          ...state.audioDenoiseTypes.map(
            (option) => SettingsChoiceRow(
              title: option.label,
              selected: state.selectedAudioDenoiseType == option.type,
              onTap: () => state.onAudioDenoiseTypeSelected?.call(option.type),
            ),
          ),
      ],
    );
  }
}
