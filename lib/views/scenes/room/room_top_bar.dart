import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class RoomTopBar extends StatelessWidget implements PreferredSizeWidget {
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

  final Widget? shareScreenWidget;
  final String roomName;
  final VoidCallback onSwapCamera;
  final bool showSwapCamera;
  final bool isPaidUser;
  final bool showSpeakerButton;
  final VoidCallback? onSpeakerButtonPressed;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppBar(
      automaticallyImplyLeading: false,
      elevation: 0,
      backgroundColor: colors.interActionWeakMinor3,
      titleSpacing: 16,
      title: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    _buildLeadingWidget(context),
                    const SizedBox(width: 8),
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
              child: IconButton(
                onPressed: onSpeakerButtonPressed,
                icon: context.images.iconSpeakerPhone.svg(
                  width: 20,
                  height: 20,
                ),
                tooltip: "Select speaker",
              ),
            ),
          ),
        if (showSwapCamera)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: IconButton(
              onPressed: onSwapCamera,
              icon: context.images.iconSwapCamera.svg(width: 20, height: 20),
              tooltip: 'Swap camera',
            ),
          ),
      ],
    );
  }

  Widget _buildLeadingWidget(BuildContext context) {
    final textStyle = ProtonStyles.body2Medium(color: context.colors.textNorm);

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
