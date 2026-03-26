import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/alerts/media_permission_dialog.dart';
import 'package:meet/views/components/close_button_v1.dart';
import 'package:meet/views/scenes/signin/auth_bloc.dart';
import 'package:meet/views/scenes/signin/auth_state.dart';

import 'prejoin_arguments.dart';
import 'prejoin_bloc.dart';
import 'prejoin_event.dart';
import 'prejoin_screen.dart';
import 'prejoin_state.dart';

class PreJoinPage extends StatefulWidget {
  final PreJoinBloc bloc;
  final AuthBloc authBloc;
  final JoinArgs? joinArgs;
  static const String routeName = '/preJoin';
  const PreJoinPage({
    required this.bloc,
    required this.authBloc,
    this.joinArgs,
    super.key,
  });

  @override
  State<PreJoinPage> createState() => _PreJoinPageState();
}

class _PreJoinPageState extends State<PreJoinPage> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _roomNameController;
  late final FocusNode _displayNameFocusNode;
  late final FocusNode _meetingLinkFocusNode;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController();
    _roomNameController = TextEditingController();
    _displayNameFocusNode = FocusNode();
    _meetingLinkFocusNode = FocusNode();
    _displayNameController.text = widget.authBloc.state.displayName;

    // Defer heavy initialization until after first frame to make navigation feel instant
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Dispatch initialization event after page is shown
        if (widget.joinArgs != null) {
          widget.bloc.add(
            PreJoinInitialized(
              widget.joinArgs!,
              widget.authBloc.state.displayName,
            ),
          );
        }

        // Sync display name from BLoC state
        if ((_displayNameController.text.isEmpty ||
                widget.bloc.state.shouldOverrideAuthDisplayName) &&
            widget.bloc.state.displayName.isNotEmpty &&
            !_displayNameFocusNode.hasFocus) {
          _displayNameController.text = widget.bloc.state.displayName;
        }
      }
    });
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _roomNameController.dispose();
    _displayNameFocusNode.dispose();
    _meetingLinkFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        // Provide existing instances safely
        BlocProvider<PreJoinBloc>.value(value: widget.bloc),
        BlocProvider<AuthBloc>.value(value: widget.authBloc),
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<AuthBloc, AuthState>(
            listenWhen: (prev, curr) =>
                prev.displayName != curr.displayName &&
                curr.displayName.isNotEmpty,
            listener: (context, state) {
              // Only update controller if it's empty and user is not actively typing
              if (_displayNameController.text.isEmpty &&
                  !_displayNameFocusNode.hasFocus) {
                _displayNameController.text = state.displayName;
                widget.bloc.add(UpdateDisplayName(state.displayName));
              }
            },
          ),
          BlocListener<PreJoinBloc, PreJoinState>(
            listenWhen: (prev, curr) {
              // Trigger when:
              // 1. Display name changes and is not empty
              // 2. Loading completes (isLoading: true -> false) and we have a display name
              return (prev.displayName != curr.displayName &&
                      curr.displayName.isNotEmpty) ||
                  (prev.isLoading &&
                      !curr.isLoading &&
                      curr.displayName.isNotEmpty);
            },
            listener: (context, state) {
              // Sync display name from BLoC state to controller if controller is empty
              // This ensures placeholder names are shown in the text field
              if ((_displayNameController.text.isEmpty ||
                      state.shouldOverrideAuthDisplayName) &&
                  !_displayNameFocusNode.hasFocus &&
                  state.displayName.isNotEmpty) {
                _displayNameController.text = state.displayName;
              }
            },
          ),
          BlocListener<PreJoinBloc, PreJoinState>(
            listenWhen: (prev, curr) =>
                prev.shouldShowCameraPermissionSettings !=
                    curr.shouldShowCameraPermissionSettings &&
                curr.shouldShowCameraPermissionSettings,
            listener: (context, state) async {
              await showMediaPermissionSettingsDialog(
                context,
                cameraDenied: !state.isCameraPermissionGranted,
                microphoneDenied: !state.isMicrophonePermissionGranted,
                onReturned: () {},
              );
              if (context.mounted) {
                widget.bloc.add(CameraPermissionSettingsConsumed());
              }
            },
          ),
          BlocListener<PreJoinBloc, PreJoinState>(
            listenWhen: (prev, curr) =>
                prev.shouldShowMicrophonePermissionSettings !=
                    curr.shouldShowMicrophonePermissionSettings &&
                curr.shouldShowMicrophonePermissionSettings,
            listener: (context, state) async {
              await showMediaPermissionSettingsDialog(
                context,
                cameraDenied: !state.isCameraPermissionGranted,
                microphoneDenied: !state.isMicrophonePermissionGranted,
                onReturned: () {},
              );
              if (context.mounted) {
                widget.bloc.add(MicrophonePermissionSettingsConsumed());
              }
            },
          ),
        ],
        child: BlocSelector<AuthBloc, AuthState, AuthState>(
          selector: (s) => s,
          builder: (context, state) {
            return Scaffold(
              backgroundColor: context.colors.backgroundNorm,
              resizeToAvoidBottomInset: true,
              body: SafeArea(
                child: Stack(
                  children: [
                    ColoredBox(
                      color: context.colors.clear,
                      child: PreJoinScreen(
                        bloc: widget.bloc,
                        displayNameController: _displayNameController,
                        roomNameController: _roomNameController,
                        displayNameFocusNode: _displayNameFocusNode,
                        meetingLinkFocusNode: _meetingLinkFocusNode,
                      ),
                    ),
                    // Close button in top left
                    Positioned(
                      top: 0,
                      left: 16,
                      child: CloseButtonV1(
                        onPressed: () => Navigator.of(context).maybePop(),
                        backgroundColor: Colors.transparent,
                        iconSize: 24,
                        iconColor: context.colors.textNorm.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
