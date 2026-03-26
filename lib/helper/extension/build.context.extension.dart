import 'dart:math';

import 'package:flutter/material.dart';
import 'package:meet/constants/proton.color.dart';
import 'package:meet/constants/proton.image.dart';
import 'package:meet/constants/proton.styles.dart';
import 'package:meet/helper/local_toast.dart';
import 'package:meet/l10n/generated/locale.dart';
import 'package:meet/provider/theme.provider.dart';
import 'package:meet/views/components/local.toast.view.dart';
import 'package:provider/provider.dart';

extension BuildContextExtension on BuildContext {
  /// Returns the maximum of the current screen width or a given [value].
  double maxWidth(double value) {
    return max(MediaQuery.of(this).size.width, value);
  }

  /// Returns the current screen height multiplied by a given [value].
  double multHeight(double value) {
    return MediaQuery.of(this).size.height * value;
  }

  /// Gets the current screen width.
  double get width => MediaQuery.of(this).size.width;

  /// Gets the current screen height.
  double get height => MediaQuery.of(this).size.height;

  bool get isLandscape => width > height;

  /// Provides access to the localized strings from the app's localization delegate.
  S get local => S.of(this);

  bool get isTopMostRoute => ModalRoute.of(this)?.isCurrent ?? true;

  /// Show snackbar
  void showSnackbar(String message, {bool isError = false}) {
    final snackBar = SnackBar(
      backgroundColor: isError ? colors.notificationError : null,
      content: Center(
        child: Text(
          message,
          style: ProtonStyles.body2Regular(color: colors.textInverted),
        ),
      ),
    );
    ScaffoldMessenger.of(this).showSnackBar(snackBar);
  }

  /// quick access to show toast
  void showToast(String message) {
    LocalToast.showToast(this, message);
  }

  void showErrorToast(String message) {
    LocalToast.showToast(this, message, toastType: ToastType.error);
  }

  /// Theme provider
  ThemeProvider get themeProvider => Provider.of<ThemeProvider>(this);
  bool get isDarkMode => themeProvider.isDarkMode();

  /// extension for images / icons
  ProtonImages get images {
    return Theme.of(this).extension<ProtonImages>() ??
        // fallover to default
        (isDarkMode ? darkImageExtension : lightImageExtension);
  }

  /// extension for colors
  ProtonColors get colors {
    return Theme.of(this).extension<ProtonColors>() ??
        // fallover to default
        (isDarkMode ? darkColorsExtension : lightColorsExtension);
  }

  /// Returns a list of localized month names.
  List<String> get monthNames => [
    local.month_jan,
    local.month_feb,
    local.month_mar,
    local.month_apr,
    local.month_may,
    local.month_jun,
    local.month_jul,
    local.month_aug,
    local.month_sep,
    local.month_oct,
    local.month_nov,
    local.month_dec,
  ];

  /// Returns a list of localized weekday names (Monday through Sunday).
  List<String> get weekdayNames => [
    local.weekday_monday,
    local.weekday_tuesday,
    local.weekday_wednesday,
    local.weekday_thursday,
    local.weekday_friday,
    local.weekday_saturday,
    local.weekday_sunday,
  ];
}
