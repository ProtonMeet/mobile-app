import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/bridge_error.extension.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/helper/logger.dart' as l;
import 'package:meet/helper/pre_meeting_waiting_room.dart';
import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/rust/errors.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/components/custom.loading.dart';
import 'package:meet/views/scenes/dashboard/schedule/waiting_room_sheet.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';

typedef OnCreateRoomValue =
    void Function(String roomName, {required bool waitingRoom});
typedef OnEditRoomValue = void Function(String roomName);

Future<void> showCreateRoomDialog(
  BuildContext context, {
  required OnCreateRoomValue onCreateRoom,
  String? initialRoomName,
  bool autofocus = true,
  bool isPaidUser = false,
  bool showWaitingRoom = false,
}) {
  // Block dialog when in force upgrade state
  final appStateManager = ManagerFactory().get<AppStateManager>();
  final currentState = appStateManager.state;
  if (currentState is AppForceUpgradeState) {
    return Future.value();
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (_) => CreateRoomDialog(
      onCreateRoom: onCreateRoom,
      initialRoomName: initialRoomName,
      autofocus: autofocus,
      isPaidUser: isPaidUser,
      showWaitingRoom: showWaitingRoom,
    ),
  );
}

Future<void> showEditRoomDialog(
  BuildContext context, {
  required OnEditRoomValue onEditRoom,
  String? initialRoomName,
  bool autofocus = true,
  ParticipantDisplayColors? displayColors,
  bool showWaitingRoom = false,
  String? meetingLinkName,
  bool initialWaitingRoomEnabled = false,
}) {
  // Block dialog when in force upgrade state
  final appStateManager = ManagerFactory().get<AppStateManager>();
  final currentState = appStateManager.state;
  if (currentState is AppForceUpgradeState) {
    return Future.value();
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (_) => CreateRoomDialog(
      onEditRoom: onEditRoom,
      initialRoomName: initialRoomName,
      autofocus: autofocus,
      selectAllOnFocus: true,
      displayColors: displayColors,
      showWaitingRoom: showWaitingRoom,
      meetingLinkName: meetingLinkName,
      initialWaitingRoomEnabled: initialWaitingRoomEnabled,
    ),
  );
}

class CreateRoomDialog extends StatefulWidget {
  const CreateRoomDialog({
    super.key,
    this.onCreateRoom,
    this.onEditRoom,
    this.initialRoomName,
    this.autofocus = true,
    this.selectAllOnFocus = false,
    this.displayColors,
    this.isPaidUser = false,
    this.showWaitingRoom = false,
    this.meetingLinkName,
    this.initialWaitingRoomEnabled = false,
  }) : assert(
         (onCreateRoom != null) ^ (onEditRoom != null),
         'Provide exactly one of onCreateRoom or onEditRoom',
       );

  final OnCreateRoomValue? onCreateRoom;
  final OnEditRoomValue? onEditRoom;
  final String? initialRoomName;
  final bool autofocus;
  final bool selectAllOnFocus;
  final ParticipantDisplayColors? displayColors;
  final bool isPaidUser;

  /// Gates the waiting-room option (MeetWaitingRoom flag, resolved by the caller's bloc).
  final bool showWaitingRoom;
  final String? meetingLinkName;
  final bool initialWaitingRoomEnabled;

