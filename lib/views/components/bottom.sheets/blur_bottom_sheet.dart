import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class BlurBottomSheet extends StatelessWidget {
  const BlurBottomSheet({
    required this.child,
    this.onDismiss,
    this.maxWidth,
    super.key,
  });

  final Widget child;
  final VoidCallback? onDismiss;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          /// Transparent background (tap to dismiss)
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).maybePop();
                onDismiss?.call();
              },
              child: Container(color: Colors.transparent),
            ),
          ),
          // Content with blur
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: maxWidth != null
                  ? ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth!),
                      child: _buildBlurContent(context),
                    )
                  : _buildBlurContent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlurContent(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(maxHeight: context.height),
          decoration: ShapeDecoration(
            color: context.colors.blurBottomSheetBackground,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: context.colors.appBorderNorm),
              borderRadius: BorderRadius.circular(40),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
