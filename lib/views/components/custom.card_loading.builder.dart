import 'package:card_loading/card_loading.dart';
import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class CustomCardLoadingBuilder {
  final double height;
  final double? width;
  final EdgeInsets? margin;
  final BorderRadius? borderRadius;
  final Duration animationDuration;
  final Duration animationDurationTwo;
  final Curve curve;
  final bool withChangeDuration;

  const CustomCardLoadingBuilder({
    required this.height,
    this.width,
    this.margin,
    this.borderRadius,
    this.animationDuration = const Duration(milliseconds: 750),
    this.animationDurationTwo = const Duration(milliseconds: 450),
    this.curve = Curves.easeInOutSine,
    this.withChangeDuration = true,
  });

  Widget build(BuildContext context) {
    return CardLoading(
      height: height,
      width: width,
      margin: margin,
      borderRadius: borderRadius,
      animationDuration: animationDuration,
      animationDurationTwo: animationDurationTwo,
      cardLoadingTheme: CardLoadingTheme(
        colorOne: Color(0xFF454554),
        colorTwo: context.colors.backgroundSecondary,
      ),
      curve: curve,
      withChangeDuration: withChangeDuration,
    );
  }
}
