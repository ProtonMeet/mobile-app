import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/settings/settings_preview_nav_row.dart';
import 'package:meet/views/components/settings/settings_row.dart';
import 'package:meet/views/components/settings/settings_section.dart';
import 'package:meet/views/components/settings/settings_toggle_row.dart';
import 'package:meet/views/scenes/settings/app_settings_bloc.dart';
import 'package:meet/views/scenes/settings/app_settings_event.dart';
import 'package:meet/views/scenes/settings/app_settings_state.dart';
import 'package:meet/views/scenes/settings/meetings/recording_settings_rows.dart';

/// Meetings-related app settings (waiting room, recording, device tests, etc.).
class AppSettingsMeetingsSection extends StatelessWidget {
  const AppSettingsMeetingsSection({
    required this.appSettingsBloc,
    required this.isSignedIn,
    super.key,
  });

  final AppSettingsBloc appSettingsBloc;
  final bool isSignedIn;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      bloc: appSettingsBloc,
      builder: (context, state) {
        return SettingsSection(
          title: context.local.settings_section_meetings,
          rows: [
            if (isSignedIn)
              SettingsToggleRow(
                overline: context.local.waiting_room,
                title: state.canEditWaitingRoom
                    ? (state.waitingRoomEnabled
                          ? context.local.settings_value_enabled
                          : context.local.settings_value_disabled)
                    : context.local.settings_value_disabled,
                subtitle: state.canEditWaitingRoom
                    ? null
                    : context.local.waiting_room_paid_feature,
                tone: SettingsRowTone.normal,
                value: state.canEditWaitingRoom
                    ? state.waitingRoomEnabled
                    : false,
                isLoading: state.isWaitingRoomBusy,
                silentWhenDisabled: !state.canEditWaitingRoom,
                onChanged: state.canEditWaitingRoom
                    ? (value) => appSettingsBloc.add(
                        AppSettingsWaitingRoomToggled(
                          enabled: value,
                          isPaidUser: state.isPaidUser,
                        ),
                      )
                    : null,
              ),
            if (state.showPreviewSettings)
              SettingsPreviewNavRow(
                overline: context.local.live_captions,
                title: context.local.live_captions_all_participants,
              ),
            if (state.showRecordingSettings) ...buildRecordingSettingsRows(),
            if (state.showPreviewSettings) ...[
              SettingsPreviewNavRow(title: context.local.test_microphone),
              SettingsPreviewNavRow(title: context.local.test_speakers),
            ],
          ],
        );
      },
    );
  }
}
