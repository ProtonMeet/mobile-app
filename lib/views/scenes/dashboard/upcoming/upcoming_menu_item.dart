import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';

class UpcomingMenuItem extends StatelessWidget {
  const UpcomingMenuItem({
    required this.icon,
    required this.label,
    required this.labelColor,
    required this.onTap,
    super.key,
  });

  final Widget icon;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 2),
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 16),
            Text(label, style: ProtonStyles.body1Semibold(color: labelColor)),
          ],
        ),
      ),
    );
  }
}
