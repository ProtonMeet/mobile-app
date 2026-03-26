import 'package:flutter/material.dart';
import 'package:meet/helper/logger.dart';

class ThemeProvider extends ChangeNotifier {
  final String key = 'theme'; // preference key
  // maping 3 theme types
  Map themeModeList = <String, ThemeMode>{
    'dark': ThemeMode.dark, // dark
    'light': ThemeMode.light, // light
    'system': ThemeMode.system, // follow system
  };

  // SharedPreferences? _preferences;
  String _themeMode = "dark";

  // return current mode
  String get themeMode => _themeMode;

  // constructure
  ThemeProvider();

  ThemeMode getThemeMode(String mode) {
    return themeModeList[mode];
  }

  // init SharedPreferences
  Future<void> _initialPreferences() async {
    // _preferences ??= await SharedPreferences.getInstance();
  }

  //  save
  Future<void> _savePreferences() async {
    await _initialPreferences();
    // _preferences?.setString(key, _themeMode);
  }

  // read
  Future<void> loadFromPreferences() async {
    await _initialPreferences();
    _themeMode = 'system'; // _preferences?.getString(key) ?? 'system';
    notifyListeners(); // notify
  }

  void toggleChangeTheme(String val) {
    _themeMode = val;
    logger.d('current theme mode: $_themeMode');
    _savePreferences();
    notifyListeners(); // notify
  }

  bool isDarkMode() {
    return true;
    // final ThemeMode theme = getThemeMode(_themeMode);
    // if (theme == ThemeMode.system) {
    //   final brightness =
    //       SchedulerBinding.instance.platformDispatcher.platformBrightness;
    //   return brightness == Brightness.dark;
    // }
    // return theme == ThemeMode.dark;
  }
}
