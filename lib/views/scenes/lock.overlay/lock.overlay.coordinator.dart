import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/local.auth.manager.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/core/view.dart';
import 'package:meet/views/scenes/core/viewmodel.dart';
import 'package:meet/views/scenes/lock.overlay/lock.overlay.view.dart';
import 'package:meet/views/scenes/lock.overlay/lock.overlay.viewmodel.dart';

class LockOverlayCoordinator extends Coordinator {
  late ViewBase widget;
  bool askUnlockWhenOnload;

  LockOverlayCoordinator({required this.askUnlockWhenOnload});

  @override
  void end() {}

  @override
  ViewBase<ViewModel> start() {
    final appState = serviceManager.get<AppStateManager>();
    final localAuth = serviceManager.get<LocalAuthManager>();

    final viewModel = LockOverlayViewModelImpl(
      this,
      appState,
      localAuth,
      askUnlockWhenOnload: askUnlockWhenOnload,
    );
    widget = LockOverlayView(viewModel);
    return widget;
  }
}
