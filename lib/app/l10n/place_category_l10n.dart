import 'package:get/get.dart';
import 'package:spacetime/app/constants/place_categories_data.dart';

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

String _trOrOriginal(String key, String fallback) {
  final t = key.tr;
  if (t == key || t.isEmpty) return fallback;
  return t;
}

/// Localized display name for a place category row (DB keeps English [name]).
String localizedPlaceCategoryName({
  required String name,
  required String emoji,
  required bool isCustom,
  required bool isMainCategory,
}) {
  if (isCustom) return name;
  if (isMainCategory) {
    final k = _l10nKeyForMain(name);
    if (k == null) return name;
    return _trOrOriginal(k, name);
  }
  final parent = predefinedParentMainNameForSub(name, emoji);
  if (parent == null) return name;
  final k = _l10nKeyForSub(parent, name);
  if (k == null) return name;
  return _trOrOriginal(k, name);
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
