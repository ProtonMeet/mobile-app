import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/global_notification.dart';
import 'package:meet/views/components/global.notification.view.dart';

/// Host widget that renders the global notification above the entire app,
/// including the status bar area.
class GlobalNotificationHost extends StatelessWidget {
  const GlobalNotificationHost({required this.child, super.key});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlobalNotificationController.instance,
      builder: (context, _) {
        final data = GlobalNotificationController.instance.current;

        return Stack(
          fit: StackFit.expand,
          children: [
            ?child,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedSwitcher(
                duration: defaultAnimationDuration,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slideAnimation = Tween<Offset>(
                    begin: const Offset(0, -1),
                    end: Offset.zero,
                  ).animate(animation);

                  return SlideTransition(
                    position: slideAnimation,
                    child: child,
                  );
                },
                child: data == null
                    ? const SizedBox.shrink(key: ValueKey('hidden'))
                    : GlobalNotificationView(
                        key: ValueKey(data),
                        data: data,
                        onDismiss:
                            GlobalNotificationController.instance.dismiss,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
