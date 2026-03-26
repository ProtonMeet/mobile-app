import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/room/room_bloc.dart';
import 'package:meet/views/scenes/room/room_event.dart';
import 'package:meet/views/scenes/room/room_state.dart';

class _SpeakerPhonePanelConstants {
  static const double borderRadiusMedium = 24.0;
  static const double borderRadiusLarge = 40.0;
  static const double borderColorAlpha = 0.03;
}

class SpeakerPhonePanel extends StatefulWidget {
  const SpeakerPhonePanel({super.key});

  @override
  State<SpeakerPhonePanel> createState() => _SpeakerPhonePanelState();
}

class _SpeakerPhonePanelState extends State<SpeakerPhonePanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Decoration _buildContainerDecoration(BuildContext context) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(_SpeakerPhonePanelConstants.borderRadiusMedium),
      topRight: Radius.circular(_SpeakerPhonePanelConstants.borderRadiusMedium),
    );

    return BoxDecoration(
      color: context.colors.blurBottomSheetBackground,
      border: Border.all(
        color: Colors.white.withValues(
          alpha: _SpeakerPhonePanelConstants.borderColorAlpha,
        ),
      ),
      borderRadius: borderRadius,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = context.isLandscape && mobile;
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(_SpeakerPhonePanelConstants.borderRadiusLarge),
        topRight: Radius.circular(
          _SpeakerPhonePanelConstants.borderRadiusLarge,
        ),
      ),
      child: RepaintBoundary(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: double.infinity,
            // height: double.infinity, // don't need to make height match parent since it only has two items
            decoration: _buildContainerDecoration(context),
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.deferToChild,
              child: _buildScrollableContent(context, isLandscape),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableContent(BuildContext context, bool isLandscape) {
    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              automaticallyImplyLeading: false,
              toolbarHeight: !isLandscape ? 36.0 : 8.0,
              expandedHeight: !isLandscape ? 36.0 : 8.0,
              flexibleSpace: SizedBox.expand(
                child: ClipRRect(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: Colors.transparent,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(
                            _SpeakerPhonePanelConstants.borderRadiusMedium,
                          ),
                          topRight: Radius.circular(
                            _SpeakerPhonePanelConstants.borderRadiusMedium,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  /// Meeting details section
                  BlocSelector<RoomBloc, RoomState, bool>(
                    selector: (state) => state.isSpeakerPhone,
                    builder: (context, isSpeakerPhone) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMenuItem(
                            context,
                            icon: Icon(
                              Icons.headphones,
                              size: 24,
                              color: context.colors.interActionNorm,
                            ),
                            label: 'Default device',
                            selected: !isSpeakerPhone,
                            onTap: () {
                              context.read<RoomBloc>().add(
                                const SetSpeakerPhone(enabled: false),
                              );
                            },
                          ),
                          _buildMenuItem(
                            context,
                            icon: Icon(
                              Icons.volume_up_rounded,
                              size: 24,
                              color: context.colors.interActionNorm,
                            ),
                            label: 'Phone speakers',
                            selected: isSpeakerPhone,
                            onTap: () {
                              context.read<RoomBloc>().add(
                                const SetSpeakerPhone(enabled: true),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ]),
              ),
            ),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: !isLandscape ? 36.0 : 8.0,
          child: AbsorbPointer(
            child: Stack(
              children: [
                if (!isLandscape)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 36.0,
                    child: BottomSheetHandleBar(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required Widget icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 16),
                  icon,
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      label,
                      style: ProtonStyles.body1Medium(
                        color: context.colors.interActionNorm,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 16),
                    Icon(
                      Icons.check,
                      color: context.colors.interActionNorm,
                      size: 20,
                    ),
                  ],
                  const SizedBox(width: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
