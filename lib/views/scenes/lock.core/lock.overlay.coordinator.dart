import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/core/view.dart';
import 'package:meet/views/scenes/core/viewmodel.dart';
import 'package:meet/views/scenes/lock.core/lock.overlay.view.dart';
import 'package:meet/views/scenes/lock.core/lock.overlay.viewmodel.dart';
import 'package:meet/views/scenes/lock.overlay/lock.overlay.coordinator.dart';

class LockCoordinator extends Coordinator {
  late ViewBase widget;

  @override
  void end() {}

  Future<void> showLockOverlay({required bool askUnlockWhenOnload}) async {
    final view = LockOverlayCoordinator(
      askUnlockWhenOnload: askUnlockWhenOnload,
    ).start();

    final context = Coordinator.rootNavigatorKey.currentContext;
    if (context == null) {
      return;
    }
    await showInBottomSheet(
      view,
      backgroundColor: context.colors.backgroundSecondary,
      enableDrag: false,
      isDismissible: false,
      fullScreen: true,
      canPop: false,
    );
  }

  @override
  ViewBase<ViewModel> start() {
    final appState = serviceManager.get<AppStateManager>();
    final viewModel = LockCoreViewModelImpl(this, appState);
    widget = LockCoreView(viewModel);
    return widget;
  }
}
