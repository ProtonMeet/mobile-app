import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/close_button_v1.dart';

class CustomHeader extends StatelessWidget {
  final String? title;
  final AxisDirection buttonDirection;
  final Widget? button;
  final EdgeInsets? padding;
  final TextStyle? titleStyle;

  const CustomHeader({
    required this.buttonDirection,
    this.title,
    this.button,
    this.padding,
    this.titleStyle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Padding(
        padding:
            padding ??
            const EdgeInsets.symmetric(
              horizontal: defaultPadding,
              vertical: defaultPadding,
            ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            buttonDirection == AxisDirection.left
                ? Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child:
                          button ??
                          CloseButtonV1(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                    ),
                  )
                : const Spacer(),
            Expanded(
              flex: 3,
              child: Text(
                title ?? "",
                style:
                    titleStyle ??
                    ProtonStyles.body2Medium(color: context.colors.textNorm),
                textAlign: TextAlign.center,
              ),
            ),
            buttonDirection == AxisDirection.right
                ? Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child:
                          button ??
                          CloseButtonV1(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                          ),
                    ),
                  )
                : const Spacer(),
          ],
        ),
      ),
    );
  }
}
