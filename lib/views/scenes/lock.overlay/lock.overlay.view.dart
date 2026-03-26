import 'package:flutter/material.dart';
import 'package:meet/constants/constants.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/button.v5.dart';
import 'package:meet/views/components/button.v6.dart';
import 'package:meet/views/scenes/core/view.dart';
import 'package:meet/views/scenes/lock.overlay/lock.overlay.viewmodel.dart';

class LockOverlayView extends ViewBase<LockOverlayViewModel> {
  const LockOverlayView(LockOverlayViewModel viewModel)
    : super(viewModel, const Key("LockOverlayView"));

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return child;
      },
      child: SizedBox.expand(
        child: ColoredBox(
          /// Key is necessary to identify the widget uniquely
          key: const ValueKey('locked'),
          color: context.colors.backgroundSecondary,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 264,
                  height: 54,
                  child: context.images.protonMeetBarLogo.image(
                    fit: BoxFit.fitHeight,
                  ),
                ),
                // Assets.images.icon.lock.applyThemeIfNeeded(context).image(
                //       fit: BoxFit.fitHeight,
                //       width: 240,
                //       height: 167,
                //     ),
                Text(
                  viewModel.error,
                  style: ProtonStyles.body2Medium(
                    color: context.colors.notificationError,
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: defaultPadding,
                  ),
                  child: Visibility(
                    visible:
                        viewModel.isLockTimerNeedUnlock && viewModel.needUnlock,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: ButtonV6(
                      text: context.local.unlock_app,
                      width: context.width,
                      height: 55,
                      backgroundColor: context.colors.protonBlue,
                      textStyle: ProtonStyles.body1Medium(
                        color: context.colors.white,
                      ),
                      onPressed: () async {
                        await viewModel.unlock();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: defaultPadding,
                  ),
                  child: Visibility(
                    visible:
                        viewModel.isLockTimerNeedUnlock && viewModel.needUnlock,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: ButtonV5(
                      text: context.local.logout,
                      width: context.width,
                      height: 55,
                      backgroundColor: context.colors.interActionWeakDisable,
                      borderColor: context.colors.interActionWeakDisable,
                      textStyle: ProtonStyles.body1Medium(
                        color: context.colors.textNorm,
                      ),
                      onPressed: () async {
                        await viewModel.logout();
                      },
                    ),
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
