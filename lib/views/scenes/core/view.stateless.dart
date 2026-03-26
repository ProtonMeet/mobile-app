import 'package:flutter/widgets.dart';
import 'package:meet/views/scenes/core/viewmodel.stateless.dart';

abstract class StatelessViewBase<V extends StatelessViewModel>
    extends StatelessWidget {
  final V viewModel;

  const StatelessViewBase(this.viewModel, {super.key});
}
