import 'package:spacetime/app/l10n/place_category_l10n.dart';

class PlaceCategory {
  final int? id;
  final String name;
  final String emoji;
  final int? parentId;
  final int order;
  final bool isCustom;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PlaceCategory>? subcategories;

  PlaceCategory({
    this.id,
    required this.name,
    required this.emoji,
    this.parentId,
    this.order = 0,
    this.isCustom = false,
    required this.createdAt,
    required this.updatedAt,
    this.subcategories,
  });

  /// Create PlaceCategory from database map
  factory PlaceCategory.fromMap(Map<String, dynamic> map) {
    return PlaceCategory(
      id: map['place_category_id'] as int?,
      name: map['place_category_name'] as String,
      emoji: map['place_category_emoji'] as String,
      parentId: map['place_category_parent_id'] as int?,
      order: map['place_category_order'] as int? ?? 0,
      isCustom: (map['place_category_is_custom'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['place_category_created_at'] as String),
      updatedAt: DateTime.parse(map['place_category_updated_at'] as String),
      subcategories:
          map['subcategories'] != null
              ? (map['subcategories'] as List)
                  .map(
                    (sub) => PlaceCategory.fromMap(sub as Map<String, dynamic>),
                  )
                  .toList()
              : null,
    );
  }

  /// Convert PlaceCategory to database map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'place_category_id': id,
      'place_category_name': name,
      'place_category_emoji': emoji,
      'place_category_parent_id': parentId,
      'place_category_order': order,
      'place_category_is_custom': isCustom ? 1 : 0,
      'place_category_created_at': createdAt.toIso8601String(),
      'place_category_updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Create a copy of this PlaceCategory with updated fields
  PlaceCategory copyWith({
    int? id,
    String? name,
    String? emoji,
    int? parentId,
    int? order,
    bool? isCustom,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<PlaceCategory>? subcategories,
  }) {
    return PlaceCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      parentId: parentId ?? this.parentId,
      order: order ?? this.order,
      isCustom: isCustom ?? this.isCustom,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      subcategories: subcategories ?? this.subcategories,
    );
  }

  /// Check if this is a main category (has no parent)
  bool get isMainCategory => parentId == null;

  /// Check if this is a subcategory (has a parent)
  bool get isSubcategory => parentId != null;

  /// Get display text with emoji (predefined categories use l10n; DB [name] stays English).
  String get displayText =>
      '$emoji ${localizedPlaceCategoryName(name: name, emoji: emoji, isCustom: isCustom, isMainCategory: isMainCategory)}';

  /// Check if this category has subcategories
  bool get hasSubcategories =>
      subcategories != null && subcategories!.isNotEmpty;

  @override
  String toString() {
    return 'PlaceCategory{id: $id, name: $name, emoji: $emoji, parentId: $parentId, order: $order, isCustom: $isCustom}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaceCategory &&
        other.id == id &&
        other.name == name &&
        other.emoji == emoji &&
        other.parentId == parentId &&
        other.order == order &&
        other.isCustom == isCustom;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        emoji.hashCode ^
        parentId.hashCode ^
        order.hashCode ^
        isCustom.hashCode;
  }
}

/// Helper class for place category operations
class PlaceCategoryHelper {
  /// Convert list of database maps to list of PlaceCategory objects
  static List<PlaceCategory> fromMapList(List<Map<String, dynamic>> maps) {
    return maps.map((map) => PlaceCategory.fromMap(map)).toList();
  }

  /// Group subcategories under their parent categories
  static List<PlaceCategory> buildHierarchy(List<PlaceCategory> allCategories) {
    final Map<int, PlaceCategory> categoryMap = {};
    final List<PlaceCategory> mainCategories = [];

    // First pass: create map and identify main categories
    for (final category in allCategories) {
      categoryMap[category.id!] = category;
      if (category.isMainCategory) {
        mainCategories.add(category);
      }
    }

    // Second pass: attach subcategories to their parents
    for (final category in allCategories) {
      if (category.isSubcategory &&
          categoryMap.containsKey(category.parentId)) {
        final parent = categoryMap[category.parentId!]!;
        final updatedSubcategories = List<PlaceCategory>.from(
          parent.subcategories ?? [],
        );
        updatedSubcategories.add(category);
        categoryMap[category.parentId!] = parent.copyWith(
          subcategories: updatedSubcategories,
        );
      }
    }

    // Return main categories with their subcategories attached
    return mainCategories.map((main) => categoryMap[main.id!]!).toList();
  }

  /// Flatten hierarchical categories into a single list
  static List<PlaceCategory> flattenHierarchy(
    List<PlaceCategory> hierarchicalCategories,
  ) {
    final List<PlaceCategory> flattened = [];

    for (final mainCategory in hierarchicalCategories) {
      flattened.add(mainCategory);
      if (mainCategory.hasSubcategories) {
        flattened.addAll(mainCategory.subcategories!);
      }
    }

    return flattened;
  }

  /// Search categories by name (case-insensitive)
  static List<PlaceCategory> searchCategories(
    List<PlaceCategory> categories,
    String query,
  ) {
    if (query.isEmpty) return categories;

    final lowerQuery = query.toLowerCase();
    return categories
        .where((category) => category.name.toLowerCase().contains(lowerQuery))
        .toList();
  }

  /// Sort categories by order and name
  static List<PlaceCategory> sortCategories(List<PlaceCategory> categories) {
    final sorted = List<PlaceCategory>.from(categories);
    sorted.sort((a, b) {
      final orderComparison = a.order.compareTo(b.order);
      if (orderComparison != 0) return orderComparison;
      return a.name.compareTo(b.name);
    });
    return sorted;
  }
}
