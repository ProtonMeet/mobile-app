import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class BaseBottomSheet extends StatelessWidget {
  const BaseBottomSheet({
    required this.child,
    super.key,
    this.onBackdropTap,
    this.dragOffset = 0,
    this.maxWidth = maxMobileSheetWidth,
    this.maxHeight,
    this.borderRadius,
    this.backgroundColor,
    this.borderSide,
    this.blurSigma = 8,
    this.contentPadding = EdgeInsets.zero,
    this.scrollController,
  });

  final Widget child;
  final VoidCallback? onBackdropTap;
  final double dragOffset;
  final double maxWidth;
  final double? maxHeight;
  final BorderRadius? borderRadius;
  final Color? backgroundColor;
  final BorderSide? borderSide;
  final double blurSigma;
  final EdgeInsetsGeometry contentPadding;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final handleBackdropTap =
        onBackdropTap ?? () => Navigator.of(context).maybePop();
    final resolvedBorderRadius =
        borderRadius ??
        const BorderRadius.only(
          topLeft: Radius.circular(40),
          topRight: Radius.circular(40),
        );
    final resolvedBackgroundColor =
        backgroundColor ??
        context.colors.interActionWeekMinor2.withValues(alpha: 0.30);
    final resolvedBorderSide =
        borderSide ?? BorderSide(color: Colors.white.withValues(alpha: 0.04));

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: handleBackdropTap,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Transform.translate(
            offset: Offset(0, dragOffset),
            child: ClipRRect(
              borderRadius: resolvedBorderRadius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth,
                    maxHeight: maxHeight ?? double.infinity,
                  ),
                  child: Container(
                    padding: contentPadding,
                    decoration: ShapeDecoration(
                      color: resolvedBackgroundColor,
                      shape: RoundedRectangleBorder(
                        side: resolvedBorderSide,
                        borderRadius: resolvedBorderRadius,
                      ),
                    ),
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: SafeArea(
                        // ignore: avoid_redundant_argument_values
                        top: true,
                        // ignore: avoid_redundant_argument_values
                        left: true,
                        // ignore: avoid_redundant_argument_values
                        right: true,
                        // ignore: avoid_redundant_argument_values
                        bottom: true,
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
