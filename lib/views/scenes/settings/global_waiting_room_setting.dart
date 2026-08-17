import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/bridge_error.extension.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/proton_user_settings.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/views/scenes/settings/settings_section_header.dart';

class GlobalWaitingRoomSettingSection extends StatefulWidget {
  const GlobalWaitingRoomSettingSection({super.key});

  @override
  State<GlobalWaitingRoomSettingSection> createState() =>
      _GlobalWaitingRoomSettingSectionState();
}

class _GlobalWaitingRoomSettingSectionState
    extends State<GlobalWaitingRoomSettingSection> {
  bool _waitingRoomEnabled = false;
  bool _isLoading = true;
  bool _isUpdating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final manager = ManagerFactory().get<AppCoreManager>();
    final settings = await ProtonUserSettings.instance.ensureLoaded(manager);
    if (!mounted) {
      return;
    }
    setState(() {
      _waitingRoomEnabled = settings?.waitingRoom ?? false;
      _isLoading = false;
    });
  }

  Future<void> _onToggle(bool value) async {
    if (_isUpdating || _isLoading) {
      return;
    }

    final previous = _waitingRoomEnabled;
    setState(() {
      _waitingRoomEnabled = value;
      _isUpdating = true;
      _errorMessage = null;
    });

    try {
      final manager = ManagerFactory().get<AppCoreManager>();
      final settings = await ProtonUserSettings.instance.updateWaitingRoom(
        manager,
        enable: value,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _waitingRoomEnabled = settings.waitingRoom;
        _isUpdating = false;
      });
    } on BridgeError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _waitingRoomEnabled = previous;
        _isUpdating = false;
        _errorMessage = error.userMessage;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _waitingRoomEnabled = previous;
        _isUpdating = false;
        _errorMessage = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(24));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionHeader(title: context.local.settings_section_meetings),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: borderRadius,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.local.enable_waiting_room,
                              style: ProtonStyles.body1Medium(
                                color: context.colors.textNorm,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _waitingRoomEnabled
                                  ? context
                                        .local
                                        .waiting_room_setting_on_description
                                  : context
                                        .local
                                        .waiting_room_setting_off_description,
                              style: ProtonStyles.body2Regular(
                                color: context.colors.textWeak,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (_isLoading || _isUpdating)
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              context.colors.protonBlue,
                            ),
                          ),
                        )
                      else
                        Container(
                          height: 33,
                          width: 56,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: context.colors.interActionWeak,
                            ),
                            borderRadius: BorderRadius.circular(40),
                          ),
                          child: CupertinoSwitch(
                            value: _waitingRoomEnabled,
                            onChanged: _onToggle,
                            activeTrackColor: context.colors.backgroundNorm,
                            inactiveTrackColor: context.colors.backgroundNorm,
                            inactiveThumbColor: context.colors.interActionWeak,
                            thumbColor: context.colors.protonBlue,
                          ),
                        ),
                    ],
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: ProtonStyles.body2Medium(
                        color: context.colors.notificationError,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
