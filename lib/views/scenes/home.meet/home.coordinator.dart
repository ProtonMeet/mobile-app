import 'package:meet/views/scenes/core/coordinator.dart';
import 'package:meet/views/scenes/core/view.dart';
import 'package:meet/views/scenes/core/viewmodel.dart';
import 'package:meet/views/scenes/home.meet/home.view.dart';

import 'package:meet/views/scenes/home.meet/home.viewmodel.dart';

class MeetDashboardCoordinator extends Coordinator {
  late ViewBase widget;

  MeetDashboardCoordinator();

  @override
  void end() {}

  @override
  ViewBase<ViewModel> start() {
    final viewModel = HomeViewModelImpl(this);
    widget = HomeView(viewModel);
    return widget;
  }
}
