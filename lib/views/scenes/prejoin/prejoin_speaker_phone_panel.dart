import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:meet/views/components/bottom.sheets/bottom_sheet_handle_bar.dart';
import 'package:meet/views/scenes/prejoin/prejoin_bloc.dart';
import 'package:meet/views/scenes/prejoin/prejoin_event.dart';
import 'package:meet/views/scenes/prejoin/prejoin_state.dart';

class _PreJoinSpeakerPhonePanelConstants {
  static const double borderRadiusMedium = 24.0;
  static const double borderColorAlpha = 0.03;
}

class PreJoinSpeakerPhonePanel extends StatelessWidget {
  const PreJoinSpeakerPhonePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final isLandscape = context.isLandscape && mobile;
    return RepaintBoundary(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          decoration: _buildContainerDecoration(context),
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            behavior: HitTestBehavior.deferToChild,
            child: _buildScrollableContent(context, isLandscape),
          ),
        ),
      ),
    );
  }

  Decoration _buildContainerDecoration(BuildContext context) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(
        _PreJoinSpeakerPhonePanelConstants.borderRadiusMedium,
      ),
      topRight: Radius.circular(
        _PreJoinSpeakerPhonePanelConstants.borderRadiusMedium,
      ),
    );

    return BoxDecoration(
      color: context.colors.blurBottomSheetBackground,
      border: Border.all(
        color: Colors.white.withValues(
          alpha: _PreJoinSpeakerPhonePanelConstants.borderColorAlpha,
        ),
      ),
      borderRadius: borderRadius,
    );
  }

  Widget _buildScrollableContent(BuildContext context, bool isLandscape) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isLandscape) const BottomSheetHandleBar(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: BlocSelector<PreJoinBloc, PreJoinState, bool>(
            selector: (state) => state.isSpeakerPhoneEnabled,
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
                      context.read<PreJoinBloc>().add(
                        SetSpeakerPhoneEnabled(enabled: false),
                      );
                      Navigator.of(context).pop();
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
                      context.read<PreJoinBloc>().add(
                        SetSpeakerPhoneEnabled(enabled: true),
                      );
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
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
