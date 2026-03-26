import 'package:flutter/material.dart';
import 'package:meet/helper/extension/build.context.extension.dart';
import 'package:meet/views/components/bottom.sheets/base.dart';
import 'package:meet/views/scenes/core/coordinator.dart';

abstract class BaseBottomSheet extends StatelessWidget {
  const BaseBottomSheet({super.key});

  static void showSheet({required Widget child, Color? backgroundColor}) {
    final context = Coordinator.rootNavigatorKey.currentContext;
    if (context == null) {
      return;
    }
    HomeModalBottomSheet.show(
      context,
      backgroundColor: backgroundColor ?? context.colors.backgroundSecondary,
      child: child,
    );
  }

  void showPopup() {
    final context = Coordinator.rootNavigatorKey.currentContext;
    if (context == null) {
      return;
    }
    showDialog(
      context: context,
      builder: (context) => this,
      barrierDismissible: false,
    );
  }

  void show() {
    showSheet(child: this);
  }
}
