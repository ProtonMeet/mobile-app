import 'package:meet/managers/app.core.manager.dart';
import 'package:meet/managers/app.state.manager.dart';
import 'package:meet/managers/providers/data.provider.manager.dart';
import 'package:meet/rust/proton_meet/models/user.dart';
import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/core/view.dart';
import 'package:meet/views/scenes/core/viewmodel.dart';
import 'package:meet/views/scenes/signin/signin.view.dart';
import 'package:meet/views/scenes/signin/signin.viewmodel.dart';

class SigninCoordinator extends Coordinator {
  late ViewBase widget;
  final Function(ProtonUser) onLoginSuccess;

  SigninCoordinator({required this.onLoginSuccess});

  @override
  void end() {}

  @override
  ViewBase<ViewModel> start() {
    final appCoreManager = serviceManager.get<AppCoreManager>();
    final dataProviderManager = serviceManager.get<DataProviderManager>();
    final appStateManager = serviceManager.get<AppStateManager>();
    final viewModel = SigninViewModelImpl(
      this,
      dataProviderManager,
      appStateManager,
      serviceManager,
      appCoreManager,
    );
    widget = SigninView(viewModel, onLoginSuccess: onLoginSuccess);
    return widget;
  }
}
