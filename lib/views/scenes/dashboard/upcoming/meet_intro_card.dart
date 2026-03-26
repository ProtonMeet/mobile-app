import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';

class MeetIntroCard extends StatelessWidget {
  const MeetIntroCard({
    required this.message,
    required this.onSchedule,
    required this.onStart,
    super.key,
    this.icon,
    this.backgroundColor,
    this.primaryColor,
    this.tonalColor,
    this.textColor,
    this.showButtons = false,
  });

  /// Top icon (e.g., Icons.videocam_rounded). If null, uses a default.
  final Widget? icon;

  /// Center message shown in the card.
  final String message;

  /// Buttons’ callbacks.
  final VoidCallback onSchedule;
  final VoidCallback onStart;

  /// Optional styling overrides.
  final Color? backgroundColor; // card bg
  final Color? primaryColor; // "Start" button
  final Color? tonalColor; // "Schedule" button background
  final Color? textColor; // headline text

  final bool showButtons;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? const Color(0xFF141826); // deep navy
    final primary = primaryColor ?? const Color(0xFF9B9DFD); // lavender
    final tonal = (tonalColor ?? Colors.white.withValues(alpha: 0.10));

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(child: icon ?? const SizedBox.shrink()),
          const SizedBox(height: 12),
          // Headline text
          Text(
            message,
            textAlign: TextAlign.center,
            style: ProtonStyles.body1Semibold(
              color: textColor ?? context.colors.textNorm,
            ),
          ),

          const SizedBox(height: 40),

          // Buttons row
          if (showButtons) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PillButton.tonal(
                  label: 'Schedule',
                  onPressed: onSchedule,
                  bg: tonal,
                  fg: Colors.white.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 8),
                _PillButton.filled(
                  label: 'Start',
                  onPressed: onStart,
                  bg: primary,
                  fg: Colors.black.withValues(alpha: 0.90),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton._({
    required this.label,
    required this.onPressed,
    required this.bg,
    required this.fg,
  });

  factory _PillButton.filled({
    required String label,
    required VoidCallback onPressed,
    required Color bg,
    required Color fg,
  }) => _PillButton._(label: label, onPressed: onPressed, bg: bg, fg: fg);

  factory _PillButton.tonal({
    required String label,
    required VoidCallback onPressed,
    required Color bg,
    required Color fg,
  }) => _PillButton._(label: label, onPressed: onPressed, bg: bg, fg: fg);

  final String label;
  final VoidCallback onPressed;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 140,
        maxWidth: 200,
        minHeight: 55,
      ),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(55),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(55),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Center(
              child: Text(label, style: ProtonStyles.body1Medium(color: fg)),
            ),
          ),
        ),
      ),
    );
  }
}
