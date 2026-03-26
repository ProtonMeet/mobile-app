import 'package:flutter/material.dart';
import 'package:meet/views/scenes/app/app.splash.view.dart';
import 'package:meet/views/scenes/core/view.dart';
import 'package:meet/views/scenes/lock.core/lock.overlay.viewmodel.dart';

class LockCoreView extends ViewBase<LockCoreViewModel> {
  const LockCoreView(LockCoreViewModel viewModel)
    : super(viewModel, const Key("LockCoreView"));

  @override
  Widget build(BuildContext context) {
    return viewModel.initialized
        ? const SizedBox()
        : SplashView().build(context);
  }
}
