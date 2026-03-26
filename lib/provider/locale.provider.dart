import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/l10n/generated/locale.dart';
// import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const String systemDefault = 'en';
  final String key = 'locale'; // preference key

  // SharedPreferences? _preferences;

  String _language = systemDefault; // current language

  String get language => _language;

  Locale? get locale {
    if (_language != '') {
      if (_language == 'zh-TW') {
        return Locale("zh", "TW");
      }
      if (_language == 'zh-CN') {
        return Locale("zh", "CN");
      }
      if (_language == 'es-419') {
        return Locale("es", "419");
      }

      /// check and set system default lang
      if (_language == systemDefault) {
        final systemLocale = PlatformDispatcher.instance.locale;
        final local = S.supportedLocales
            .where(
              (e) =>
                  e.countryCode == systemLocale.countryCode &&
                  e.languageCode == systemLocale.languageCode,
            )
            .firstOrNull;
        if (local != null) {
          return local;
        }
      }
      return Locale(_language);
    }
    return null;
  }

  /// return the language native words by given bcp47 code
  static String localeName(String bcp47, context) {
    return 'English'; // Always return English
  }

  LocaleProvider() {
    _loadFromPreferences();
  }

  // init SharedPreferences
  Future<void> _initialPreferences() async {
    // _preferences ??= await SharedPreferences.getInstance();
  }

  // save
  Future<void> _savePreferences() async {
    await _initialPreferences();
    // _preferences?.setString(key, _language);
  }

  // read
  Future<void> _loadFromPreferences() async {
    await _initialPreferences();
    _language = systemDefault; // Always use English
    notifyListeners();
  }

  void toggleChangeLocale(String language) {
    _language = systemDefault; // Always use English
    logger.d('current locale: $language');
    _savePreferences();
    notifyListeners();
  }
}
