import 'package:flutter/widgets.dart';
import 'package:meet/constants/env.dart';
import 'package:meet/views/scenes/app/app.router.dart';
import 'package:meet/views/scenes/app/app.view.dart';
import 'package:meet/views/scenes/app/app.viewmodel.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/core/view.dart';

class AppCoordinator extends Coordinator {
  late ViewBase widget;

  AppCoordinator();

  @override
  void end() {}

  @override
  Widget start() {
    final viewModel = AppViewModelImpl(this, serviceManager);
    widget = AppView(viewModel);
    return widget;
  }

  void showDashboardPage(ApiEnv env) {
    final ctx = Coordinator.rootNavigatorKey.currentContext;
    if (ctx == null) return;

    final args = <String, Object>{
      'displayName': '',
      'isVideoEnabled': false,
      'isAudioEnabled': false,
      'isE2EEEnabled': true,
    };

    Navigator.pushNamedAndRemoveUntil(
      ctx,
      RouteName.dashboard.path,
      arguments: args,
      (route) => false,
    );
  }
}
