import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class UserAvatarButton extends StatelessWidget {
  const UserAvatarButton({
    required this.displayName,
    required this.onTap,
    this.width = 40.0,
    this.height = 40.0,
    super.key,
  });

  final String? displayName;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final String initial = (displayName?.isNotEmpty == true
        ? displayName!.trim()[0].toUpperCase()
        : '?');
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.avatarPurple1Background,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: TextButton(
        onPressed: onTap,
        child: Text(
          initial,
          style: ProtonStyles.body2Semibold(color: colors.avatarPurple1Text),
        ),
      ),
    );
  }
}
