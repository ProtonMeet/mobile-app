import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/settings/settings_section.dart';
import 'package:meet/views/components/settings/settings_toggle_row.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_bloc.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_state.dart';
import 'package:meet/views/scenes/room/settings/sections/in_room_background_settings_section.dart';
import 'package:meet/views/scenes/room/settings/sections/in_room_host_settings_section.dart';
import 'package:meet/views/scenes/room/settings/sections/in_room_video_audio_settings_section.dart';
import 'package:meet/views/scenes/room/side_panel_widget.dart';

/// In-meeting settings, shown in the room side rail or as a bottom sheet.
class InRoomSettingsPanel extends StatelessWidget {
  const InRoomSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InRoomSettingsBloc, InRoomSettingsState>(
      builder: (context, state) {
        return RoomSidePanelScroll(
          header: Text(
            context.local.meeting_settings,
            style: ProtonStyles.headline(
              fontSize: 18,
              color: context.colors.textNorm,
            ),
          ),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const InRoomHostSettingsSection(),
                  InRoomVideoAudioSettingsSection(state: state),
                  InRoomBackgroundSettingsSection(state: state),
                  _DisplaySection(state: state),
                  _ConnectionSection(state: state),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DisplaySection extends StatelessWidget {
  const _DisplaySection({required this.state});

  final InRoomSettingsState state;

  @override
  Widget build(BuildContext context) {
    if (!state.showPreviewSettings) {
      return const SizedBox.shrink();
    }

    return SettingsSection(
      title: context.local.settings_section_display,
      rows: [
        SettingsToggleRow(title: context.local.live_captions, value: false),
        SettingsToggleRow(title: context.local.meeting_timer, value: false),
      ],
    );
  }
}

class _ConnectionSection extends StatelessWidget {
  const _ConnectionSection({required this.state});

  final InRoomSettingsState state;

  @override
  Widget build(BuildContext context) {
    if (!state.showConnectionSettings) {
      return const SizedBox.shrink();
    }

    final onReconnect = state.onReconnectPressed;

    return SettingsSection(
      title: context.local.connection,
      rows: [
        if (onReconnect != null)
          SettingsToggleRow(
            title: context.local.reconnect_meeting,
            value: state.isRejoining,
            isLoading: state.isRejoining,
            onChanged: (_) => onReconnect(),
          ),
        if (state.onForceShowConnectionStatusBannerChanged != null)
          SettingsToggleRow(
            title: context.local.always_show_status,
            value: state.forceShowConnectionStatusBanner,
            onChanged: state.onForceShowConnectionStatusBannerChanged,
          ),
      ],
    );
  }
}
