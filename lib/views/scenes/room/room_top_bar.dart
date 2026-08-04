import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/constants/test_ids.dart';
import 'package:meet/helper/audio_output_display.dart';
import 'package:meet/views/components/test_id.dart';
import 'package:meet/helper/desktop_content_fit.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_state.dart';

class RoomTopBar extends StatelessWidget {
  const RoomTopBar({
    required this.roomName,
    required this.onSwapCamera,
    this.shareScreenWidget,
    this.showSwapCamera = false,
    this.isPaidUser = false,
    this.showSpeakerButton = false,
    this.onSpeakerButtonPressed,
    super.key,
  });

  static const double toolbarHeight = 60;

  static double totalHeight(BuildContext context) {
    return toolbarHeight +
        MediaQuery.paddingOf(context).top +
        DesktopContentFit.extraTopPadding(context);
  }

  final Widget? shareScreenWidget;
  final String roomName;
  final VoidCallback onSwapCamera;
  final bool showSwapCamera;
  final bool isPaidUser;
  final bool showSpeakerButton;
  final VoidCallback? onSpeakerButtonPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final windowChromeInsets = DesktopContentFit.minimumSafeArea(context);
    final barBackground = colors.interActionWeakMinor3;

    // Opaque, isolated layer so side-panel BackdropFilter never bleeds into the
    // top bar (including the status-bar / window-chrome inset above the toolbar).
    return RepaintBoundary(
      child: ColoredBox(
        color: barBackground,
        child: SizedBox(
          height: totalHeight(context),
          child: SafeArea(
            bottom: false,
            minimum: windowChromeInsets,
            child: SizedBox(
              height: toolbarHeight,
              child: AppBar(
                automaticallyImplyLeading: false,
                elevation: 0,
                scrolledUnderElevation: 0,
                surfaceTintColor: Colors.transparent,
                shadowColor: Colors.transparent,
                toolbarHeight: toolbarHeight,
                backgroundColor: Colors.transparent,
                titleSpacing: 16,
                title: LayoutBuilder(
                  builder: (context, constraints) {
                    if (shareScreenWidget != null) {
                      return SizedBox(
                        width: constraints.maxWidth,
                        child: shareScreenWidget,
                      );
                    }

                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildLeadingWidget(context),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                actions: [
                  if (showSpeakerButton)
                    Transform.translate(
                      offset: Offset(showSwapCamera ? 14.0 : 0.0, 0.0),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child:
                            BlocSelector<
                              RoomBloc,
                              RoomState,
                              (bool, bool, bool)
                            >(
                              selector: (state) => (
                                state.isSpeakerPhone,
                                state.hasExternalAudioOutput,
                                state.hasBluetoothAudioOutput,
                              ),
                              builder: (context, data) {
                                final icon = AudioOutputDisplay.icon(
                                  context,
                                  isSpeakerPhone: data.$1,
                                  hasExternalAudioOutput: data.$2,
                                  hasBluetoothAudioOutput: data.$3,
                                );
                                return TestId(
                                  id: TestIds.roomSpeakerOutput,
                                  button: true,
                                  child: IconButton(
                                    onPressed: onSpeakerButtonPressed,
                                    icon: icon.svg20(
                                      color: context.colors.textNorm,
                                    ),
                                    tooltip: 'Select speaker',
                                  ),
                                );
                              },
                            ),
                      ),
                    ),
                  if (showSwapCamera)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: TestId(
                        id: TestIds.roomSwapCamera,
                        button: true,
                        child: IconButton(
                          onPressed: onSwapCamera,
                          icon: context.images.iconSwapCamera.svg20(
                            color: context.colors.textNorm,
                          ),
                          tooltip: 'Swap camera',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingWidget(BuildContext context) {
    final textStyle = ProtonStyles.body1Semibold(
      color: context.colors.interActionNorm,
    );

    if (shareScreenWidget != null) {
      return shareScreenWidget!;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 8),
        Text(roomName, style: textStyle),
      ],
    );
  }
}
