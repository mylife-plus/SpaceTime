import 'package:get/get.dart';
import 'package:spacetime/app/constants/place_categories_data.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/utils/search_utils.dart';

/// Slugs must match [assets/l10n/place_category_bundle.json] (see tool that generated it).
String placeCategorySlug(String input) {
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
}

String? _l10nKeyForMain(String englishMainName) {
  if (!kPlaceCategoriesSeed.containsKey(englishMainName)) return null;
  return 'place_cat_m_${placeCategorySlug(englishMainName)}';
}

String? _l10nKeyForSub(String englishMainName, String englishSubName) {
  if (!kPlaceCategoriesSeed.containsKey(englishMainName)) return null;
  return 'place_cat_s_${placeCategorySlug(englishMainName)}__${placeCategorySlug(englishSubName)}';
}

/// Resolves predefined subcategory parent using [name] + [emoji] (unique for Pharmacy, etc.).
String? predefinedParentMainNameForSub(String subName, String emoji) {
  String? found;
  for (final e in kPlaceCategoriesSeed.entries) {
    for (final item in e.value) {
      if (item['name'] == subName && item['emoji'] == emoji) {
        if (found != null && found != e.key) {
          return found;
        }
        found = e.key;
      }
    }
  }
  return found;
}

/// Prefer settings language over [Get.locale], which can lag after in-app language changes.
String _languageCodeForPlaceCategoryStrings() {
  if (Get.isRegistered<UiController>()) {
    try {
      return effectiveLanguageCode(
        Get.find<UiController>().selectedLanguage.value,
      );
    } catch (_) {}
  }
  return effectiveLanguageCode(null);
}

String _trForLangKey(String key, String fallback, String languageCode) {
  final t = trForLang(key, languageCode);
  if (t == key || t.isEmpty) return fallback;
  return t;
}

String _trOrOriginal(String key, String fallback) {
  return _trForLangKey(key, fallback, _languageCodeForPlaceCategoryStrings());
}

/// Same as [localizedPlaceCategoryName] for a fixed [languageCode] (e.g. search indexing).
String localizedPlaceCategoryNameForLang({
  required String name,
  required String emoji,
  required bool isCustom,
  required bool isMainCategory,
  required String languageCode,
}) {
  if (isCustom) return name;
  if (isMainCategory) {
    final k = _l10nKeyForMain(name);
    if (k == null) return name;
    return _trForLangKey(k, name, languageCode);
  }
  final parent = predefinedParentMainNameForSub(name, emoji);
  if (parent == null) return name;
  final k = _l10nKeyForSub(parent, name);
  if (k == null) return name;
  return _trForLangKey(k, name, languageCode);
}

/// Localized display name for a place category row (DB keeps English [name]).
String localizedPlaceCategoryName({
  required String name,
  required String emoji,
  required bool isCustom,
  required bool isMainCategory,
}) {
  return localizedPlaceCategoryNameForLang(
    name: name,
    emoji: emoji,
    isCustom: isCustom,
    isMainCategory: isMainCategory,
    languageCode: _languageCodeForPlaceCategoryStrings(),
  );
}

/// Maps edit-dialog text back to the DB name: custom uses [trimmedControllerText];
/// predefined keeps canonical English if the user left the localized or English label.
String resolvedPlaceCategoryDbNameForEditSave({
  required String trimmedControllerText,
  required String canonicalDbName,
  required String emoji,
  required bool isCustom,
  required bool isMainCategory,
}) {
  if (isCustom) return trimmedControllerText;
  final localized = localizedPlaceCategoryName(
    name: canonicalDbName,
    emoji: emoji,
    isCustom: false,
    isMainCategory: isMainCategory,
  );
  if (trimmedControllerText == canonicalDbName ||
      trimmedControllerText == localized) {
    return canonicalDbName;
  }
  return trimmedControllerText;
}

/// Normalized text including [storedCategory] plus all known translations (en/es/fr/de)
/// so keyword search matches regardless of UI language used when saving the memory.
String placeCategorySearchHaystack(String? storedCategory) {
  if (storedCategory == null || storedCategory.trim().isEmpty) {
    return '';
  }
  final raw = storedCategory.trim();
  final spaceIdx = raw.indexOf(' ');
  if (spaceIdx <= 0 || spaceIdx >= raw.length - 1) {
    return SearchUtils.normalizeText(raw);
  }
  final emoji = raw.substring(0, spaceIdx);
  final name = raw.substring(spaceIdx + 1);
  if (name.isEmpty) {
    return SearchUtils.normalizeText(raw);
  }

  final isPredefinedSub = predefinedParentMainNameForSub(name, emoji) != null;
  final isPredefinedMain =
      !isPredefinedSub && kPlaceCategoriesSeed.containsKey(name);

  if (!isPredefinedSub && !isPredefinedMain) {
    return SearchUtils.normalizeText('$raw $name');
  }

  final isMain = isPredefinedMain;
  final variants = <String>{raw, name};
  for (final code in L10nLoader.maps.keys) {
    final localized = localizedPlaceCategoryNameForLang(
      name: name,
      emoji: emoji,
      isCustom: false,
      isMainCategory: isMain,
      languageCode: code,
    );
    variants.add(localized);
    variants.add('$emoji $localized');
  }
  return SearchUtils.normalizeText(variants.join(' '));
}

/// Localized display for stored canonical `emoji englishName` (memories / filters); custom unchanged.
String localizedPlaceCategoryStoredLabel(String stored) {
  if (stored.isEmpty) return stored;
  final t = stored.trim();
  final spaceIdx = t.indexOf(' ');
  if (spaceIdx <= 0 || spaceIdx >= t.length - 1) return t;
  final emoji = t.substring(0, spaceIdx);
  final name = t.substring(spaceIdx + 1);
  final asSub = localizedPlaceCategoryName(
    name: name,
    emoji: emoji,
    isCustom: false,
    isMainCategory: false,
  );
  if (asSub != name) return '$emoji $asSub';
  final asMain = localizedPlaceCategoryName(
    name: name,
    emoji: emoji,
    isCustom: false,
    isMainCategory: true,
  );
  if (asMain != name) return '$emoji $asMain';
  return stored;
}
