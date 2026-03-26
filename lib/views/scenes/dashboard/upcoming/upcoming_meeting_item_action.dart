import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';

class UpcomingMeetingItemAction extends StatelessWidget {
  const UpcomingMeetingItemAction({
    required this.onTap,
    required this.label,
    this.icon,
    super.key,
  });

  final VoidCallback onTap;
  final String label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    padding: const EdgeInsets.all(10),
                    decoration: ShapeDecoration(
                      color: context.colors.borderCard,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: context.colors.appBorderNorm),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Center(
                      child: icon ?? context.images.iconAdd.svg20(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Opacity(
                      opacity: 0.90,
                      child: Text(
                        label,
                        style: ProtonStyles.body1Medium(
                          color: context.colors.textNorm,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
