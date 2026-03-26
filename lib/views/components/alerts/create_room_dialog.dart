import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/manager.factory.dart';
import 'package:meet/views/components/alerts/base_bottom_sheet.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/room/get_participant_display_colors.dart';

typedef OnRoomValue = void Function(String roomName);

Future<void> showCreateRoomDialog(
  BuildContext context, {
  required OnRoomValue onCreateRoom,
  String? initialRoomName,
  bool autofocus = true,
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
    ),
  );
}

Future<void> showEditRoomDialog(
  BuildContext context, {
  required OnRoomValue onEditRoom,
  String? initialRoomName,
  bool autofocus = true,
  ParticipantDisplayColors? displayColors,
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
      onCreateRoom: onEditRoom,
      initialRoomName: initialRoomName,
      autofocus: autofocus,
      selectAllOnFocus: true,
      displayColors: displayColors,
    ),
  );
}

class CreateRoomDialog extends StatefulWidget {
  const CreateRoomDialog({
    required this.onCreateRoom,
    super.key,
    this.initialRoomName,
    this.autofocus = true,
    this.selectAllOnFocus = false,
    this.displayColors,
  });

  final OnRoomValue onCreateRoom;
  final String? initialRoomName;
  final bool autofocus;
  final bool selectAllOnFocus;
  final ParticipantDisplayColors? displayColors;

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

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
    _ctrl.addListener(_onTextChanged);
    _isButtonEnabled = _ctrl.text.trim().isNotEmpty;
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
    widget.onCreateRoom(roomName);
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
