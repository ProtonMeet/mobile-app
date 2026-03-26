import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

/// A reusable loading view component with a circular progress indicator and text
///
/// This component displays a centered loading indicator with optional title and description text.
/// It uses RepaintBoundary to optimize performance by isolating the indicator and text from
/// unnecessary rebuilds.
class LoadingView extends StatelessWidget {
  /// The main title text displayed above the description
  final String title;

  /// Optional description text displayed below the title
  final String? description;

  /// Background color of the loading view
  final Color? backgroundColor;

  /// Color of the circular progress indicator
  final Color? indicatorColor;

  /// Stroke width of the circular progress indicator
  final double indicatorStrokeWidth;

  /// Size of the circular progress indicator
  final double indicatorSize;

  /// Spacing between title and description
  final double titleDescriptionSpacing;

  /// Spacing between description and indicator
  final double descriptionIndicatorSpacing;

  /// Horizontal padding for the title text
  final EdgeInsets titlePadding;

  /// Maximum number of lines for the title text
  final int titleMaxLines;

  /// Text style for the title
  final TextStyle Function(BuildContext)? titleStyle;

  const LoadingView({
    required this.title,
    this.description,
    this.backgroundColor,
    this.indicatorColor,
    this.indicatorStrokeWidth = 5.0,
    this.indicatorSize = 70.0,
    this.titleDescriptionSpacing = 0.0,
    this.descriptionIndicatorSpacing = 40.0,
    this.titlePadding = const EdgeInsets.only(
      left: 40.0,
      right: 40.0,
      bottom: 20.0,
    ),
    this.titleMaxLines = 3,
    this.titleStyle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: backgroundColor ?? context.colors.interActionWeakMinor3,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Use RepaintBoundary to isolate text updates from animation
            RepaintBoundary(
              child: Container(
                padding: titlePadding,
                child: Text(
                  textAlign: TextAlign.center,
                  maxLines: titleMaxLines,
                  title,
                  style:
                      titleStyle?.call(context) ??
                      ProtonStyles.headingSmallSemiBold(
                        color: context.colors.textNorm,
                      ),
                ),
              ),
            ),
            if (description != null && description!.isNotEmpty) ...[
              if (titleDescriptionSpacing > 0)
                SizedBox(height: titleDescriptionSpacing),
              RepaintBoundary(
                child: Text(
                  description!,
                  style: ProtonStyles.body2Medium(
                    color: context.colors.textWeak,
                  ),
                ),
              ),
              SizedBox(height: descriptionIndicatorSpacing),
            ],
            // Use RepaintBoundary for loading indicator to avoid rebuilds
            RepaintBoundary(
              child: SizedBox(
                width: indicatorSize,
                height: indicatorSize,
                child: CircularProgressIndicator(
                  strokeWidth: indicatorStrokeWidth,
                  color: indicatorColor ?? context.colors.interActionNorm,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
