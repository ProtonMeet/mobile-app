import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/helper/extension/platform.extension.dart';
import 'package:proton_video_effects/proton_video_effects.dart';

/// Every mobile/desktop engine now runs the same erode → solidify → feather → gamma stages, so the
/// dials mean the same thing everywhere. Apple applies them at frame resolution via Core Image;
/// Android applies them in mask space with the fractions converted to mask pixels.
bool get maskEdgeTuningSupported => iOS || macOS || android;

/// Inline segmentation is an Apple-only experiment: the Android engine always dispatches
/// inference asynchronously and drops `synchronousSegmentation` on the floor, so the switch would
/// be a control that does nothing.
bool get synchronousSegmentationSupported => iOS || macOS;

/// The mask overlay is only implemented in the Android engine, where the mask geometry is the
/// thing under investigation. Apple composites through Core Image and has no equivalent path.
bool get maskDebugOverlaySupported => android;

/// Labelled slider with a live value readout, shared by the background debug screens.
class BlurParamSlider extends StatelessWidget {
  const BlurParamSlider({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.formatValue,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double) formatValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodySmall = theme.textTheme.bodySmall?.copyWith(
      color: context.colors.textWeak,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(description, style: bodySmall),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                label: formatValue(value),
                onChanged: onChanged,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                formatValue(value),
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Switch for the inline-segmentation experiment.
///
/// Renders nothing where [synchronousSegmentationSupported] is false.
class SynchronousSegmentationSwitch extends StatelessWidget {
  const SynchronousSegmentationSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!synchronousSegmentationSupported) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text(
        'Synchronous segmentation',
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Text(
        'Segments each frame inline so the mask matches it exactly, removing the lag that lets '
        'a waving arm tear the background. Blocks video capture while inferring, so watch '
        'frameFps in the perf log for dropped frames.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: context.colors.textWeak,
        ),
      ),
    );
  }
}

/// Switch for the red mask overlay.
///
/// Renders nothing where [maskDebugOverlaySupported] is false.
class MaskDebugOverlaySwitch extends StatelessWidget {
  const MaskDebugOverlaySwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!maskDebugOverlaySupported) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      title: Text('Show mask overlay', style: theme.textTheme.titleSmall),
      subtitle: Text(
        'Drops the background effect and tints the mask red over the sharp frame, so its '
        'position, orientation and feather are visible directly. A correct mask is a red '
        'silhouette sitting exactly on you.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: context.colors.textWeak,
        ),
      ),
    );
  }
}

/// Every mask shaping dial, in the order the pipeline applies them.
///
/// Renders nothing where [maskEdgeTuningSupported] is false.
class MaskEdgeSliders extends StatelessWidget {
  const MaskEdgeSliders({
    required this.tuning,
    required this.onChanged,
    super.key,
  });

  final MaskEdgeTuning tuning;
  final ValueChanged<MaskEdgeTuning> onChanged;

  static String _fraction(double value) => value.toStringAsFixed(3);

  static String _plain(double value) => value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    if (!maskEdgeTuningSupported) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BlurParamSlider(
          title: 'Mask edge erosion',
          description:
              'Pulls the outline inward, as a fraction of frame height. Raise this when waving '
              'an arm tears a hole in the background; it costs thin detail like stray hair.',
          value: tuning.erodeHeightFraction,
          min: 0,
          max: MaskEdgeTuning.maxEdgeFraction,
          divisions: 50,
          formatValue: _fraction,
          onChanged: (v) => onChanged(tuning.copyWith(erodeHeightFraction: v)),
        ),
        const SizedBox(height: 16),
        BlurParamSlider(
          title: 'Mask edge softness',
          description:
              'Width of the fade at the outline, as a fraction of frame height. '
              'Higher = softer. Does not move the edge.',
          value: tuning.featherHeightFraction,
          min: 0,
          max: MaskEdgeTuning.maxEdgeFraction,
          divisions: 50,
          formatValue: _fraction,
          onChanged: (v) =>
              onChanged(tuning.copyWith(featherHeightFraction: v)),
        ),
        const SizedBox(height: 16),
        BlurParamSlider(
          title: 'Subject opacity (solidify slope)',
          description:
              'How hard low confidence is pushed to fully opaque. Raise this if you look '
              'see-through; 1.0 turns the step off.',
          value: tuning.solidifySlope,
          min: MaskEdgeTuning.minSolidifySlope,
          max: MaskEdgeTuning.maxSolidifySlope,
          divisions: 30,
          formatValue: _plain,
          onChanged: (v) => onChanged(tuning.copyWith(solidifySlope: v)),
        ),
        const SizedBox(height: 16),
        BlurParamSlider(
          title: 'Solidify midpoint',
          description:
              'Confidence treated as the outline. Lower grows the subject (fixes chunks of you '
              'going missing), higher shrinks it.',
          value: tuning.solidifyMidpoint,
          min: MaskEdgeTuning.minSolidifyMidpoint,
          max: MaskEdgeTuning.maxSolidifyMidpoint,
          divisions: 24,
          formatValue: _plain,
          onChanged: (v) => onChanged(tuning.copyWith(solidifyMidpoint: v)),
        ),
        const SizedBox(height: 16),
        BlurParamSlider(
          title: 'Foreground gamma',
          description:
              'Above 1.0 pushes uncertain areas to background so objects leak in less, but '
              'steepens the edge. Below 1.0 grows the subject. 1.0 is neutral.',
          value: tuning.foregroundGamma,
          min: MaskEdgeTuning.minForegroundGamma,
          max: MaskEdgeTuning.maxForegroundGamma,
          divisions: 25,
          formatValue: _plain,
          onChanged: (v) => onChanged(tuning.copyWith(foregroundGamma: v)),
        ),
      ],
    );
  }
}
