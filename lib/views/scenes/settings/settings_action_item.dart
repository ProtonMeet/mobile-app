import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/settings/app_settings.dart'
    show AppSettingsBottomSheet;

/// Single tappable row for [AppSettingsBottomSheet] (and similar settings UIs).
class SettingsActionItem extends StatelessWidget {
  const SettingsActionItem({
    required this.title,
    required this.onTap,
    super.key,
    this.isFirst = false,
    this.isLast = false,
    this.isDanger = false,
    this.suffix,
  });

  final String title;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;
  final bool isDanger;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final borderRadius = isFirst && isLast
        ? BorderRadius.circular(24)
        : isFirst
        ? const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          )
        : isLast
        ? const BorderRadius.only(
            bottomLeft: Radius.circular(24),
            bottomRight: Radius.circular(24),
          )
        : BorderRadius.zero;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: Container(
          height: 70,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: borderRadius,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: ProtonStyles.body1Medium(
                    color: isDanger
                        ? context.colors.notificationError
                        : context.colors.textNorm,
                  ),
                ),
              ),
              if (isDanger)
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(12),
                  decoration: ShapeDecoration(
                    color: const Color(0xFF3D2A3D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                    size: 16,
                  ),
                )
              else if (suffix != null)
                suffix!
              else
                const SizedBox(width: 20),
            ],
          ),
        ),
      ),
    );
  }
}
