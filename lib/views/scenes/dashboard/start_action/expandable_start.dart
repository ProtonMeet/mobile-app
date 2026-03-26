import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

import 'start_action_text.dart';

class ExpandableStart extends StatelessWidget {
  const ExpandableStart({
    required this.t,
    required this.pillH,
    required this.onToggle,
    required this.onInstant,
    super.key,
  });

  final double t;
  final double pillH;
  final VoidCallback onToggle;
  final VoidCallback onInstant;

  @override
  Widget build(BuildContext context) {
    final sigma = 3.0;
    final bgColor = context.colors.interActionWeekMinor2.withValues(
      alpha: 0.40,
    );
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: t < 0.5 ? onToggle : onInstant,
          child: Material(
            color: Colors.transparent,
            child: t < 0.2
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(40),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                      child: Container(
                        height: pillH,
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: BoxDecoration(
                          color: bgColor,
                          border: Border.all(color: bgColor),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: defaultAnimationDuration,
                            child: const StartActionText(),
                          ),
                        ),
                      ),
                    ),
                  )
                : Container(
                    height: pillH,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      border: Border.all(color: bgColor),
                      borderRadius: BorderRadius.circular(40),
                      color: bgColor,
                    ),
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: defaultAnimationDuration,
                        child: const StartActionTextLong(),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
