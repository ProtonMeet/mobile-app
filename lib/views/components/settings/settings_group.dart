import 'package:flutter/material.dart';

/// Stacks settings rows into one card: rounded outer corners and hairline
/// gaps between rows.
///
/// Callers pass rows in order and never deal with per-row corner radii, which
/// is what used to drift between the app and in-call settings sheets.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, super.key});

  static const double cornerRadius = 24;

  /// Row fill. The app is dark-only, so this is a fixed white overlay rather
  /// than a theme token.
  static final Color surfaceColor = Colors.white.withValues(alpha: 0.04);

  static const double _separator = 1;
  static const EdgeInsets _margin = EdgeInsets.symmetric(horizontal: 16);

  final List<Widget> children;

  static BorderRadius _radiusFor(int index, int length) {
    const radius = Radius.circular(cornerRadius);
    final isFirst = index == 0;
    final isLast = index == length - 1;
    return BorderRadius.only(
      topLeft: isFirst ? radius : Radius.zero,
      topRight: isFirst ? radius : Radius.zero,
      bottomLeft: isLast ? radius : Radius.zero,
      bottomRight: isLast ? radius : Radius.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: _margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: _separator),
            Material(
              color: surfaceColor,
              borderRadius: _radiusFor(i, children.length),
              clipBehavior: Clip.antiAlias,
              child: children[i],
            ),
          ],
        ],
      ),
    );
  }
}