  @override
  State<CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<CreateRoomDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initialRoomName ?? '',
  );
  final FocusNode _focus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  bool _hasInitialized = false;
  bool _isButtonEnabled = false;
  bool _waitingRoomEnabled = false;
  bool _canManageWaitingRoom = false;
  bool _isUpdatingWaitingRoom = false;
  String? _waitingRoomError;

  @override
  void initState() {
    super.initState();
    _waitingRoomEnabled = widget.initialWaitingRoomEnabled;
    _focus.addListener(_onFocusChange);
    _ctrl.addListener(_onTextChanged);
    _isButtonEnabled = _ctrl.text.trim().isNotEmpty;
    if (widget.selectAllOnFocus &&
        widget.showWaitingRoom &&
        widget.meetingLinkName != null) {
      unawaited(_loadCanManageWaitingRoom());
    }
  }

  Future<void> _loadCanManageWaitingRoom() async {
    final meetingLinkName = widget.meetingLinkName;
    if (meetingLinkName == null || meetingLinkName.isEmpty) {
      return;
    }
    try {
      final appCore = ManagerFactory().get<AppCoreManager>().appCore;
      final canManage = await resolveCanManageWaitingRoom(
        appCore: appCore,
        meetLinkName: meetingLinkName,
      );
      if (mounted) {
        setState(() {
          _canManageWaitingRoom = canManage;
        });
      }
    } catch (e) {
      l.logger.w('[CreateRoomDialog] Failed to resolve manage waiting room: $e');
    }
  }

  void _onTextChanged() {
    final newEnabled = _ctrl.text.trim().isNotEmpty;
    if (_isButtonEnabled != newEnabled) {
      setState(() {
        _isButtonEnabled = newEnabled;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Perform initial focus here when inherited widgets are available
    if (!_hasInitialized) {
      _hasInitialized = true;
      if (widget.autofocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focus.requestFocus();
          if (widget.selectAllOnFocus) {
            _ctrl.selection = TextSelection(
              baseOffset: 0,
              extentOffset: _ctrl.text.length,
            );
          }
        });
      }
    }
  }

  void _onFocusChange() {
    final hasFocus = _focus.hasFocus;
    if (hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _focus.removeListener(_onFocusChange);
    _ctrl.dispose();
    _focus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _submit() {
    final roomName = _ctrl.text.trim();
    if (roomName.isEmpty) {
      return;
    }
    Navigator.of(context).pop();
    final onEditRoom = widget.onEditRoom;
    if (onEditRoom != null) {
      onEditRoom(roomName);
      return;
    }
    widget.onCreateRoom!(
      roomName,
      waitingRoom:
          _waitingRoomEnabled, // To-do: check if it's a paid feature; widget.isPaidUser && _waitingRoomEnabled
    );
  }

  String _formatWaitingRoomLabel(BuildContext context) {
    return _waitingRoomEnabled
        ? context.local.schedule_waiting_room_on
        : context.local.schedule_waiting_room_off;
  }

  Widget _buildWaitingRoomOption(BuildContext context) {
    final waitingRoomLabel = _formatWaitingRoomLabel(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GestureDetector(
          onTap: _isUpdatingWaitingRoom ? null : _selectWaitingRoom,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ).copyWith(right: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isUpdatingWaitingRoom) ...[
                  CustomLoading(
                    size: 16,
                    strokeWidth: 2,
                    color: context.colors.protonBlue,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  waitingRoomLabel,
                  style: ProtonStyles.body1Medium(
                    color: context.colors.protonBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_waitingRoomError != null)
          Padding(
            padding: const EdgeInsets.only(right: 32, left: 16, bottom: 4),
            child: Text(
              _waitingRoomError!,
              textAlign: TextAlign.right,
              style: ProtonStyles.body2Medium(
                color: context.colors.notificationError,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _selectWaitingRoom() async {
    final meetingLinkName = widget.meetingLinkName;
    final isEditWithPreMeetingApi =
        widget.selectAllOnFocus && meetingLinkName != null && _canManageWaitingRoom;

    await showWaitingRoomSheet(
      context,
      selected: _waitingRoomEnabled,
      isOnOptionEnabled: true,
      onSelect: (enabled) async {
        if (!isEditWithPreMeetingApi) {
          setState(() {
            _waitingRoomEnabled = enabled;
          });
          return;
        }
        if (_isUpdatingWaitingRoom || enabled == _waitingRoomEnabled) {
          return;
        }

        final previousEnabled = _waitingRoomEnabled;
        setState(() {
          _waitingRoomEnabled = enabled;
          _isUpdatingWaitingRoom = true;
          _waitingRoomError = null;
        });

        try {
          final appCore = ManagerFactory().get<AppCoreManager>().appCore;
          await updatePreMeetingWaitingRoomSetting(
            appCore: appCore,
            meetLinkName: meetingLinkName,
            enable: enabled,
          );
          if (!mounted) {
            return;
          }
          setState(() {
            _isUpdatingWaitingRoom = false;
          });
        } on BridgeError catch (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _waitingRoomEnabled = previousEnabled;
            _isUpdatingWaitingRoom = false;
            _waitingRoomError = error.userMessage;
          });
        } catch (error) {
          if (!mounted) {
            return;
          }
          setState(() {
            _waitingRoomEnabled = previousEnabled;
            _isUpdatingWaitingRoom = false;
            _waitingRoomError = extractErrorMessage(error);
          });
        }
      },
    );
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients && mounted) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      if (maxScroll > 0) {
        _scrollController.animateTo(
          maxScroll,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderNorm = context.colors.appBorderNorm;
    final Color bgField = context.colors.backgroundNorm;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnimatedPadding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: BaseBottomSheet(
          blurSigma: 14,
          onBackdropTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(40),
          borderSide: BorderSide(
            color: context.colors.white.withValues(alpha: 0.04),
          ),
          backgroundColor: context.colors.backgroundDark.withValues(alpha: 0.3),
          scrollController: _scrollController,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(child: BottomSheetHandleBar()),
                const SizedBox(height: 32),

                /// Icon above title
                RepaintBoundary(
                  child:
                      widget.selectAllOnFocus &&
                          widget.displayColors?.roomLogo != null
                      ? widget.displayColors!.roomLogo!.svg56()
                      : context.images.defaultRoomLogo.svg56(),
                ),
                const SizedBox(height: 24),

                /// Title & subtitle
                RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Text(
                          widget.selectAllOnFocus
                              ? context.local.edit_room
                              : context.local.create_new_room,
                          textAlign: TextAlign.center,
                          style: ProtonStyles.headline(
                            color: context.colors.textNorm,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.local.create_room_subtitle,
                          textAlign: TextAlign.center,
                          style: ProtonStyles.body2Medium(
                            color: context.colors.textWeak,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                /// Field card
                RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      decoration: ShapeDecoration(
                        color: bgField,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(color: borderNorm),
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.local.room_name,
                            style: ProtonStyles.body2Medium(
                              color: context.colors.textWeak,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _ctrl,
                            focusNode: _focus,
                            autofocus: widget.autofocus,
                            textInputAction: TextInputAction.done,
                            minLines: 1,
                            maxLines: 2,
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText: context.local.enter_room_name_hint,
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              hintStyle: ProtonStyles.body2Medium(
                                color: context.colors.textHint,
                              ),
                            ),
                            style: ProtonStyles.body2Medium(
                              color: context.colors.textNorm,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if ((!widget.selectAllOnFocus && widget.showWaitingRoom) ||
                    (widget.selectAllOnFocus &&
                        widget.showWaitingRoom &&
                        _canManageWaitingRoom)) ...[
                  const SizedBox(height: 10),
                  RepaintBoundary(child: _buildWaitingRoomOption(context)),
                ],

                /// Create button
                RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _isButtonEnabled ? _submit : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isButtonEnabled
                              ? (widget.selectAllOnFocus &&
                                        widget.displayColors != null
                                    ? widget
                                          .displayColors!
                                          .actionBackgroundColor
                                    : context.colors.protonBlue)
                              : context.colors.interActionWeekMinor1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(200),
                          ),
                        ),
                        child: Text(
                          widget.selectAllOnFocus
                              ? context.local.save
                              : context.local.create_and_copy_link,
                          style: ProtonStyles.body1Semibold(
                            color: _isButtonEnabled
                                ? context.colors.textInverted
                                : context.colors.textDisable,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
