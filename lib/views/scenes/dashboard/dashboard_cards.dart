import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/views/components/stacked_card_carousel.dart';
import 'package:meet/views/components/stacked_info_card.dart';

import 'dashboard_state.dart';

/// Small dashboard widget using `StackedCardCarousel(items: ...)`.
///
/// - Shows stacked info cards
/// - Only the active card has a close action
class DashboarCards extends StatelessWidget {
  const DashboarCards({
    required this.cards,
    required this.onDismiss,
    super.key,
  });

  final List<DashboardCard> cards;
  final void Function(String id) onDismiss;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return AnimatedSize(
        duration: defaultAnimationDurationLong,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: const SizedBox.shrink(),
      );
    }

    final visibleCount = cards.length >= 3 ? 3 : cards.length;
    final height = 170.0 + (20.0 * (visibleCount - 1)) + 16.0;

    final items = cards.map((card) {
      return StackedCardCarouselItem(
        id: card.id,
        builder: (context, onClose, {required bool isActive}) {
          return StackedInfoCard(
            key: ValueKey('info_${card.id}'),
            backgroundColor: card.backgroundColor,
            title: card.title,
            subtitle: card.subtitle,
            icon: _DashboardInfoCardIcon(iconKey: card.iconKey),
            onClose: isActive ? onClose : null,
            isActive: isActive,
          );
        },
      );
    }).toList();

    return AnimatedSize(
      duration: defaultAnimationDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Container(
        padding: const EdgeInsets.only(left: 24, right: 24),
        height: height,
        width: double.infinity,
        child: StackedCardCarousel(
          key: ValueKey('carousel_${cards.map((e) => e.id).join("_")}'),
          items: items,
          initialOffset: 4,
          spaceBetweenItems: 4,
          scrollEnabled: false,
          onItemDismissed: onDismiss,
        ),
      ),
    );
  }
}

class _DashboardInfoCardIcon extends StatelessWidget {
  const _DashboardInfoCardIcon({required this.iconKey});
  final String iconKey;

  @override
  Widget build(BuildContext context) {
    // Mock mapping; can later be driven by backend payload.
    switch (iconKey) {
      case 'badge_lock':
        return const _BadgeIcon(base: Color(0xFF6D4AFF), icon: Icons.lock);
      case 'badge_shield':
      default:
        return const _BadgeIcon(base: Color(0xFF7A6BFF), icon: Icons.shield);
    }
  }
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({required this.base, required this.icon});
  final Color base;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: base.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
          ),
        ),
        Center(child: Icon(icon, size: 34, color: base)),
        Positioned(
          right: 2,
          bottom: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: base,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.check, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
