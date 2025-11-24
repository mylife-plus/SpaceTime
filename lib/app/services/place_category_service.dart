import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/place_category_model.dart';
import '../services/memory_db.dart';
import '../modules/memories/controllers/memory_controller.dart';
import '../modules/add_memories/controllers/add_memories_controller.dart';

class PlaceCategoryService {
  static final PlaceCategoryService _instance =
      PlaceCategoryService._internal();
  factory PlaceCategoryService() => _instance;
  PlaceCategoryService._internal();

  final DatabaseHelper _databaseHelper = DatabaseHelper.instance;

  /// Get all main categories (parent categories)
  Future<List<PlaceCategory>> getMainCategories() async {
    try {
      final maps = await _databaseHelper.getMainPlaceCategories();
      final categories = PlaceCategoryHelper.fromMapList(maps);
      return PlaceCategoryHelper.sortCategories(categories);
    } catch (e) {
      // debugPrint('[PlaceCategoryService][getMainCategories] Error: $e');
      return [];
    }
  }

  /// Get subcategories for a specific parent category
  Future<List<PlaceCategory>> getSubcategories(int parentId) async {
    try {
      
      final maps = await _databaseHelper.getSubPlaceCategories(parentId);
      final categories = PlaceCategoryHelper.fromMapList(maps);
      
      return PlaceCategoryHelper.sortCategories(categories);
    } catch (e) {
      // debugPrint('[PlaceCategoryService][getSubcategories] Error: $e');
      return [];
    }
  }

