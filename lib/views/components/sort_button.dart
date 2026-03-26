import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';

class SortButton extends StatelessWidget {
  const SortButton({
    required this.onTap,
    this.width = 40.0,
    this.height = 40.0,
    super.key,
  });

  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(200),
      child: Container(
        width: 40,
        height: 40,
        padding: const EdgeInsets.all(12),
        decoration: ShapeDecoration(
          color: context.colors.backgroundCard,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: context.colors.borderCard),
            borderRadius: BorderRadius.circular(200),
          ),
        ),
        child: context.images.iconSorting.svg16(color: context.colors.textWeak),
      ),
    );
  }
}
