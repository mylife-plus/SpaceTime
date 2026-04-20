import 'package:flutter/material.dart';

/// Locale used by [GetMaterialApp] and [Get.updateLocale] so Material pickers
/// match app language.
Locale appLocaleFromLanguageCode(String code) {
  return Locale(code);
}