  /// Get a single category by ID
  Future<PlaceCategory?> getCategoryById(int categoryId) async {
    try {

      // Get all categories and find the one with matching ID
      final allCategories = await getAllCategoriesHierarchical();

      // Search in main categories
      for (final mainCategory in allCategories) {
        if (mainCategory.id == categoryId) {
          return mainCategory;
        }

        // Search in subcategories
        if (mainCategory.subcategories != null) {
          for (final subcategory in mainCategory.subcategories!) {
            if (subcategory.id == categoryId) {
              return subcategory;
            }
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Get all categories in hierarchical structure
  Future<List<PlaceCategory>> getAllCategoriesHierarchical() async {
    try {

      // Step 1: Get main categories only (without subcategories)
      final mainCategoryMaps = await _databaseHelper.getMainPlaceCategories();

      // Step 2: Convert main categories to PlaceCategory objects
      final mainCategories = <PlaceCategory>[];
      for (final mainCategoryMap in mainCategoryMaps) {
        try {
          // Create main category without subcategories first
          final mainCategory = PlaceCategory.fromMap(mainCategoryMap);

          // Step 3: Get subcategories for this main category
          final subcategoryMaps = await _databaseHelper.getSubPlaceCategories(
            mainCategory.id!,
          );

          // Step 4: Convert subcategories to PlaceCategory objects
          final subcategories = <PlaceCategory>[];
          for (final subcategoryMap in subcategoryMaps) {
            try {
              final subcategory = PlaceCategory.fromMap(subcategoryMap);
              subcategories.add(subcategory);
            } catch (subError) {
            }
          }

          // Step 5: Create main category with subcategories
          final mainCategoryWithSubs = PlaceCategory(
            id: mainCategory.id,
            name: mainCategory.name,
            emoji: mainCategory.emoji,
            parentId: mainCategory.parentId,
            order: mainCategory.order,
            isCustom: mainCategory.isCustom,
            createdAt: mainCategory.createdAt,
            updatedAt: mainCategory.updatedAt,
            subcategories: subcategories,
          );
          mainCategories.add(mainCategoryWithSubs);
        } catch (mainError) {
        }
      }

      final sortedCategories = PlaceCategoryHelper.sortCategories(
        mainCategories,
      );
      return sortedCategories;
    } catch (e) {
      return [];
    }
  }

  /// Get all categories as a flat list
  Future<List<PlaceCategory>> getAllCategoriesFlat() async {
    try {
     
      final hierarchical = await getAllCategoriesHierarchical();
      final flattened = PlaceCategoryHelper.flattenHierarchy(hierarchical);
    
      return flattened;
    } catch (e) {
      // debugPrint('[PlaceCategoryService][getAllCategoriesFlat] Error: $e');
      return [];
    }
  }

  /// Search categories by name
  Future<List<PlaceCategory>> searchCategories(
    String query, {
    int limit = 20,
  }) async {
    try {
    

      // Get all categories that match the search query
      final maps = await _databaseHelper.searchPlaceCategories(
        query,
        limit: limit,
      );
      final directMatches = PlaceCategoryHelper.fromMapList(maps);
      
      final searchResults = <PlaceCategory>[];
      final addedIds = <int>{};

      // Process each direct match
      for (final match in directMatches) {
        if (match.isMainCategory) {
          // If it's a main category match, add all its subcategories instead
          
          try {
            final subcategoryMaps = await _databaseHelper.getSubPlaceCategories(
              match.id!,
            );
           

            for (final subcategoryMap in subcategoryMaps) {
              try {
                final subcategory = PlaceCategory.fromMap(subcategoryMap);
                if (!addedIds.contains(subcategory.id)) {
                  searchResults.add(subcategory);
                  addedIds.add(subcategory.id!);
                  
                }
              } catch (subError) {
                
              }
            }
          } catch (subFetchError) {
          
          }
        } else {
          // If it's a subcategory match, add it directly
          if (!addedIds.contains(match.id)) {
            searchResults.add(match);
            addedIds.add(match.id!);
            
          }
        }
      }

      
      return searchResults;
    } catch (e) {
      // debugPrint('[PlaceCategoryService][searchCategories] Error: $e');
      return [];
    }
  }

  /// Add a new custom category
  Future<PlaceCategory?> addCustomCategory({
    required String name,
    required String emoji,
    int? parentId,
    int order = 0,
  }) async {
    try {
      // debugPrint(
      //   '[PlaceCategoryService][addCustomCategory] Adding custom category: $name ($emoji)',
      // );

      // Check for duplicate category name (case-insensitive)
      final allCategories = await getAllCategoriesFlat();
      final nameLower = name.trim().toLowerCase();

      for (final category in allCategories) {
        if (category.name.toLowerCase() == nameLower) {
          // debugPrint(
          //   '[PlaceCategoryService][addCustomCategory] Duplicate category name found: ${category.name}',
          // );
          // Return a special marker to indicate duplicate
          // We'll use a category with id = -1 to signal duplicate
          return PlaceCategory(
            id: -1,
            name: name,
            emoji: emoji,
            parentId: parentId,
            order: order,
            isCustom: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }
      }

      // Additional check: If adding a main category, check if name conflicts with any subcategory
      // If adding a subcategory, check if name conflicts with its parent category
      if (parentId == null) {
        // Adding a main category - check if this name exists as any subcategory
        for (final category in allCategories) {
          if (category.parentId != null && category.name.toLowerCase() == nameLower) {
            
            // Return id = -3 to signal main category conflicts with subcategory
            return PlaceCategory(
              id: -3,
              name: name,
              emoji: emoji,
              parentId: parentId,
              order: order,
              isCustom: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
          }
        }
      } else {
        // Adding a subcategory - check if name conflicts with parent category or any other subcategory under same parent
        final parentCategory = await getCategoryById(parentId);
        if (parentCategory != null && parentCategory.name.toLowerCase() == nameLower) {
          
          // Return id = -4 to signal subcategory conflicts with parent category
          return PlaceCategory(
            id: -4,
            name: name,
            emoji: emoji,
            parentId: parentId,
            order: order,
            isCustom: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
        }
      }

      final now = DateTime.now();
      final categoryId = await _databaseHelper.addCustomPlaceCategory(
        name: name,
        emoji: emoji,
        parentId: parentId,
        order: order,
      );

      if (categoryId > 0) {
        final newCategory = PlaceCategory(
          id: categoryId,
          name: name,
          emoji: emoji,
          parentId: parentId,
          order: order,
          isCustom: true,
          createdAt: now,
          updatedAt: now,
        );

       
        return newCategory;
      } else {
        
        return null;
      }
    } catch (e) {
      // debugPrint('[PlaceCategoryService][addCustomCategory] Error: $e');
      return null;
    }
  }

  /// Update an existing category
  Future<bool> updateCategory({
    required int categoryId,
    String? name,
    String? emoji,
    int? order,
    int? parentId,
  }) async {
    try {
      // debugPrint(
     

      // Always get current category data before update for memory synchronization
      final currentCategory = await getCategoryById(categoryId);
      if (currentCategory == null) {
        debugPrint(
          '[PlaceCategoryService][updateCategory] Category not found for ID: $categoryId',
        );
        return false;
      }

      debugPrint(
        '[PlaceCategoryService][updateCategory] Current category: ${currentCategory.emoji} ${currentCategory.name}',
      );

      // Check for duplicate category name (case-insensitive) if name is being changed
      if (name != null && name.trim().toLowerCase() != currentCategory.name.toLowerCase()) {
        final allCategories = await getAllCategoriesFlat();
        final nameLower = name.trim().toLowerCase();

        for (final category in allCategories) {
          // Skip the current category being edited
          if (category.id != categoryId && category.name.toLowerCase() == nameLower) {
            debugPrint(
              '[PlaceCategoryService][updateCategory] Duplicate category name found: ${category.name}',
            );
            throw Exception('DUPLICATE_CATEGORY_NAME');
          }
        }

        // Additional check: If editing a main category, check if name conflicts with any subcategory
        // If editing a subcategory, check if name conflicts with its parent category
        if (currentCategory.parentId == null) {
          // Editing a main category - check if this name exists as any subcategory
          for (final category in allCategories) {
            if (category.id != categoryId && category.parentId != null && category.name.toLowerCase() == nameLower) {
              debugPrint(
                '[PlaceCategoryService][updateCategory] Main category name conflicts with existing subcategory: ${category.name}',
              );
              throw Exception('MAIN_CATEGORY_CONFLICTS_WITH_SUBCATEGORY');
            }
          }
        } else {
          // Editing a subcategory - check if name conflicts with parent category
          final parentCategory = await getCategoryById(currentCategory.parentId!);
          if (parentCategory != null && parentCategory.name.toLowerCase() == nameLower) {
            debugPrint(
              '[PlaceCategoryService][updateCategory] Subcategory name conflicts with parent category: ${parentCategory.name}',
            );
            throw Exception('SUBCATEGORY_CONFLICTS_WITH_PARENT');
          }
        }
      }

      final rowsAffected = await _databaseHelper.updatePlaceCategory(
        categoryId: categoryId,
        name: name,
        emoji: emoji,
        order: order,
        parentId: parentId,
      );

      final success = rowsAffected > 0;

      // If update was successful, check if name or emoji changed and update memories accordingly
      if (success) {
        // Get the updated category to see what actually changed
        final updatedCategory = await getCategoryById(categoryId);
        if (updatedCategory != null) {
          final oldEmoji = currentCategory.emoji;
          final oldName = currentCategory.name;
          final newEmoji = updatedCategory.emoji;
          final newName = updatedCategory.name;

          debugPrint(
            '[PlaceCategoryService][updateCategory] Comparing categories:',
          );
          debugPrint(
            '[PlaceCategoryService][updateCategory]   Old: "$oldEmoji $oldName"',
          );
          debugPrint(
            '[PlaceCategoryService][updateCategory]   New: "$newEmoji $newName"',
          );

          // Check if emoji or name actually changed
          if (oldEmoji != newEmoji || oldName != newName) {
            debugPrint(
              '[PlaceCategoryService][updateCategory] ✅ Category changed detected! Updating memories...',
            );

            // First, check how many memories currently use the old format
            final oldMemoryCount = await _databaseHelper
                .getMemoryCountForCategoryByEmojiAndName(oldEmoji, oldName);
            debugPrint(
              '[PlaceCategoryService][updateCategory] Found $oldMemoryCount memories using old format "$oldEmoji $oldName"',
            );

            if (oldMemoryCount > 0) {
              final memoriesUpdated = await _databaseHelper
                  .updateMemoryCategoryByEmojiAndName(
                    oldEmoji,
                    oldName,
                    newEmoji,
                    newName,
                  );
              debugPrint(
                '[PlaceCategoryService][updateCategory] ✅ Successfully updated $memoriesUpdated memories from "$oldEmoji $oldName" to "$newEmoji $newName"',
              );

              // Verify the update worked
              final newMemoryCount = await _databaseHelper
                  .getMemoryCountForCategoryByEmojiAndName(newEmoji, newName);
              final remainingOldCount = await _databaseHelper
                  .getMemoryCountForCategoryByEmojiAndName(oldEmoji, oldName);
              debugPrint(
                '[PlaceCategoryService][updateCategory] Verification: $newMemoryCount memories now use new format, $remainingOldCount still use old format',
              );
            } else {
              debugPrint(
                '[PlaceCategoryService][updateCategory] ⚠️  No memories found using old format - they might be using a different format',
              );

              // Check if memories exist with just the name (legacy format)
              final legacyCount = await _databaseHelper
                  .getMemoryCountForCategory(oldName);
              if (legacyCount > 0) {
                debugPrint(
                  '[PlaceCategoryService][updateCategory] Found $legacyCount memories using legacy format "$oldName"',
                );
                final legacyUpdated = await _databaseHelper
                    .updateMemoryCategoryName(oldName, "$newEmoji $newName");
                debugPrint(
                  '[PlaceCategoryService][updateCategory] Updated $legacyUpdated memories from legacy format',
                );
              }
            }
          } else {
            debugPrint(
              '[PlaceCategoryService][updateCategory] ℹ️  No emoji or name changes detected, skipping memory updates',
            );
          }
        } else {
          debugPrint(
            '[PlaceCategoryService][updateCategory] ❌ Warning: Could not retrieve updated category for memory sync',
          );
        }
      }

      // Update memory controllers to refresh their data with updated categories
      if (success) {
        await _refreshMemoryControllers();
      }

      debugPrint(
        '[PlaceCategoryService][updateCategory] Update ${success ? 'successful' : 'failed'} for category ID: $categoryId',
      );
      return success;
    } catch (e) {
      debugPrint('[PlaceCategoryService][updateCategory] Error: $e');
      // Rethrow duplicate exceptions so UI can handle them
      if (e.toString().contains('DUPLICATE_CATEGORY_NAME')) {
        rethrow;
      }
      return false;
    }
  }

  /// Delete a category (custom categories and predefined subcategories)
  /// Returns: true if deleted, false if failed, null if has memories (cannot delete)
  Future<bool?> deleteCategory(int categoryId) async {
    try {
      debugPrint(
        '[PlaceCategoryService][deleteCategory] Deleting category ID: $categoryId',
      );

      // First, get the category to check its name
      final category = await getCategoryById(categoryId);
      if (category == null) {
        debugPrint(
          '[PlaceCategoryService][deleteCategory] Category not found for ID: $categoryId',
        );
        return false;
      }

      // Check if any memories are using this category (using formatted string: emoji + space + name)
      final memoryCount = await _databaseHelper
          .getMemoryCountForCategoryByEmojiAndName(
            category.emoji,
            category.name,
          );
      if (memoryCount > 0) {
        debugPrint(
          '[PlaceCategoryService][deleteCategory] Cannot delete category "${category.emoji} ${category.name}" - $memoryCount memories are using it',
        );
        return null; // null indicates cannot delete due to memories
      }

      // If this is a main category, check if ANY of its subcategories have associated memories
      if (category.parentId == null) {
        final subcategories = await getSubcategories(categoryId);
        for (final subcategory in subcategories) {
          final subcategoryMemoryCount = await _databaseHelper
              .getMemoryCountForCategoryByEmojiAndName(
                subcategory.emoji,
                subcategory.name,
              );
          if (subcategoryMemoryCount > 0) {
            debugPrint(
              '[PlaceCategoryService][deleteCategory] Cannot delete main category "${category.emoji} ${category.name}" - subcategory "${subcategory.emoji} ${subcategory.name}" has $subcategoryMemoryCount memories',
            );
            return null; // null indicates cannot delete due to memories in subcategories
          }
        }
      }

      final rowsAffected = await _databaseHelper.deletePlaceCategory(
        categoryId,
      );

      final success = rowsAffected > 0;
      if (success) {
        debugPrint(
          '[PlaceCategoryService][deleteCategory] Successfully deleted category ID: $categoryId',
        );
      } else {
        debugPrint(
          '[PlaceCategoryService][deleteCategory] Failed to delete category ID: $categoryId (may be a protected main category)',
        );
      }
      return success;
    } catch (e) {
      debugPrint('[PlaceCategoryService][deleteCategory] Error: $e');
      return false;
    }
  }

  /// Get memory count for a specific category
  Future<int> getMemoryCountForCategory(String categoryName) async {
    try {
      return await _databaseHelper.getMemoryCountForCategory(categoryName);
    } catch (e) {
      debugPrint('[PlaceCategoryService][getMemoryCountForCategory] Error: $e');
      return 0;
    }
  }

  /// Get memory count for a specific category by emoji and name (formatted)
  Future<int> getMemoryCountForCategoryByEmojiAndName(
    String emoji,
    String name,
  ) async {
    try {
      return await _databaseHelper.getMemoryCountForCategoryByEmojiAndName(
        emoji,
        name,
      );
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][getMemoryCountForCategoryByEmojiAndName] Error: $e',
      );
      return 0;
    }
  }

  /// Get all memories that use a specific category
  Future<List<Map<String, dynamic>>> getMemoriesForCategory(
    String categoryName,
  ) async {
    try {
      return await _databaseHelper.getMemoriesForCategory(categoryName);
    } catch (e) {
      debugPrint('[PlaceCategoryService][getMemoriesForCategory] Error: $e');
      return [];
    }
  }

  /// Get all memories that use a specific category by emoji and name (formatted)
  Future<List<Map<String, dynamic>>> getMemoriesForCategoryByEmojiAndName(
    String emoji,
    String name,
  ) async {
    try {
      return await _databaseHelper.getMemoriesForCategoryByEmojiAndName(
        emoji,
        name,
      );
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][getMemoriesForCategoryByEmojiAndName] Error: $e',
      );
      return [];
    }
  }

  /// Force update all memories for a specific category (useful for fixing data inconsistencies)
  Future<int> forceUpdateMemoriesForCategory(int categoryId) async {
    try {
      final category = await getCategoryById(categoryId);
      if (category == null) {
        debugPrint(
          '[PlaceCategoryService][forceUpdateMemoriesForCategory] Category not found for ID: $categoryId',
        );
        return 0;
      }

      // Force update memories to use the current category format
      final formattedCategory = '${category.emoji} ${category.name}';
      debugPrint(
        '[PlaceCategoryService][forceUpdateMemoriesForCategory] Force updating memories to use: $formattedCategory',
      );

      // This will update memories that might be using old formats
      final memoriesUpdated = await _databaseHelper
          .updateMemoryCategoryByEmojiAndName(
            category.emoji,
            category.name, // old format (same as new)
            category.emoji,
            category.name, // new format (same as old)
          );

      debugPrint(
        '[PlaceCategoryService][forceUpdateMemoriesForCategory] Force updated $memoriesUpdated memories',
      );
      return memoriesUpdated;
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][forceUpdateMemoriesForCategory] Error: $e',
      );
      return 0;
    }
  }

  /// Debug method: Check for memory-category inconsistencies
  Future<void> debugCategoryMemoryConsistency() async {
    try {
      debugPrint(
        '[PlaceCategoryService][debugCategoryMemoryConsistency] Starting consistency check...',
      );

      final allCategories = await getAllCategoriesHierarchical();
      int totalInconsistencies = 0;

      for (final mainCategory in allCategories) {
        // Check main category
        await _debugSingleCategoryConsistency(mainCategory);

        // Check subcategories
        if (mainCategory.subcategories != null) {
          for (final subcategory in mainCategory.subcategories!) {
            final inconsistencies = await _debugSingleCategoryConsistency(
              subcategory,
            );
            totalInconsistencies += inconsistencies;
          }
        }
      }

      debugPrint(
        '[PlaceCategoryService][debugCategoryMemoryConsistency] Consistency check complete. Total inconsistencies found: $totalInconsistencies',
      );
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][debugCategoryMemoryConsistency] Error: $e',
      );
    }
  }

