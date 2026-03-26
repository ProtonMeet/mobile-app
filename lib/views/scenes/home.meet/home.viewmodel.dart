import 'package:meet/views/scenes/core/view.navigatior.identifiers.dart';
import 'package:meet/views/scenes/core/viewmodel.dart';

abstract class HomeViewModel extends ViewModel {
  HomeViewModel(super.coordinator);
}

class HomeViewModelImpl extends HomeViewModel {
  HomeViewModelImpl(super.coordinator);

  @override
  Future<void> loadData() async {
    sinkAddSafe();
  }

  @override
  Future<void> move(NavID to) async {}
}
