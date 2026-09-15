import 'package:flutter/material.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_bloc.dart';
import 'package:meet/views/scenes/room/settings/bloc/in_room_settings_event.dart';

/// Pushes [RoomBloc] / room shell snapshots into [InRoomSettingsBloc] after
/// layout, so we never dispatch bloc events from a [build] method.
class InRoomSettingsBindingsSync extends StatefulWidget {
  const InRoomSettingsBindingsSync({
    required this.bloc,
    required this.bindings,
    required this.child,
    super.key,
  });

  final InRoomSettingsBloc bloc;
  final InRoomSettingsBindingsUpdated bindings;
  final Widget child;

  @override
  State<InRoomSettingsBindingsSync> createState() =>
      _InRoomSettingsBindingsSyncState();
}

class _InRoomSettingsBindingsSyncState
    extends State<InRoomSettingsBindingsSync> {
  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant InRoomSettingsBindingsSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSync();
  }

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.bloc.add(widget.bindings);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
