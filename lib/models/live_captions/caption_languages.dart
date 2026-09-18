import 'package:meet/constants/live_captions_constants.dart';

/// One entry in the caption language settings dropdown.
class CaptionLanguageOption {
  const CaptionLanguageOption({required this.code, required this.displayName});

  /// BCP-47-ish code sent to STT, or [LiveCaptionsConstants.defaultCaptionLanguage].
  final String code;

  /// Native-language label (matches web static list; localize in UI if needed).
  final String displayName;

  /// Whether this option maps to auto-detect (no LiveKit attribute written).
  bool get isAutoDetect => code == LiveCaptionsConstants.defaultCaptionLanguage;
}

/// Auto-detect plus 19 spoken languages (20 picker rows total).
const List<CaptionLanguageOption> supportedCaptionLanguages = [
  CaptionLanguageOption(code: 'multi', displayName: 'Auto-detect'),
  CaptionLanguageOption(code: 'ar', displayName: 'العربية'),
  CaptionLanguageOption(code: 'zh', displayName: '中文 (简体)'),
  CaptionLanguageOption(code: 'zh-TW', displayName: '中文 (繁體)'),
  CaptionLanguageOption(code: 'nl', displayName: 'Nederlands'),
  CaptionLanguageOption(code: 'en', displayName: 'English'),
  CaptionLanguageOption(code: 'fr', displayName: 'Français'),
  CaptionLanguageOption(code: 'de', displayName: 'Deutsch'),
  CaptionLanguageOption(code: 'hi', displayName: 'हिन्दी'),
  CaptionLanguageOption(code: 'id', displayName: 'Bahasa Indonesia'),
  CaptionLanguageOption(code: 'it', displayName: 'Italiano'),
  CaptionLanguageOption(code: 'ja', displayName: '日本語'),
  CaptionLanguageOption(code: 'ko', displayName: '한국어'),
  CaptionLanguageOption(code: 'pl', displayName: 'Polski'),
  CaptionLanguageOption(code: 'pt', displayName: 'Português'),
  CaptionLanguageOption(code: 'pt-BR', displayName: 'Português (Brasil)'),
  CaptionLanguageOption(code: 'ru', displayName: 'Русский'),
  CaptionLanguageOption(code: 'es', displayName: 'Español'),
  CaptionLanguageOption(code: 'tr', displayName: 'Türkçe'),
  CaptionLanguageOption(code: 'uk', displayName: 'Українська'),
  CaptionLanguageOption(code: 'vi', displayName: 'Tiếng Việt'),
];

/// Returns true when [code] is a supported picker / STT language code.
bool isSupportedCaptionLanguageCode(String code) =>
    supportedCaptionLanguages.any((option) => option.code == code);

/// Lookup by code; null when unknown.
CaptionLanguageOption? captionLanguageOptionForCode(String code) {
  for (final option in supportedCaptionLanguages) {
    if (option.code == code) {
      return option;
    }
  }
  return null;
}
