import '../constants/place_categories_data.dart';
import '../services/place_category_service.dart';
import '../models/place_category_model.dart';

/// Backwards-compatible alias for predefined category seed (English keys).
Map<String, List<Map<String, String>>> get placeCategoriesJson =>
    kPlaceCategoriesSeed;

// Note: This JSON data is now automatically loaded into the database on app launch.
// Use PlaceCategoryService to access and manage place categories instead of this static data.

/// Utility class for place category operations in UI components
class PlaceCategoriesUtils {
  static final PlaceCategoryService _service = PlaceCategoryService();

  /// Get all categories formatted for dropdown/picker widgets
  static Future<List<Map<String, dynamic>>> getCategoriesForDropdown({
    bool includeSubcategories = true,
  }) async {
    return await _service.getCategoriesForPicker(
      includeSubcategories: includeSubcategories,
    );
  }

  /// Search categories by name for autocomplete/search widgets
  static Future<List<PlaceCategory>> searchCategories(String query) async {
    if (query.isEmpty) return [];
    return await _service.searchCategories(query);
  }

  /// Get main categories only (for category selection)
  static Future<List<PlaceCategory>> getMainCategories() async {
    return await _service.getMainCategories();
  }

  /// Get subcategories for a specific parent category
  static Future<List<PlaceCategory>> getSubcategories(int parentId) async {
    return await _service.getSubcategories(parentId);
  }

  /// Add a new custom category
  static Future<PlaceCategory?> addCustomCategory({
    required String name,
    required String emoji,
    int? parentId,
  }) async {
    return await _service.addCustomCategory(
      name: name,
      emoji: emoji,
      parentId: parentId,
    );
  }

  /// Update an existing category
  static Future<bool> updateCategory({
    required int categoryId,
    String? name,
    String? emoji,
  }) async {
    return await _service.updateCategory(
      categoryId: categoryId,
      name: name,
      emoji: emoji,
    );
  }

  /// Delete a custom category
  /// Returns: true if deleted, false if failed, null if has memories (cannot delete)
  static Future<bool?> deleteCategory(int categoryId) async {
    return await _service.deleteCategory(categoryId);
  }

  /// Format category for display (emoji + name)
  static String formatCategoryDisplay(PlaceCategory category) {
    return '${category.emoji} ${category.name}';
  }

