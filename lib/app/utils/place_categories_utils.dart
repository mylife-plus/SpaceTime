import '../services/place_category_service.dart';
import '../models/place_category_model.dart';

var placeCategoriesJson = {
  "Accommodation": [
    {"name": "Home", "emoji": "🏠"},
    {"name": "Hotel", "emoji": "🏨"},
    {"name": "Motel", "emoji": "🏩"},
    {"name": "Hostel", "emoji": "🛏️"},
    {"name": "Bed and Breakfast", "emoji": "🥞"},
    {"name": "Vacation Rental", "emoji": "🏡"},
    {"name": "Campground", "emoji": "🏕️"},
    {"name": "Resort", "emoji": "🏖️"},
    {"name": "Guest House", "emoji": "🏘️"},
  ],
  "Food and Drink": [
    {"name": "Restaurant", "emoji": "🍽️"},
    {"name": "Cafe", "emoji": "☕️"},
    {"name": "Bar/Pub", "emoji": "🍻"},
    {"name": "Fast Food", "emoji": "🍔"},
    {"name": "Bakery", "emoji": "🥖"},
    {"name": "Food Court", "emoji": "🥡"},
    {"name": "Ice Cream Shop", "emoji": "🍨"},
    {"name": "Coffee Shop", "emoji": "🫘"},
  ],
  "Retail and Shopping": [
    {"name": "Supermarket", "emoji": "🛒"},
    {"name": "Convenience Store", "emoji": "🏪"},
    {"name": "Department Store", "emoji": "🛍️"},
    {"name": "Shopping Mall", "emoji": "🏬"},
    {"name": "Pharmacy", "emoji": "💊"},
    {"name": "Market", "emoji": "🧺"},
    {"name": "Jewelry Store", "emoji": "💍"},
    {"name": "Florist", "emoji": "🌷"},
  ],
  "Health and Medical": [
    {"name": "Hospital", "emoji": "🏥"},
    {"name": "Clinic", "emoji": "🩺"},
    {"name": "Pharmacy", "emoji": "⚕️"},
    {"name": "Dentist", "emoji": "🦷"},
    {"name": "Veterinary Clinic", "emoji": "🐾"},
  ],
  "Education": [
    {"name": "School", "emoji": "🏫"},
    {"name": "University", "emoji": "🧑‍🎓"},
    {"name": "College", "emoji": "🎓"},
    {"name": "Kindergarten", "emoji": "🧒"},
    {"name": "Library", "emoji": "📚"},
  ],
  "Transportation": [
    {"name": "Airport", "emoji": "✈️"},
    {"name": "Train Station", "emoji": "🚆"},
    {"name": "Bus Station", "emoji": "🚍"},
    {"name": "Subway/Metro Station", "emoji": "🚇"},
    {"name": "Taxi Stand", "emoji": "🚖"},
    {"name": "Parking Lot/Garage", "emoji": "🅿️"},
    {"name": "Bicycle Rental", "emoji": "🚲"},
    {"name": "Car Rental", "emoji": "🚗"},
    {"name": "Ferry Terminal", "emoji": "⛴️"},
    {"name": "Charging Station", "emoji": "🔋"},
  ],
  "Financial Service": [
    {"name": "Bank", "emoji": "🏦"},
    {"name": "ATM", "emoji": "🏧"},
    {"name": "Currency Exchange", "emoji": "💱"},
    {"name": "Insurance Agency", "emoji": "📑"},
  ],
  "Entertainment and Recreation": [
    {"name": "Movie Theater", "emoji": "🎬"},
    {"name": "Amusement Park", "emoji": "🎡"},
    {"name": "Zoo", "emoji": "🐘"},
    {"name": "Aquarium", "emoji": "🐠"},
    {"name": "Bowling Alley", "emoji": "🎳"},
    {"name": "Arcade", "emoji": "🕹️"},
    {"name": "Nightclub", "emoji": "💃"},
    {"name": "Casino", "emoji": "♦️"},
    {"name": "Concert Venue", "emoji": "🎤"},
    {"name": "Theater", "emoji": "🎭"},
  ],
  "Cultural and Historical": [
    {"name": "Museum", "emoji": "🏛️"},
    {"name": "Art Gallery", "emoji": "🖼️"},
    {"name": "Historical Site", "emoji": "📜"},
    {"name": "Monument", "emoji": "🗿"},
    {"name": "Archaeological Site", "emoji": "⚒️"},
    {"name": "Castle", "emoji": "🏰"},
    {"name": "Cultural Center", "emoji": "🎎"},
    {"name": "Memorial", "emoji": "🪦"},
  ],
  "Sport and Fitness": [
    {"name": "Gyms/Fitness Center", "emoji": "🏋️"},
    {"name": "Sports Field", "emoji": "⚽️"},
    {"name": "Stadium", "emoji": "🏟️"},
    {"name": "Swimming Pool", "emoji": "🏊"},
    {"name": "Golf Course", "emoji": "⛳️"},
    {"name": "Tennis Court", "emoji": "🎾"},
    {"name": "Skate Park", "emoji": "🛹"},
    {"name": "Yoga Studio", "emoji": "🧘"},
  ],
  "Parks and Nature": [
    {"name": "Park", "emoji": "🌳"},
    {"name": "Nature Reserve", "emoji": "🌲"},
    {"name": "Beach", "emoji": "🏖️"},
    {"name": "Forest", "emoji": "🌴"},
    {"name": "Coast", "emoji": "🌊"},
    {"name": "Botanical Garden", "emoji": "🌺"},
    {"name": "Picnic Area", "emoji": "🧺"},
    {"name": "Playground", "emoji": "🛝"},
    {"name": "Scenic Lookout", "emoji": "🌄"},
  ],
  "Religious Site": [
    {"name": "Church", "emoji": "⛪️"},
    {"name": "Mosque", "emoji": "🕌"},
    {"name": "Temple", "emoji": "🛕"},
    {"name": "Synagogue", "emoji": "🕍"},
    {"name": "Shrine", "emoji": "🎐"},
    {"name": "Monastery", "emoji": "🏯"},
    {"name": "Cemetery", "emoji": "🪦"},
  ],
  "Government and Public Service": [
    {"name": "Post Office", "emoji": "📮"},
    {"name": "Police Station", "emoji": "👮"},
    {"name": "Fire Station", "emoji": "🚒"},
    {"name": "Courthouse", "emoji": "⚖️"},
    {"name": "City Hall", "emoji": "🏛️"},
    {"name": "Embassy/Consulate", "emoji": "🛂"},
    {"name": "Public Library", "emoji": "📖"},
    {"name": "Community Center", "emoji": "🏘️"},
  ],
  "Business and Professional Service": [
    {"name": "Office", "emoji": "🏢"},
    {"name": "Co-working Space", "emoji": "👩‍💻"},
    {"name": "Conference Center", "emoji": "🎤"},
    {"name": "Law Firm", "emoji": "⚖️"},
    {"name": "Accounting Firm", "emoji": "🧾"},
    {"name": "Repair Shop", "emoji": "🔧"},
  ],
  "Beauty and Personal Care": [
    {"name": "Hair Salon", "emoji": "💇"},
    {"name": "Barbershop", "emoji": "💈"},
    {"name": "Spa", "emoji": "💆"},
    {"name": "Nail Salon", "emoji": "💅"},
    {"name": "Tattoo Parlor", "emoji": "🎨"},
  ],
};

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
