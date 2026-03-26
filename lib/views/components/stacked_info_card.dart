import 'package:flutter/material.dart';
import 'package:meet/constants/proton.styles.dart';

class StackedInfoCard extends StatelessWidget {
  const StackedInfoCard({
    required this.backgroundColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    super.key,
    this.onClose,
    this.width,
    this.height = 180,
    this.radius = 32,
    this.padding = const EdgeInsets.only(
      left: 20,
      right: 20,
      top: 10,
      bottom: 10,
    ),
    this.isActive = false,
  });

  final Color backgroundColor;
  final Widget icon;
  final String title;
  final String subtitle;
  final VoidCallback? onClose;
  final double? width;
  final double height;
  final double radius;
  final EdgeInsets padding;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: width ?? double.infinity,
      height: height,
      child: _MainSheet(
        color: backgroundColor,
        radius: radius,
        child: Padding(
          padding: padding,
          child: Column(
            children: [
              // Close
              if (onClose != null) ...[
                Align(
                  alignment: Alignment.topRight,
                  child: _CloseButton(onTap: onClose!),
                ),
              ],
              Row(
                children: [
                  // Icon
                  SizedBox(width: 56, height: 56, child: icon),
                  const SizedBox(width: 16),

                  // Text
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          isActive ? title : '',
                          style: ProtonStyles.subheadline(
                            color: const Color(0xFF0B0B0B),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          subtitle,
                          style: textTheme.bodyLarge?.copyWith(
                            color: const Color(0xFF1A1A1A),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainSheet extends StatelessWidget {
  const _MainSheet({
    required this.color,
    required this.radius,
    required this.child,
  });

  final Color color;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: const SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: Icon(Icons.close, size: 20, color: Color(0xFF0B0B0B)),
        ),
      ),
    );
  }
}