  /// Get category by name (case-insensitive search)
  static Future<PlaceCategory?> getCategoryByName(String name) async {
    final results = await searchCategories(name);
    try {
      return results.firstWhere(
        (category) => category.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (e) {
      // If exact match not found, return first result or null
      return results.isNotEmpty ? results.first : null;
    }
  }
}

final Map<String, String> countryFlags = {
  "afghanistan": "🇦🇫",
  "albania": "🇦🇱",
  "algeria": "🇩🇿",
  "andorra": "🇦🇩",
  "angola": "🇦🇴",
  "antigua and barbuda": "🇦🇬",
  "argentina": "🇦🇷",
  "armenia": "🇦🇲",
  "australia": "🇦🇺",
  "austria": "🇦🇹",
  "azerbaijan": "🇦🇿",
  "bahamas": "🇧🇸",
  "bahrain": "🇧🇭",
  "bangladesh": "🇧🇩",
  "barbados": "🇧🇧",
  "belarus": "🇧🇾",
  "belgium": "🇧🇪",
  "belize": "🇧🇿",
  "benin": "🇧🇯",
  "bhutan": "🇧🇹",
  "bolivia": "🇧🇴",
  "bosnia and herzegovina": "🇧🇦",
  "botswana": "🇧🇼",
  "brazil": "🇧🇷",
  "brunei": "🇧🇳",
  "bulgaria": "🇧🇬",
  "burkina faso": "🇧🇫",
  "burundi": "🇧🇮",
  "cabo verde": "🇨🇻",
  "cambodia": "🇰🇭",
  "cameroon": "🇨🇲",
  "canada": "🇨🇦",
  "central african republic": "🇨🇫",
  "chad": "🇹🇩",
  "chile": "🇨🇱",
  "china": "🇨🇳",
  "colombia": "🇨🇴",
  "comoros": "🇰🇲",
  "congo (democratic republic)": "🇨🇩",
  "congo (republic)": "🇨🇬",
  "costa rica": "🇨🇷",
  "croatia": "🇭🇷",
  "cuba": "🇨🇺",
  "cyprus": "🇨🇾",
  "czech republic": "🇨🇿",
  "czechia": "🇨🇿",
  "denmark": "🇩🇰",
  "djibouti": "🇩🇯",
  "dominica": "🇩🇲",
  "dominican republic": "🇩🇴",
  "ecuador": "🇪🇨",
  "egypt": "🇪🇬",
  "el salvador": "🇸🇻",
  "equatorial guinea": "🇬🇶",
  "eritrea": "🇪🇷",
  "estonia": "🇪🇪",
  "eswatini": "🇸🇿",
  "ethiopia": "🇪🇹",
  "fiji": "🇫🇯",
  "finland": "🇫🇮",
  "france": "🇫🇷",
  "gabon": "🇬🇦",
  "gambia": "🇬🇲",
  "georgia": "🇬🇪",
  "germany": "🇩🇪",
  "ghana": "🇬🇭",
  "greece": "🇬🇷",
  "grenada": "🇬🇩",
  "guatemala": "🇬🇹",
  "guinea": "🇬🇳",
  "guinea-bissau": "🇬🇼",
  "guyana": "🇬🇾",
  "haiti": "🇭🇹",
  "honduras": "🇭🇳",
  "hungary": "🇭🇺",
  "iceland": "🇮🇸",
  "india": "🇮🇳",
  "indonesia": "🇮🇩",
  "iran": "🇮🇷",
  "iraq": "🇮🇶",
  "ireland": "🇮🇪",
  "israel": "🇮🇱",
  "italy": "🇮🇹",
  "jamaica": "🇯🇲",
  "japan": "🇯🇵",
  "jordan": "🇯🇴",
  "kazakhstan": "🇰🇿",
  "kenya": "🇰🇪",
  "kiribati": "🇰🇮",
  "kuwait": "🇰🇼",
  "kyrgyzstan": "🇰🇬",
  "laos": "🇱🇦",
  "latvia": "🇱🇻",
  "lebanon": "🇱🇧",
  "lesotho": "🇱🇸",
  "liberia": "🇱🇷",
  "libya": "🇱🇾",
  "liechtenstein": "🇱🇮",
  "lithuania": "🇱🇹",
  "luxembourg": "🇱🇺",
  "madagascar": "🇲🇬",
  "malawi": "🇲🇼",
  "malaysia": "🇲🇾",
  "maldives": "🇲🇻",
  "mali": "🇲🇱",
  "malta": "🇲🇹",
  "marshall islands": "🇲🇭",
  "mauritania": "🇲🇷",
  "mauritius": "🇲🇺",
  "mexico": "🇲🇽",
  "micronesia": "🇫🇲",
  "moldova": "🇲🇩",
  "monaco": "🇲🇨",
  "mongolia": "🇲🇳",
  "montenegro": "🇲🇪",
  "morocco": "🇲🇦",
  "mozambique": "🇲🇿",
  "myanmar": "🇲🇲",
  "namibia": "🇳🇦",
  "nauru": "🇳🇷",
  "nepal": "🇳🇵",
  "netherlands": "🇳🇱",
  "new zealand": "🇳🇿",
  "nicaragua": "🇳🇮",
  "niger": "🇳🇪",
  "nigeria": "🇳🇬",
  "north korea": "🇰🇵",
  "north macedonia": "🇲🇰",
  "norway": "🇳🇴",
  "oman": "🇴🇲",
  "pakistan": "🇵🇰",
  "palau": "🇵🇼",
  "palestine": "🇵🇸",
  "panama": "🇵🇦",
  "papua new guinea": "🇵🇬",
  "paraguay": "🇵🇾",
  "peru": "🇵🇪",
  "philippines": "🇵🇭",
  "poland": "🇵🇱",
  "portugal": "🇵🇹",
  "qatar": "🇶🇦",
  "romania": "🇷🇴",
  "russia": "🇷🇺",
  "rwanda": "🇷🇼",
  "saint kitts and nevis": "🇰🇳",
  "saint lucia": "🇱🇨",
  "saint vincent and the grenadines": "🇻🇨",
  "samoa": "🇼🇸",
  "san marino": "🇸🇲",
  "sao tome and principe": "🇸🇹",
  "saudi arabia": "🇸🇦",
  "senegal": "🇸🇳",
  "serbia": "🇷🇸",
  "seychelles": "🇸🇨",
  "sierra leone": "🇸🇱",
  "singapore": "🇸🇬",
  "slovakia": "🇸🇰",
  "slovenia": "🇸🇮",
  "solomon islands": "🇸🇧",
  "somalia": "🇸🇴",
  "south africa": "🇿🇦",
  "south korea": "🇰🇷",
  "south sudan": "🇸🇸",
  "spain": "🇪🇸",
  "sri lanka": "🇱🇰",
  "sudan": "🇸🇩",
  "suriname": "🇸🇷",
  "sweden": "🇸🇪",
  "switzerland": "🇨🇭",
  "syria": "🇸🇾",
  "taiwan": "🇹🇼",
  "tajikistan": "🇹🇯",
  "tanzania": "🇹🇿",
  "thailand": "🇹🇭",
  "timor-leste": "🇹🇱",
  "togo": "🇹🇬",
  "tonga": "🇹🇴",
  "trinidad and tobago": "🇹🇹",
  "tunisia": "🇹🇳",
  "turkey": "🇹🇷",
  "turkmenistan": "🇹🇲",
  "tuvalu": "🇹🇻",
  "uganda": "🇺🇬",
  "ukraine": "🇺🇦",
  "united arab emirates": "🇦🇪",
  "united kingdom": "🇬🇧",
  "united states": "🇺🇸",
  "uruguay": "🇺🇾",
  "uzbekistan": "🇺🇿",
  "vanuatu": "🇻🇺",
  "vatican city": "🇻🇦",
  "venezuela": "🇻🇪",
  "vietnam": "🇻🇳",
  "yemen": "🇾🇪",
  "zambia": "🇿🇲",
  "zimbabwe": "🇿🇼",
};
