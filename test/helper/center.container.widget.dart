import 'package:flutter/widgets.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class CenterContainer extends StatelessWidget {
  const CenterContainer({
    required this.height,
    required this.child,
    super.key,
  });

  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: context.colors.backgroundNorm,
      child: Center(child: child),
    );
  }
}
