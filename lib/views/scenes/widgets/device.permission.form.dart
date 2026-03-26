import 'package:flutter/material.dart';
import 'package:meet/constants/assets.gen.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/close_button_v1.dart';

class PermissionForm extends StatelessWidget {
  final String title;
  final String content;
  final Widget useDeviceButton;
  final Widget useWithoutDeviceButton;
  final VoidCallback onClose;

  const PermissionForm({
    required this.title,
    required this.content,
    required this.useDeviceButton,
    required this.useWithoutDeviceButton,
    required this.onClose,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 28,
        vertical: 32,
      ).copyWith(top: 16),
      backgroundColor: context.colors.backgroundNorm,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Transform.translate(
              offset: const Offset(12, 0),
              child: CloseButtonV1(
                onPressed: () {
                  onClose();
                  Navigator.pop(context);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Assets.images.icon.protonMeetBrand.svg(
              width: 150,
              height: 40,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: ProtonStyles.body1Medium(color: context.colors.textNorm),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: ProtonStyles.body2Regular(color: context.colors.textWeak),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          useDeviceButton,
          const SizedBox(height: 12),
          useWithoutDeviceButton,
        ],
      ),
    );
  }
}
