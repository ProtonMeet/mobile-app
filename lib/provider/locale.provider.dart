import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:meet/helper/logger.dart';
import 'package:meet/l10n/generated/locale.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleProvider extends ChangeNotifier {
  static const String systemDefault = 'system_default';
  final String key = 'locale';

  SharedPreferences? _preferences;

  String _language = systemDefault;

  String get language => _language;

  Locale? get locale {
    if (_language == '') {
      return null;
    }
    if (_language == 'zh-TW') {
      return const Locale('zh', 'TW');
    }
    if (_language == 'zh-CN') {
      return const Locale('zh', 'CN');
    }
    if (_language == 'es-419') {
      return const Locale('es', '419');
    }

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
      return null;
    }

    return Locale(_language);
  }

  /// Native language name (or system default label) for a BCP 47 tag.
  static String localeName(String bcp47, BuildContext context) {
    switch (bcp47) {
      case 'be':
        return 'Беларуская';
      case 'ca':
        return 'Català';
      case 'cs':
        return 'Čeština';
      case 'de':
        return 'Deutsch';
      case 'el':
        return 'Ελληνικά';
      case 'en':
        return 'English';
      case 'es':
        return 'Español';
      case 'es-419':
        return 'Español (Latinoamérica)';
      case 'fr':
        return 'Français';
      case 'hu':
        return 'Magyar';
      case 'id':
        return 'Bahasa Indonesia';
      case 'it':
        return 'Italiano';
      case 'nl':
        return 'Nederlands';
      case 'no':
        return 'Norsk';
      case 'pl':
        return 'Polski';
      case 'pt':
        return 'Português';
      case 'ro':
        return 'Română';
      case 'ru':
        return 'Русский';
      case 'sk':
        return 'Slovenčina';
      case 'sv':
        return 'Svenska';
      case 'tr':
        return 'Türkçe';
      case 'zh':
        return '简体中文';
      case 'zh-CN':
        return '简体中文';
      case 'zh-TW':
        return '繁體中文';
      default:
        return S.of(context).system_default_mode;
    }
  }

  LocaleProvider() {
    _loadFromPreferences();
  }

  Future<void> _initialPreferences() async {
    _preferences ??= await SharedPreferences.getInstance();
  }

  Future<void> _savePreferences() async {
    await _initialPreferences();
    await _preferences?.setString(key, _language);
  }

  Future<void> _loadFromPreferences() async {
    await _initialPreferences();
    _language = _preferences?.getString(key) ?? systemDefault;
    notifyListeners();
  }

  void toggleChangeLocale(String language) {
    _language = language;
    logger.d('current locale: $language');
    _savePreferences();
    notifyListeners();
  }
}