  /// Debug helper: Check consistency for a single category
  Future<int> _debugSingleCategoryConsistency(PlaceCategory category) async {
    try {
      final formattedCategory = '${category.emoji} ${category.name}';
      final memoryCount = await getMemoryCountForCategoryByEmojiAndName(
        category.emoji,
        category.name,
      );

      if (memoryCount > 0) {
        debugPrint(
          '[PlaceCategoryService][_debugSingleCategoryConsistency] ✅ Category "$formattedCategory" has $memoryCount memories',
        );
        return 0;
      } else {
        // Check if memories exist with just the name (old format)
        final oldFormatCount = await getMemoryCountForCategory(category.name);
        if (oldFormatCount > 0) {
          debugPrint(
            '[PlaceCategoryService][_debugSingleCategoryConsistency] ⚠️  INCONSISTENCY: Category "$formattedCategory" has $oldFormatCount memories using old format "${category.name}"',
          );
          return 1;
        } else {
          debugPrint(
            '[PlaceCategoryService][_debugSingleCategoryConsistency] ℹ️  Category "$formattedCategory" has no memories',
          );
          return 0;
        }
      }
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][_debugSingleCategoryConsistency] Error checking category ${category.name}: $e',
      );
      return 0;
    }
  }

  /// Fix specific category inconsistency (like School → School1)
  Future<int> fixCategoryInconsistency(
    String oldCategoryName,
    String newEmoji,
    String newName,
  ) async {
    try {
      debugPrint(
        '[PlaceCategoryService][fixCategoryInconsistency] Fixing inconsistency:',
      );
      debugPrint(
        '[PlaceCategoryService][fixCategoryInconsistency]   From: "$oldCategoryName"',
      );
      debugPrint(
        '[PlaceCategoryService][fixCategoryInconsistency]   To: "$newEmoji $newName"',
      );

      // Check how many memories use the old format
      final oldCount = await getMemoryCountForCategory(oldCategoryName);
      debugPrint(
        '[PlaceCategoryService][fixCategoryInconsistency] Found $oldCount memories using old format',
      );

      if (oldCount > 0) {
        // Update memories from old format to new format
        final updated = await _databaseHelper.updateMemoryCategoryName(
          oldCategoryName,
          '$newEmoji $newName',
        );
        debugPrint(
          '[PlaceCategoryService][fixCategoryInconsistency] ✅ Updated $updated memories',
        );

        // Verify the fix
        final remainingOld = await getMemoryCountForCategory(oldCategoryName);
        final newCount = await getMemoryCountForCategoryByEmojiAndName(
          newEmoji,
          newName,
        );
        debugPrint(
          '[PlaceCategoryService][fixCategoryInconsistency] Verification: $remainingOld old format remaining, $newCount new format',
        );

        return updated;
      } else {
        debugPrint(
          '[PlaceCategoryService][fixCategoryInconsistency] No memories found using old format',
        );
        return 0;
      }
    } catch (e) {
      debugPrint('[PlaceCategoryService][fixCategoryInconsistency] Error: $e');
      return 0;
    }
  }

  /// Fix all category inconsistencies automatically
  Future<int> fixAllCategoryInconsistencies() async {
    try {
      debugPrint(
        '[PlaceCategoryService][fixAllCategoryInconsistencies] Starting automatic fix...',
      );

      final allCategories = await getAllCategoriesHierarchical();
      int totalFixed = 0;

      for (final mainCategory in allCategories) {
        // Fix main category inconsistencies
        final mainFixed = await _fixSingleCategoryInconsistency(mainCategory);
        totalFixed += mainFixed;

        // Fix subcategory inconsistencies
        if (mainCategory.subcategories != null) {
          for (final subcategory in mainCategory.subcategories!) {
            final subFixed = await _fixSingleCategoryInconsistency(subcategory);
            totalFixed += subFixed;
          }
        }
      }

      debugPrint(
        '[PlaceCategoryService][fixAllCategoryInconsistencies] ✅ Fixed $totalFixed total inconsistencies',
      );

      // Refresh memory controllers if any fixes were made
      if (totalFixed > 0) {
        await _refreshMemoryControllers();
      }

      return totalFixed;
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][fixAllCategoryInconsistencies] Error: $e',
      );
      return 0;
    }
  }

  /// Fix inconsistencies for a single category
  Future<int> _fixSingleCategoryInconsistency(PlaceCategory category) async {
    try {
      // Check if memories exist with just the name (old format)
      final oldFormatCount = await getMemoryCountForCategory(category.name);
      if (oldFormatCount > 0) {
        debugPrint(
          '[PlaceCategoryService][_fixSingleCategoryInconsistency] Fixing ${category.name}: $oldFormatCount memories',
        );
        return await fixCategoryInconsistency(
          category.name,
          category.emoji,
          category.name,
        );
      }
      return 0;
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][_fixSingleCategoryInconsistency] Error fixing ${category.name}: $e',
      );
      return 0;
    }
  }

  /// Quick fix for the specific School → School1 issue
  Future<void> fixSchoolToSchool1Issue() async {
    try {
      debugPrint(
        '[PlaceCategoryService][fixSchoolToSchool1Issue] 🔧 Fixing School → School1 inconsistency...',
      );

      // Find the School1 category to get its emoji
      final allCategories = await getAllCategoriesHierarchical();
      PlaceCategory? school1Category;

      for (final mainCategory in allCategories) {
        if (mainCategory.subcategories != null) {
          for (final subcategory in mainCategory.subcategories!) {
            if (subcategory.name == 'School1') {
              school1Category = subcategory;
              break;
            }
          }
        }
        if (school1Category != null) break;
      }

      if (school1Category != null) {
        debugPrint(
          '[PlaceCategoryService][fixSchoolToSchool1Issue] Found School1 category: ${school1Category.emoji} ${school1Category.name}',
        );

        // Check for memories using old "School" format
        final oldSchoolCount = await getMemoryCountForCategory('School');
        debugPrint(
          '[PlaceCategoryService][fixSchoolToSchool1Issue] Found $oldSchoolCount memories using old "School" format',
        );

        if (oldSchoolCount > 0) {
          // Update memories from "School" to "🏫 School1" (or whatever emoji School1 uses)
          final updated = await _databaseHelper.updateMemoryCategoryName(
            'School',
            '${school1Category.emoji} ${school1Category.name}',
          );
          debugPrint(
            '[PlaceCategoryService][fixSchoolToSchool1Issue] ✅ Updated $updated memories from "School" to "${school1Category.emoji} ${school1Category.name}"',
          );

          // Verify the fix
          final remainingOld = await getMemoryCountForCategory('School');
          final newCount = await getMemoryCountForCategoryByEmojiAndName(
            school1Category.emoji,
            school1Category.name,
          );
          debugPrint(
            '[PlaceCategoryService][fixSchoolToSchool1Issue] ✅ Verification: $remainingOld old format remaining, $newCount new format',
          );

          // Refresh memory controllers after fixing
          await _refreshMemoryControllers();
        } else {
          debugPrint(
            '[PlaceCategoryService][fixSchoolToSchool1Issue] ℹ️  No memories found using old "School" format',
          );
        }
      } else {
        debugPrint(
          '[PlaceCategoryService][fixSchoolToSchool1Issue] ❌ Could not find School1 category',
        );
      }
    } catch (e) {
      debugPrint('[PlaceCategoryService][fixSchoolToSchool1Issue] ❌ Error: $e');
    }
  }

  /// Check if categories are initialized
  Future<bool> areCategoriesInitialized() async {
    try {
      return await _databaseHelper.arePlaceCategoriesInitialized();
    } catch (e) {
      debugPrint('[PlaceCategoryService][areCategoriesInitialized] Error: $e');
      return false;
    }
  }

  /// Initialize categories if needed
  Future<void> initializeCategoriesIfNeeded() async {
    try {
      debugPrint(
        '[PlaceCategoryService][initializeCategoriesIfNeeded] Checking initialization status',
      );
      await _databaseHelper.initializePlaceCategoriesIfNeeded();
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][initializeCategoriesIfNeeded] Error: $e',
      );
    }
  }

  /// Get categories suitable for dropdown/picker (with display text)
  Future<List<Map<String, dynamic>>> getCategoriesForPicker({
    bool includeSubcategories = true,
  }) async {
    try {
      debugPrint(
        '[PlaceCategoryService][getCategoriesForPicker] Fetching categories for picker',
      );

      final List<Map<String, dynamic>> pickerItems = [];

      if (includeSubcategories) {
        final hierarchical = await getAllCategoriesHierarchical();

        for (final mainCategory in hierarchical) {
          // Add main category
          pickerItems.add({
            'id': mainCategory.id,
            'name': mainCategory.name,
            'emoji': mainCategory.emoji,
            'displayText': mainCategory.displayText,
            'isMainCategory': true,
            'parentId': null,
          });

          // Add subcategories with indentation
          if (mainCategory.hasSubcategories) {
            for (final subCategory in mainCategory.subcategories!) {
              pickerItems.add({
                'id': subCategory.id,
                'name': subCategory.name,
                'emoji': subCategory.emoji,
                'displayText': '  ${subCategory.displayText}', // Indented
                'isMainCategory': false,
                'parentId': subCategory.parentId,
              });
            }
          }
        }
      } else {
        final mainCategories = await getMainCategories();
        for (final category in mainCategories) {
          pickerItems.add({
            'id': category.id,
            'name': category.name,
            'emoji': category.emoji,
            'displayText': category.displayText,
            'isMainCategory': true,
            'parentId': null,
          });
        }
      }

      debugPrint(
        '[PlaceCategoryService][getCategoriesForPicker] Prepared ${pickerItems.length} picker items',
      );
      return pickerItems;
    } catch (e) {
      debugPrint('[PlaceCategoryService][getCategoriesForPicker] Error: $e');
      return [];
    }
  }

  /// Refresh memory controllers to update their data after category changes
  Future<void> _refreshMemoryControllers() async {
    try {
      debugPrint(
        '[PlaceCategoryService][_refreshMemoryControllers] 🔄 Refreshing memory controllers...',
      );

      // Try to refresh MemoryController if it exists
      try {
        final memoryController = Get.find<MemoryController>();
        debugPrint(
          '[PlaceCategoryService][_refreshMemoryControllers] Found MemoryController, refreshing data...',
        );

        // Use onAgainInit to refresh all data including categories
        memoryController.onAgainInit();
        debugPrint(
          '[PlaceCategoryService][_refreshMemoryControllers] ✅ MemoryController data refreshed',
        );
      } catch (e) {
        debugPrint(
          '[PlaceCategoryService][_refreshMemoryControllers] MemoryController not found or error: $e',
        );
      }

      // Try to refresh AddMemoriesController if it exists
      try {
        final addMemoriesController = Get.find<AddMemoriesController>();
        // debugPrint('[PlaceCategoryService][_refreshMemoryControllers] Found AddMemoriesController, refreshing data...');

        // Reload memories and filter data in AddMemoriesController
        await addMemoriesController.loadMemoriesFromDatabase();
        await addMemoriesController.loadFilterData();

        debugPrint(
          '[PlaceCategoryService][_refreshMemoryControllers] ✅ AddMemoriesController data refreshed',
        );
      } catch (e) {
        debugPrint(
          '[PlaceCategoryService][_refreshMemoryControllers] AddMemoriesController not found or error: $e',
        );
      }

      // Also refresh memory view if it's in edit mode or needs category refresh
      await _refreshMemoryViewIfNeeded();

      // Refresh category picker widget if it's currently open
      await _refreshCategoryPickerIfOpen();

      debugPrint(
        '[PlaceCategoryService][_refreshMemoryControllers] ✅ Memory controllers refresh completed',
      );
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][_refreshMemoryControllers] ❌ Error refreshing memory controllers: $e',
      );
    }
  }

  /// Refresh memory view if needed (especially in edit mode)
  Future<void> _refreshMemoryViewIfNeeded() async {
    try {
      debugPrint(
        '[PlaceCategoryService][_refreshMemoryViewIfNeeded] 🔄 Checking if memory view needs refresh...',
      );

      // Try to find MemoryController to check if we're in memory view context
      try {
        final memoryController = Get.find<MemoryController>();

        // Always check and update selected category if it exists, regardless of context
        // This ensures category updates are reflected immediately in memory view
        debugPrint(
          '[PlaceCategoryService][_refreshMemoryViewIfNeeded] MemoryController found, checking selected category...',
        );

        if (memoryController.selectedCategory.value.isNotEmpty) {
          final currentCategoryText = memoryController.selectedCategory.value;
          debugPrint(
            '[PlaceCategoryService][_refreshMemoryViewIfNeeded] Current selected category: "$currentCategoryText"',
          );

          // Try to find the updated category in the database and update the controller
          final updatedCategory = await _findUpdatedCategoryForText(
            currentCategoryText,
          );

          if (updatedCategory != null) {
            final updatedCategoryText =
                '${updatedCategory.emoji} ${updatedCategory.name}';
            if (updatedCategoryText != currentCategoryText) {
              debugPrint(
                '[PlaceCategoryService][_refreshMemoryViewIfNeeded] 🔄 Updating selected category from "$currentCategoryText" to "$updatedCategoryText"',
              );
              memoryController.selectedCategory.value = updatedCategoryText;
              debugPrint(
                '[PlaceCategoryService][_refreshMemoryViewIfNeeded] ✅ Selected category updated successfully',
              );
            } else {
              debugPrint(
                '[PlaceCategoryService][_refreshMemoryViewIfNeeded] Selected category is already up to date',
              );
            }
          } else {
            debugPrint(
              '[PlaceCategoryService][_refreshMemoryViewIfNeeded] ⚠️ Could not find matching category for "$currentCategoryText"',
            );
          }
        } else {
          debugPrint(
            '[PlaceCategoryService][_refreshMemoryViewIfNeeded] No selected category to update',
          );
        }

        // Always refresh the category list for future selections
        try {
          memoryController.onAgainInit();
          debugPrint(
            '[PlaceCategoryService][_refreshMemoryViewIfNeeded] ✅ Memory controller refreshed',
          );
        } catch (e) {
          debugPrint(
            '[PlaceCategoryService][_refreshMemoryViewIfNeeded] Error refreshing memory controller: $e',
          );
        }
      } catch (e) {
        debugPrint(
          '[PlaceCategoryService][_refreshMemoryViewIfNeeded] MemoryController not found or error: $e',
        );
      }
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][_refreshMemoryViewIfNeeded] ❌ Error refreshing memory view: $e',
      );
    }
  }

  /// Helper method to find updated category information for a given category text
  Future<PlaceCategory?> _findUpdatedCategoryForText(
    String categoryText,
  ) async {
    try {
      debugPrint(
        '[PlaceCategoryService][_findUpdatedCategoryForText] Looking for updated category for: "$categoryText"',
      );

      // Parse the current category text (format: "emoji name")
      final parts = categoryText.split(' ');
      if (parts.length < 2) {
        debugPrint(
          '[PlaceCategoryService][_findUpdatedCategoryForText] Invalid category format: "$categoryText"',
        );
        return null;
      }

      final emoji = parts[0];
      final name = parts.sublist(1).join(' ');
      debugPrint(
        '[PlaceCategoryService][_findUpdatedCategoryForText] Parsed - emoji: "$emoji", name: "$name"',
      );

      // Get all categories from database
      final allCategories = await getAllCategoriesFlat();
      debugPrint(
        '[PlaceCategoryService][_findUpdatedCategoryForText] Found ${allCategories.length} categories in database',
      );

      // First try to find by exact name match (most reliable)
      for (final category in allCategories) {
        if (category.name == name) {
          debugPrint(
            '[PlaceCategoryService][_findUpdatedCategoryForText] ✅ Found exact name match: ${category.emoji} ${category.name}',
          );
          return category;
        }
      }

      // If not found by name, try to find by emoji (in case name was changed)
      for (final category in allCategories) {
        if (category.emoji == emoji) {
          debugPrint(
            '[PlaceCategoryService][_findUpdatedCategoryForText] ✅ Found emoji match: ${category.emoji} ${category.name}',
          );
          return category;
        }
      }

      debugPrint(
        '[PlaceCategoryService][_findUpdatedCategoryForText] ❌ No matching category found',
      );
      return null;
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][_findUpdatedCategoryForText] ❌ Error finding updated category: $e',
      );
      return null;
    }
  }

  /// Refresh category picker widget if it's currently open
  Future<void> _refreshCategoryPickerIfOpen() async {
    try {
      debugPrint(
        '[PlaceCategoryService][_refreshCategoryPickerIfOpen] 🔄 Triggering category picker refresh...',
      );

      // Try to find the global refresh notifier registered by CategoryPickerWidget
      try {
        final refreshNotifier = Get.find<RxInt>(tag: 'categoryPickerRefresh');
        refreshNotifier.value = DateTime.now().millisecondsSinceEpoch;
        debugPrint(
          '[PlaceCategoryService][_refreshCategoryPickerIfOpen] ✅ Category picker refresh triggered',
        );
      } catch (e) {
        // If the notifier is not found, the category picker is not currently open
        debugPrint(
          '[PlaceCategoryService][_refreshCategoryPickerIfOpen] Category picker not open: $e',
        );
      }
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][_refreshCategoryPickerIfOpen] ❌ Error refreshing category picker: $e',
      );
    }
  }

  /// Method to refresh all memory-related controllers when a memory is updated or deleted
  /// This should be called from memory view when memories are modified
  Future<void> refreshMemoryControllersAfterMemoryChange() async {
    try {
      debugPrint(
        '[PlaceCategoryService][refreshMemoryControllersAfterMemoryChange] 🔄 Refreshing controllers after memory change...',
      );

      // Refresh AddMemoriesController to update the memory list
      try {
        final addMemoriesController = Get.find<AddMemoriesController>();
        addMemoriesController.onAgainInit();
        debugPrint(
          '[PlaceCategoryService][refreshMemoryControllersAfterMemoryChange] ✅ AddMemoriesController refreshed',
        );
      } catch (e) {
        debugPrint(
          '[PlaceCategoryService][refreshMemoryControllersAfterMemoryChange] AddMemoriesController not found: $e',
        );
      }

      // Refresh MemoryController if it exists
      try {
        final memoryController = Get.find<MemoryController>();
        memoryController.onAgainInit();
        debugPrint(
          '[PlaceCategoryService][refreshMemoryControllersAfterMemoryChange] ✅ MemoryController refreshed',
        );
      } catch (e) {
        debugPrint(
          '[PlaceCategoryService][refreshMemoryControllersAfterMemoryChange] MemoryController not found: $e',
        );
      }

      debugPrint(
        '[PlaceCategoryService][refreshMemoryControllersAfterMemoryChange] ✅ Memory controllers refresh completed',
      );
    } catch (e) {
      debugPrint(
        '[PlaceCategoryService][refreshMemoryControllersAfterMemoryChange] ❌ Error refreshing controllers: $e',
      );
    }
  }
}
