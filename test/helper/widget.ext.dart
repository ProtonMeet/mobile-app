import 'package:flutter/widgets.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:meet/provider/theme.provider.dart';
import 'package:provider/provider.dart';

@isTest
extension WidgetExtension on Widget {
  Widget withTheme(ThemeProvider mockThemeProvider) {
    final testwidget = ChangeNotifierProvider<ThemeProvider>.value(
      value: mockThemeProvider,
      child: this,
    );
    return testwidget;
  }

  // Widget get withBgSecondary {
  //   return ColoredBox(
  //     color: context.colors.backgroundSecondary,
  //     child: this,
  //   );
  // }

  // Widget get withBgNormal {
  //   return ColoredBox(
  //     color: context.colors.backgroundNorm,
  //     child: this,
  //   );
  // }
}
