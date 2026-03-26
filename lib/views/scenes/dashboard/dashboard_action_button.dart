import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/scenes/core/responsive.dart';

class DashboardActionButton extends StatelessWidget {
  const DashboardActionButton({
    required this.title,
    required this.onPressed,
    super.key,
    this.enabled = true,
    this.isLoading = false,
    this.details,
    this.icon,
    this.iconBackgroundColor,
    this.backgroundColor,
    this.splashColor,
    this.highlightColor,
    this.height,
    this.borderRadius = 40.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    this.iconSize = 24.0,
    this.chevron = const Icon(Icons.chevron_right),
  });

  final VoidCallback onPressed;
  final String title;
  final String? details;
  final bool isLoading;
  final bool enabled;

  /// Provide your own icon widget
  final Widget? icon;

  final Color? iconBackgroundColor;
  final Color? backgroundColor;
  final Color? splashColor;
  final Color? highlightColor;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final double iconSize;
  final Widget chevron;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Calculate responsive height: fixed 72px on mobile, scales up to 130px max on larger screens
    final calculatedHeight =
        height ??
        () {
          // Keep height fixed at 72px on mobile
          if (Responsive.isMobile(context)) {
            return 72.0;
          }
          // Scale height on desktop/tablet screens
          final screenHeight = context.height;
          // Scale from 72 (at 600px) to 130 (at 1200px+)
          final scaleFactor = ((screenHeight - 600) / 600).clamp(0.0, 1.0);
          return (72 + (130 - 72) * scaleFactor).roundToDouble();
        }();

    // Use provided colors or fallback to theme colors
    final bg = backgroundColor ?? colors.backgroundNorm;
    final iconBg = iconBackgroundColor ?? colors.interActionWeakMinor3;
    final onSurface = colors.textNorm;

    // darker muted background when disabled
    final effectiveBg = enabled ? bg : onSurface.withValues(alpha: 0.05);
    // subtle dim icon background
    final effectiveIconBg = enabled ? iconBg : onSurface.withValues(alpha: 0.1);
    // dim text when disabled
    final textColor = enabled ? onSurface : onSurface.withValues(alpha: 0.4);

    return Opacity(
      opacity: enabled ? 1.0 : 0.7,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled && !isLoading ? onPressed : null,
          borderRadius: BorderRadius.circular(borderRadius),
          splashColor: splashColor,
          highlightColor: highlightColor,
          child: Ink(
            height: calculatedHeight,
            decoration: BoxDecoration(
              color: effectiveBg,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: colors.appBorderNorm),
            ),
            padding: padding,
            child: Row(
              children: [
                // Left circular icon
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: effectiveIconBg,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: iconSize,
                    height: iconSize,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: IconTheme(
                        data: IconThemeData(
                          color: enabled
                              ? colors.protonBlue
                              : onSurface.withValues(alpha: 0.4),
                        ),
                        child: icon ?? const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Title | (optional) details
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ProtonStyles.body1Semibold(color: textColor),
                        ),
                      ),
                      if (details != null) ...[
                        const Spacer(),
                        Flexible(
                          child: Text(
                            details!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: ProtonStyles.body2Medium(
                              color: textColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                IconTheme(
                  data: IconThemeData(
                    color: enabled
                        ? onSurface.withValues(alpha: 0.5)
                        : onSurface.withValues(alpha: 0.3),
                  ),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconTheme(
                          data: IconThemeData(
                            color: enabled
                                ? onSurface.withValues(alpha: 0.5)
                                : onSurface.withValues(alpha: 0.3),
                          ),
                          child: chevron,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
