import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';

class SearchButton extends StatelessWidget {
  const SearchButton({
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
    return Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(
        color: context.colors.backgroundCard,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: context.colors.borderCard),
          borderRadius: BorderRadius.circular(200),
        ),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: context.images.iconChatSearch.svg20(
          color: context.colors.textWeak,
        ),
      ),
    );
  }
}
