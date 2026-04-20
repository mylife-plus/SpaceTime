import 'package:get/get.dart';

class SupportedLanguage {
  SupportedLanguage({
    required this.code,
    required this.nativeNameKey,
    required this.emoji,
  });

  final String code;
  /// L10n key; use [nativeName] so `.tr` runs after translations load.
  final String nativeNameKey;
  final String emoji;

  String get nativeName => nativeNameKey.tr;
}

final List<SupportedLanguage> kSupportedLanguages = [
  SupportedLanguage(code: 'en', nativeNameKey: 'supported_language_english', emoji: '🇺🇸'),
  SupportedLanguage(code: 'es', nativeNameKey: 'supported_language_espa_ol', emoji: '🇪🇸'),
  SupportedLanguage(code: 'fr', nativeNameKey: 'supported_language_fran_ais', emoji: '🇫🇷'),
  SupportedLanguage(code: 'de', nativeNameKey: 'supported_language_deutsch', emoji: '🇩🇪'),
];

SupportedLanguage supportedLanguageForCode(String code) {
  for (final lang in kSupportedLanguages) {
    if (lang.code == code) return lang;
  }
  return kSupportedLanguages.first;
}

String displayNameForLanguageCode(String code) {
  return supportedLanguageForCode(code).nativeName;
}

/// Emoji + localized native name for settings subtitles.
String displayLabelForLanguageCode(String code) {
  final lang = supportedLanguageForCode(code);
  return '${lang.emoji} ${lang.nativeName}';
}
