import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/helper/global_notification.dart';
import 'package:meet/views/components/global.notification.view.dart';

/// Host widget that renders the global notification above the entire app,
/// including the status bar area, and pushes [child] down instead of overlaying it.
class GlobalNotificationHost extends StatelessWidget {
  const GlobalNotificationHost({required this.child, super.key});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GlobalNotificationController.instance,
      builder: (context, _) {
        final data = GlobalNotificationController.instance.current;
        final appChild = child ?? const SizedBox.shrink();

        // The banner already occupies the status-bar inset; avoid double top
        // safe-area padding in routes such as the in-room top bar.
        final Widget expandedChild;
        if (data == null) {
          expandedChild = appChild;
        } else {
          final mediaQuery = MediaQuery.of(context);
          expandedChild = MediaQuery(
            data: mediaQuery.copyWith(
              padding: mediaQuery.padding.copyWith(top: 0),
              viewPadding: mediaQuery.viewPadding.copyWith(top: 0),
            ),
            child: appChild,
          );
        }

        return Column(
          children: [
            AnimatedSwitcher(
              duration: defaultAnimationDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final slideAnimation = Tween<Offset>(
                  begin: const Offset(0, -1),
                  end: Offset.zero,
                ).animate(animation);

                return ClipRect(
                  child: SlideTransition(
                    position: slideAnimation,
                    child: child,
                  ),
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
            Expanded(child: expandedChild),
          ],
        );
      },
    );
  }
}
