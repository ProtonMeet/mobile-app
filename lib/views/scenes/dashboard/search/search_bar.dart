import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/svg_gen_image_extension.dart';
import 'package:meet/views/components/sort_button.dart';

class DashboardSearchBar extends StatelessWidget {
  const DashboardSearchBar({
    required this.onTap,
    this.onFilterTap,
    this.onSortTap,
    super.key,
  });

  final VoidCallback onTap;
  final VoidCallback? onFilterTap;
  final VoidCallback? onSortTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 8, left: 24, right: 24, bottom: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(200),
              child: Container(
                height: 40,
                padding: const EdgeInsets.only(top: 10, bottom: 10, left: 12),
                decoration: ShapeDecoration(
                  color: context.colors.backgroundCard,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: context.colors.borderCard),
                    borderRadius: BorderRadius.circular(200),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: 0.80,
                      child: context.images.iconChatSearch.svg20(
                        color: context.colors.textWeak,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (onSortTap != null) ...[
            const SizedBox(width: 6),
            SortButton(onTap: onSortTap!),
          ],
          if (onFilterTap != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onFilterTap,
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
                child: context.images.iconSettings.svg16(
                  color: context.colors.textWeak,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
