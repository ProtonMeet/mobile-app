import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      /// use system themed background before protonColor initialized
      color: context.colors.interActionWeakMinor3,
      child: Center(
        child: context.images.iconLeaveMeetingGuest.svg(
          fit: BoxFit.fitWidth,
          width: context.width / 4,
        ),
      ),
    );
  }
}
