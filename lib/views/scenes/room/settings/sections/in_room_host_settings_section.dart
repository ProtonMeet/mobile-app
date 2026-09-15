import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/settings/settings_section.dart';
import 'package:meet/views/components/settings/settings_toggle_row.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_bloc.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_event.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_state.dart';
import 'package:meet/views/scenes/settings/meetings/recording_settings_rows.dart';

/// Host-only in-meeting settings (lock, waiting room, recording, previews).
class InRoomHostSettingsSection extends StatelessWidget {
  const InRoomHostSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InRoomSettingsBloc, InRoomSettingsState>(
      builder: (context, state) {
        if (!state.isHost) {
          return const SizedBox.shrink();
        }

        final bloc = context.read<InRoomSettingsBloc>();

        return SettingsSection(
          title: context.local.settings_section_host,
          rows: [
            SettingsToggleRow(
              title: context.local.lock_meeting,
              value: state.lockMeeting,
              isLoading: state.isPending(InRoomPendingToggle.lockMeeting),
              onChanged: state.canEditHostToggles
                  ? (value) =>
                        bloc.add(InRoomLockMeetingToggled(enabled: value))
                  : null,
            ),
            if (state.showPreviewSettings)
              SettingsToggleRow(
                title: context.local.record_meeting,
                value: false,
              ),
            if (state.showWaitingRoom)
              SettingsToggleRow(
                title: context.local.enable_waiting_room,
                subtitle: state.canEditWaitingRoom
                    ? (state.waitingRoomEnabled
                          ? context.local.waiting_room_setting_on_description
                          : context.local.waiting_room_setting_off_description)
                    : context.local.waiting_room_paid_feature,
                value: state.waitingRoomEnabled,
                isLoading: state.isPending(InRoomPendingToggle.waitingRoom),
                silentWhenDisabled: !state.canEditWaitingRoom,
                onChanged: state.canEditWaitingRoom
                    ? (value) =>
                          bloc.add(InRoomWaitingRoomToggled(enabled: value))
                    : null,
              ),
            if (state.showPreviewSettings) ...[
              SettingsToggleRow(
                title: context.local.allow_live_captions,
                subtitle: context.local.allow_live_captions_description,
                value: false,
              ),
              SettingsToggleRow(
                title: context.local.transcribe_meeting,
                subtitle: context.local.transcribe_meeting_off_description,
                value: false,
              ),
            ],
            if (state.showRecordingRows) ...buildRecordingSettingsRows(),
          ],
        );
      },
    );
  }
}
