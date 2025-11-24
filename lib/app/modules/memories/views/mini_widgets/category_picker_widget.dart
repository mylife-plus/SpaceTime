import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:google_fonts/google_fonts.dart' as gfonts;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/place_category_service.dart';
import 'package:spacetime/app/models/place_category_model.dart';
import 'package:spacetime/app/shared/widgets/add_place_category_popup.dart';

class CategoryPickerWidget extends StatefulWidget {
  final Function(PlaceCategory)? onCategorySelected;
  final PlaceCategory? selectedCategory;

  // Multiple selection mode parameters
  final bool allowMultipleSelection;
  final List<PlaceCategory>? selectedCategories;
  final Function(List<PlaceCategory>)? onMultipleCategoriesSelected;

  const CategoryPickerWidget({
    super.key,
    this.onCategorySelected,
    this.selectedCategory,
    this.allowMultipleSelection = false,
    this.selectedCategories,
    this.onMultipleCategoriesSelected,
  });

  @override
  State<CategoryPickerWidget> createState() => _CategoryPickerWidgetState();
}

class _CategoryPickerWidgetState extends State<CategoryPickerWidget> {
  final TextEditingController _searchController = TextEditingController();
  final PlaceCategoryService _categoryService = PlaceCategoryService();

  // Reactive state variables
  final RxList<PlaceCategory> _mainCategories = <PlaceCategory>[].obs;
  final RxList<PlaceCategory> _searchResults = <PlaceCategory>[].obs;
  final RxBool _isLoading = false.obs;
  final RxBool _isSearching = false.obs;
  final RxMap<int, bool> _expandedCategories = <int, bool>{}.obs;
  final RxMap<int, bool> _addingToCategory = <int, bool>{}.obs;
  final RxMap<int, TextEditingController> _inlineNameControllers = <int, TextEditingController>{}.obs;
  final RxMap<int, TextEditingController> _inlineEmojiControllers = <int, TextEditingController>{}.obs;
  final RxMap<int, ExpansionTileController> _expansionControllers = <int, ExpansionTileController>{}.obs;
  final RxMap<int, bool> _pendingAddingMode = <int, bool>{}.obs;

  // Inline editing state for subcategories
  final RxMap<int, bool> _editingCategory = <int, bool>{}.obs;
  final RxMap<int, TextEditingController> _editNameControllers = <int, TextEditingController>{}.obs;
  final RxMap<int, TextEditingController> _editEmojiControllers = <int, TextEditingController>{}.obs;

  // Recently selected subcategories storage (max 6 items)
  static const String _recentSubcategoriesKey = 'recent_subcategories';
  static const int _maxRecentItems = 6;

  // Multiple selection state
  final RxList<PlaceCategory> _selectedCategories = <PlaceCategory>[].obs;

  // Memory count cache for categories
  final RxMap<int, int> _categoryMemoryCount = <int, int>{}.obs;

  // Main category inline adding state
  final RxBool _addingMainCategory = false.obs;
  final TextEditingController _mainCategoryNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[CategoryPickerWidget][initState] CategoryPickerWidget opened, initializing...',
    );
    debugPrint(
      '[CategoryPickerWidget][initState] Multiple selection mode: ${widget.allowMultipleSelection}',
    );
    debugPrint(
      '[CategoryPickerWidget][initState] Starting database initialization and category loading',
    );

    // Initialize selected categories for multiple selection mode
    if (widget.allowMultipleSelection && widget.selectedCategories != null) {
      _selectedCategories.addAll(widget.selectedCategories!);
      debugPrint(
        '[CategoryPickerWidget][initState] Initialized with ${_selectedCategories.length} pre-selected categories',
      );
    }

    // Register global refresh notifier for external access
    try {
      Get.put(_globalRefreshNotifier, tag: 'categoryPickerRefresh');
      debugPrint(
        '[CategoryPickerWidget][initState] Global refresh notifier registered',
      );
    } catch (e) {
      debugPrint(
        '[CategoryPickerWidget][initState] Global refresh notifier already registered: $e',
      );
    }

    _loadCategories();
    _searchController.addListener(_onSearchChanged);

    // Listen for global refresh triggers
    ever(_globalRefreshNotifier, (timestamp) {
      if (timestamp > 0) {
        debugPrint(
          '[CategoryPickerWidget][initState] Global refresh triggered, refreshing categories...',
        );
        _refreshCategoriesFromDatabase();
      }
    });

    debugPrint(
      '[CategoryPickerWidget][initState] CategoryPickerWidget initialization completed',
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();

    // Dispose main category controllers
    _mainCategoryNameController.dispose();

    // Dispose inline controllers
    for (final controller in _inlineNameControllers.values) {
      controller.dispose();
    }
    for (final controller in _inlineEmojiControllers.values) {
      controller.dispose();
    }

    // Dispose editing controllers
    for (final controller in _editNameControllers.values) {
      controller.dispose();
    }
    for (final controller in _editEmojiControllers.values) {
      controller.dispose();
    }

    // Clear expansion tile controllers (they don't have dispose method)
    _expansionControllers.clear();

    // Clear memory count cache
    _categoryMemoryCount.clear();

    // Close reactive variables to prevent memory leaks and dependency issues
    _mainCategories.close();
    _searchResults.close();
    _isLoading.close();
    _isSearching.close();
    _expandedCategories.close();
    _addingToCategory.close();
    _inlineNameControllers.close();
    _inlineEmojiControllers.close();
    _expansionControllers.close();
    _pendingAddingMode.close();
    _editingCategory.close();
    _editNameControllers.close();
    _editEmojiControllers.close();
    _selectedCategories.close();
    _categoryMemoryCount.close();
    _addingMainCategory.close();

    // Clean up global refresh notifier
    try {
      Get.delete<RxInt>(tag: 'categoryPickerRefresh');
      debugPrint(
        '[CategoryPickerWidget][dispose] Global refresh notifier cleaned up',
      );
    } catch (e) {
      debugPrint(
        '[CategoryPickerWidget][dispose] Error cleaning up global refresh notifier: $e',
      );
    }

    super.dispose();
  }

  /// Load all main categories with their subcategories
  Future<void> _loadCategories() async {
    try {
      _isLoading.value = true;
      debugPrint(
        '[CategoryPickerWidget][_loadCategories] Starting category loading process',
      );

      // Step 1: Check if categories are already initialized in database
      debugPrint(
        '[CategoryPickerWidget][_loadCategories] Checking if place categories are initialized',
      );
      final isInitialized = await _categoryService.areCategoriesInitialized();
      debugPrint(
        '[CategoryPickerWidget][_loadCategories] Database initialization check result: $isInitialized',
      );

      if (!isInitialized) {
        debugPrint(
          '[CategoryPickerWidget][_loadCategories] Categories not initialized, starting initialization',
        );

        // Step 2: Initialize predefined categories if needed
        try {
          await _categoryService.initializeCategoriesIfNeeded();
          debugPrint(
            '[CategoryPickerWidget][_loadCategories] Place categories initialization completed successfully',
          );

          // Verify initialization worked
          final postInitCheck =
              await _categoryService.areCategoriesInitialized();
          debugPrint(
            '[CategoryPickerWidget][_loadCategories] Post-initialization check: $postInitCheck',
          );
        } catch (initError) {
          debugPrint(
            '[CategoryPickerWidget][_loadCategories] ❌ Initialization failed: $initError',
          );
          debugPrint(
            '[CategoryPickerWidget][_loadCategories] Initialization error type: ${initError.runtimeType}',
          );
        }
      } else {
        debugPrint(
          '[CategoryPickerWidget][_loadCategories] Place categories already initialized, skipping initialization',
        );
      }

      // Database is already initialized, proceed with loading

      // Step 3: Fetch all categories from database
      debugPrint(
        '[CategoryPickerWidget][_loadCategories] Fetching categories from database',
      );

      // Clear expansion controllers to prevent reuse issues
      _expansionControllers.clear();
      debugPrint(
        '[CategoryPickerWidget][_loadCategories] Cleared expansion controllers',
      );

      // Clear memory count cache
      _categoryMemoryCount.clear();
      debugPrint(
        '[CategoryPickerWidget][_loadCategories] Cleared memory count cache',
      );

      final categories = await _categoryService.getAllCategoriesHierarchical();
      _mainCategories.value = categories;

      debugPrint(
        '[CategoryPickerWidget][_loadCategories] Successfully loaded ${categories.length} main categories from database',
      );

      // Verify we have the expected predefined categories
      if (_mainCategories.isNotEmpty) {
        debugPrint(
          '[CategoryPickerWidget][_loadCategories] ✅ Database contains categories - initialization successful',
        );

        // Log category details for debugging
        for (int i = 0; i < _mainCategories.length; i++) {
          final category = _mainCategories[i];
          final subcategoryCount = category.subcategories?.length ?? 0;
          final customStatus = category.isCustom ? '(Custom)' : '(Predefined)';
          debugPrint(
            '[CategoryPickerWidget][_loadCategories] Main Category ${i + 1}: ${category.emoji} ${category.name} - $subcategoryCount subcategories $customStatus',
          );

          // Log first few subcategories for verification
          if (category.hasSubcategories && i < 3) {
            // Only log first 3 main categories' subcategories
            for (int j = 0; j < math.min(3, subcategoryCount); j++) {
              final sub = category.subcategories![j];
              debugPrint(
                '[CategoryPickerWidget][_loadCategories]   └─ Subcategory: ${sub.emoji} ${sub.name}',
              );
            }
            if (subcategoryCount > 3) {
              debugPrint(
                '[CategoryPickerWidget][_loadCategories]   └─ ... and ${subcategoryCount - 3} more subcategories',
              );
            }
          }
        }
      } else {
        debugPrint(
          '[CategoryPickerWidget][_loadCategories] ⚠️ No categories found in database - this may indicate an initialization issue',
        );
      }
    } catch (e) {
      debugPrint(
        '[CategoryPickerWidget][_loadCategories] Error during category loading/initialization: $e',
      );
      debugPrint(
        '[CategoryPickerWidget][_loadCategories] Error type: ${e.runtimeType}',
      );
      debugPrint(
        '[CategoryPickerWidget][_loadCategories] Stack trace: ${StackTrace.current}',
      );

      // Get.snackbar(
      //   'Database Error',
      //   'Failed to load places: $e',
      //   backgroundColor: Colors.red,
      //   colorText: Colors.white,
      //   duration: const Duration(seconds: 5),
      // );

      // Set empty categories to prevent UI errors
      _mainCategories.value = [];
    } finally {
      _isLoading.value = false;
      debugPrint(
        '[CategoryPickerWidget][_loadCategories] Category loading process completed',
      );
    }
  }

  /// Refresh categories from database (used after CRUD operations)
  Future<void> _refreshCategoriesFromDatabase() async {
    try {
      debugPrint(
        '[CategoryPickerWidget][_refreshCategoriesFromDatabase] Refreshing categories from database',
      );

      // Check if widget is still mounted before proceeding
      if (!mounted) {
        debugPrint(
          '[CategoryPickerWidget][_refreshCategoriesFromDatabase] Widget not mounted, skipping refresh',
        );
        return;
      }

      // Clear expansion controllers to prevent reuse issues
      _expansionControllers.clear();
      debugPrint(
        '[CategoryPickerWidget][_refreshCategoriesFromDatabase] Cleared expansion controllers',
      );

      // Clear memory count cache
      _categoryMemoryCount.clear();
      debugPrint(
        '[CategoryPickerWidget][_refreshCategoriesFromDatabase] Cleared memory count cache',
      );

      final categories = await _categoryService.getAllCategoriesHierarchical();

      // Check again if widget is still mounted before updating reactive variables
      if (!mounted) {
        debugPrint(
          '[CategoryPickerWidget][_refreshCategoriesFromDatabase] Widget disposed during refresh, skipping update',
        );
        return;
      }

      _mainCategories.value = categories;

      debugPrint(
        '[CategoryPickerWidget][_refreshCategoriesFromDatabase] Successfully refreshed ${categories.length} main categories',
      );
    } catch (e) {
      debugPrint(
        '[CategoryPickerWidget][_refreshCategoriesFromDatabase] Error refreshing categories: $e',
      );

      if (mounted) {
        // Get.snackbar(
        //   'Refresh Error',
        //   'Failed to refresh place categories: $e',
        //   backgroundColor: Colors.orange,
        //   colorText: Colors.white,
        // );
      }
    }
  }

  // Global refresh notifier for external refresh triggers
  static final RxInt _globalRefreshNotifier = 0.obs;

  /// Handle search input changes
  void _onSearchChanged() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      _isSearching.value = false;
      _searchResults.clear();
      return;
    }

    try {
      _isSearching.value = true;
      debugPrint(
        '[CategoryPickerWidget][_onSearchChanged] Searching for: "$query"',
      );

      final results = await _categoryService.searchCategories(query);
      _searchResults.value = results;

      debugPrint(
        '[CategoryPickerWidget][_onSearchChanged] Found ${results.length} results',
      );
    } catch (e) {
      debugPrint('[CategoryPickerWidget][_onSearchChanged] Search error: $e');
      _searchResults.clear();
    }
  }

  /// Select a category and return to parent
  void _selectCategory(PlaceCategory category) {
    debugPrint(
      '[CategoryPickerWidget][_selectCategory] Selected: ${category.name}',
    );

    // Save to recent subcategories if it's a subcategory
    if (category.isSubcategory) {
      _saveRecentlySelectedSubcategory(category);
    }

    if (widget.allowMultipleSelection) {
      // Multiple selection mode - toggle category selection
      _toggleCategorySelection(category);
    } else {
      // Single selection mode - original behavior
      if (widget.onCategorySelected != null) {
        widget.onCategorySelected!(category);
      } else {
        // Fallback to legacy MemoryController - store with emoji
        final controller = Get.find<MemoryController>();
        controller.selectedCategory.value =
            '${category.emoji} ${category.name}';
      }

      Get.back(result: category);
    }
  }

  /// Toggle category selection for multiple selection mode
  void _toggleCategorySelection(PlaceCategory category) {
    debugPrint(
      '[CategoryPickerWidget][_toggleCategorySelection] Toggling: ${category.name} (isMainCategory: ${category.isMainCategory}, isSubcategory: ${category.isSubcategory})',
    );

    // Determine if the category is currently selected
    bool isSelected;
    if (category.isMainCategory && category.hasSubcategories) {
      // For main categories, check if ALL subcategories are selected
      isSelected = category.subcategories!.every(
        (subcategory) => _selectedCategories.any((c) => c.id == subcategory.id)
      );
    } else {
      // For subcategories, check if this specific category is selected
      isSelected = _selectedCategories.any((c) => c.id == category.id);
    }

    debugPrint(
      '[CategoryPickerWidget][_toggleCategorySelection] Current selection state: $isSelected',
    );

    if (isSelected) {
      // Deselecting
      if (category.isMainCategory && category.hasSubcategories) {
        // If this is a main category, remove all its subcategories
        for (final subcategory in category.subcategories!) {
          _selectedCategories.removeWhere((c) => c.id == subcategory.id);
          debugPrint(
            '[CategoryPickerWidget][_toggleCategorySelection] Removed subcategory: ${subcategory.name}',
          );
        }
        debugPrint(
          '[CategoryPickerWidget][_toggleCategorySelection] Deselected main category: ${category.name} (removed all subcategories)',
        );
      } else {
        // For subcategories, remove them directly
        _selectedCategories.removeWhere((c) => c.id == category.id);
        debugPrint(
          '[CategoryPickerWidget][_toggleCategorySelection] Removed: ${category.name}',
        );
      }
    } else {
      // Selecting
      if (category.isMainCategory && category.hasSubcategories) {
        // If this is a main category, add all its subcategories (not the main category itself)
        for (final subcategory in category.subcategories!) {
          if (!_selectedCategories.any((c) => c.id == subcategory.id)) {
            _selectedCategories.add(subcategory);
            debugPrint(
              '[CategoryPickerWidget][_toggleCategorySelection] Added subcategory: ${subcategory.name}',
            );
          }
        }
        debugPrint(
          '[CategoryPickerWidget][_toggleCategorySelection] Selected main category: ${category.name} (added ${category.subcategories!.length} subcategories)',
        );
      } else {
        // For subcategories, add them directly
        _selectedCategories.add(category);
        debugPrint(
          '[CategoryPickerWidget][_toggleCategorySelection] Added: ${category.name}',
        );

        // Save to recent subcategories
        _saveRecentlySelectedSubcategory(category);
      }
    }

    debugPrint(
      '[CategoryPickerWidget][_toggleCategorySelection] Total selected after toggle: ${_selectedCategories.length}',
    );
    debugPrint(
      '[CategoryPickerWidget][_toggleCategorySelection] Selected categories: ${_selectedCategories.map((c) => c.name).join(", ")}',
    );
  }

  /// Find the main category for a given subcategory
  PlaceCategory? _findMainCategoryForSubcategory(PlaceCategory subcategory) {
    for (final mainCategory in _mainCategories) {
      if (mainCategory.subcategories != null) {
        for (final sub in mainCategory.subcategories!) {
          if (sub.id == subcategory.id) {
            return mainCategory;
          }
        }
      }
    }
    return null;
  }

  /// Check if all subcategories of a main category are selected
  bool _areAllSubcategoriesSelected(PlaceCategory mainCategory) {
    if (!mainCategory.hasSubcategories) return false;

    for (final subcategory in mainCategory.subcategories!) {
      if (!_selectedCategories.any((c) => c.id == subcategory.id)) {
        return false;
      }
    }
    return true;
  }

  /// Check if a main category is selected (meaning all its subcategories are selected)
  bool _isMainCategorySelected(PlaceCategory mainCategory) {
    return _selectedCategories.any((c) => c.id == mainCategory.id);
  }

  /// Handle done button press for multiple selection mode
  void _onDonePressed() {
    // Filter to only return subcategories (not main categories)
    final subcategoriesOnly = _selectedCategories.where((c) => c.isSubcategory).toList();

    debugPrint(
      '[CategoryPickerWidget][_onDonePressed] Total in _selectedCategories: ${_selectedCategories.length}',
    );
    debugPrint(
      '[CategoryPickerWidget][_onDonePressed] Returning ${subcategoriesOnly.length} subcategories only',
    );
    debugPrint(
      '[CategoryPickerWidget][_onDonePressed] Subcategories: ${subcategoriesOnly.map((c) => c.name).join(", ")}',
    );

    if (widget.onMultipleCategoriesSelected != null) {
      widget.onMultipleCategoriesSelected!(subcategoriesOnly);
    }

    Get.back(result: subcategoriesOnly);
  }

  /// Toggle expansion state of a main category
  void _toggleCategoryExpansion(int categoryId) {
    _expandedCategories[categoryId] =
        !(_expandedCategories[categoryId] ?? false);
  }

  /// Start inline adding for a category
  void _startInlineAdding(int categoryId) {
    // Expand the category if not already expanded
    // final isCurrentlyExpanded = _expandedCategories[categoryId] ?? false;
    // if (!isCurrentlyExpanded) {
    //   final controller = _expansionControllers[categoryId];
    //   if (controller != null && !controller.isExpanded) {
    //     controller.expand();
    //   }
    // }

    // Show popup for adding subcategory
    Get.dialog(
      AddPlaceCategoryPopupForCategoryPicker(
        parentCategoryId: categoryId,
        isMainCategory: false,
        onCategoryAdded: (category) async {
          // Refresh categories from database
          await _refreshCategoriesFromDatabase();
          _globalRefreshNotifier.value = DateTime.now().millisecondsSinceEpoch;
        },
      ),
      barrierDismissible: false,
    );
  }

  /// Helper method to enable adding mode
  void _enableAddingMode(int categoryId) {
    _addingToCategory[categoryId] = true;

    // Initialize controllers
    _inlineNameControllers[categoryId] = TextEditingController();
    _inlineEmojiControllers[categoryId] = TextEditingController(text: '');
  }

  /// Cancel inline adding
  void _cancelInlineAdding(int categoryId) {
    _addingToCategory[categoryId] = false;
    _inlineNameControllers[categoryId]?.dispose();
    _inlineEmojiControllers[categoryId]?.dispose();
    _inlineNameControllers.remove(categoryId);
    _inlineEmojiControllers.remove(categoryId);
  }

  /// Start inline adding for main category
  void _startInlineAddingMainCategory() {
    // Show popup for adding main category
    Get.dialog(
      AddPlaceCategoryPopupForCategoryPicker(
        isMainCategory: true,
        onCategoryAdded: (category) async {
          // Refresh categories from database
          await _refreshCategoriesFromDatabase();
          _globalRefreshNotifier.value = DateTime.now().millisecondsSinceEpoch;
        },
      ),
      barrierDismissible: false,
    );
  }

  /// Cancel inline adding for main category
  void _cancelInlineAddingMainCategory() {
    _addingMainCategory.value = false;
    _mainCategoryNameController.clear();
  }

  /// Save inline added main category
  Future<void> _saveInlineMainCategory() async {
    final name = _mainCategoryNameController.text.trim();
    final emoji = '📍'; // Default emoji for place categories

    // Validate that name is provided
    if (name.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please enter a Place category name',
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
      return;
    }

    try {
      debugPrint(
        '[CategoryPickerWidget][_saveInlineMainCategory] Adding main category: $name ($emoji)',
      );

      final newCategory = await _categoryService.addCustomCategory(
        name: name,
        emoji: emoji,
        parentId: null, // Main category has no parent
      );

      if (newCategory != null) {
        // Clean up the inline adding state
        _cancelInlineAddingMainCategory();

        // Refresh categories from database to show the new addition
        await _refreshCategoriesFromDatabase();

        // Also trigger global refresh for any other category pickers that might be open
        _globalRefreshNotifier.value = DateTime.now().millisecondsSinceEpoch;

       
        debugPrint(
          '[CategoryPickerWidget][_saveInlineMainCategory] Successfully added main category: ${newCategory.id}',
        );
      } else {
        Get.snackbar(
          'Error',
          'Failed to add Place Category',
          backgroundColor: Colors.red,        duration: const Duration(seconds: 2),

          colorText: Colors.white,
        );
      }
    } catch (e) {
      debugPrint('[CategoryPickerWidget][_saveInlineMainCategory] Error: $e');
      Get.snackbar(
        'Error',
        'Failed to add Place Category: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
    }
  }

  /// Start inline editing for a subcategory
  void _startInlineEditing(PlaceCategory category) {
    if (category.id == null) return;

    // Show popup for editing subcategory
    Get.dialog(
      AddPlaceCategoryPopup(
        shouldOnlyShowEditSubCategory: true,
        fromMemoryView: true, // Enable parent category dropdown
        editCategory: category,
        onCategoryAdded: (updatedCategory) async {
          // Update the category in recents list if it exists
          await _updateCategoryInRecents(category.id!, updatedCategory);

          // Refresh categories from database
          await _refreshCategoriesFromDatabase();
          _globalRefreshNotifier.value = DateTime.now().millisecondsSinceEpoch;
        },
      ),
      barrierDismissible: false,
    );
  }

  /// Cancel inline editing
  void _cancelInlineEditing(int categoryId) {
    _editingCategory[categoryId] = false;
    _editNameControllers[categoryId]?.dispose();
    _editEmojiControllers[categoryId]?.dispose();
    _editNameControllers.remove(categoryId);
    _editEmojiControllers.remove(categoryId);
  }

  /// Save inline edited subcategory
  Future<void> _saveInlineEditedSubcategory(int categoryId) async {
    final nameController = _editNameControllers[categoryId];
    final emojiController = _editEmojiControllers[categoryId];

    if (nameController == null || emojiController == null) return;

    final name = nameController.text.trim();
    final emoji = emojiController.text.trim();

    // Validate that both name and emoji are provided
    if (name.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please enter a Place category',
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
      return;
    }

    if (emoji.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please select an icon',
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
      return;
    }

    try {
      debugPrint('[CategoryPickerWidget][_saveInlineEditedSubcategory] Updating: $name ($emoji)');

      final success = await _categoryService.updateCategory(
        categoryId: categoryId,
        name: name,
        emoji: emoji,
      );

      if (success) {
        // Clean up the inline editing state
        _cancelInlineEditing(categoryId);

        // Refresh categories from database to show the updated category
        await _refreshCategoriesFromDatabase();

        // Also trigger global refresh for any other category pickers that might be open
        _globalRefreshNotifier.value = DateTime.now().millisecondsSinceEpoch;

        // Get.snackbar(
        //   'Success',
        //   'Place "$name" updated successfully!',
        //   backgroundColor: Colors.green,
        //   colorText: Colors.white,
        // );
      } else {
        Get.snackbar(
          'Error',
          'Failed to update Place',
          backgroundColor: Colors.red,
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
      }
    } catch (e) {
      debugPrint('[CategoryPickerWidget][_saveInlineEditedSubcategory] Error: $e');
      Get.snackbar(
        'Error',
        'Failed to update Place: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
    }
  }

  /// Save recently selected subcategory
  Future<void> _saveRecentlySelectedSubcategory(PlaceCategory subcategory) async {
    try {
      // Only save subcategories (not main categories)
      if (!subcategory.isSubcategory) return;

      final prefs = await SharedPreferences.getInstance();

      // Get existing recent subcategories
      final existingJson = prefs.getString(_recentSubcategoriesKey);
      List<Map<String, dynamic>> recentList = [];

      if (existingJson != null) {
        final decoded = json.decode(existingJson) as List;
        recentList = decoded.cast<Map<String, dynamic>>();
      }

      // Create subcategory data map with all necessary information
      final subcategoryData = {
        'id': subcategory.id,
        'name': subcategory.name,
        'emoji': subcategory.emoji,
        'parentId': subcategory.parentId,
        'order': subcategory.order,
        'isCustom': subcategory.isCustom,
        'createdAt': subcategory.createdAt.toIso8601String(),
        'updatedAt': subcategory.updatedAt.toIso8601String(),
        'selectedAt': DateTime.now().toIso8601String(), // Track when it was selected
      };

      // Remove if already exists (to move it to front)
      recentList.removeWhere((item) => item['id'] == subcategory.id);

      // Add to front of list
      recentList.insert(0, subcategoryData);

      // Keep only the most recent items (max 6)
      if (recentList.length > _maxRecentItems) {
        recentList = recentList.take(_maxRecentItems).toList();
      }

      // Save back to preferences
      await prefs.setString(_recentSubcategoriesKey, json.encode(recentList));

      debugPrint('[CategoryPickerWidget] Saved recent subcategory: ${subcategory.name} (${subcategory.id})');
    } catch (e) {
      debugPrint('[CategoryPickerWidget] Error saving recent subcategory: $e');
    }
  }

  /// Get recently selected subcategories
  static Future<List<PlaceCategory>> getRecentlySelectedSubcategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString(_recentSubcategoriesKey);

      if (existingJson == null) return [];

      final decoded = json.decode(existingJson) as List;
      final recentList = decoded.cast<Map<String, dynamic>>();

      // Convert back to PlaceCategory objects
      final categories = <PlaceCategory>[];
      for (final item in recentList) {
        try {
          final category = PlaceCategory(
            id: item['id'],
            name: item['name'],
            emoji: item['emoji'],
            parentId: item['parentId'],
            order: item['order'] ?? 0,
            isCustom: item['isCustom'] ?? false,
            createdAt: DateTime.parse(item['createdAt']),
            updatedAt: DateTime.parse(item['updatedAt']),
          );
          categories.add(category);
        } catch (e) {
          debugPrint('[CategoryPickerWidget] Error parsing recent subcategory: $e');
        }
      }

      return categories;
    } catch (e) {
      debugPrint('[CategoryPickerWidget] Error getting recent subcategories: $e');
      return [];
    }
  }

  /// Update a category in the recents list (when edited)
  Future<void> _updateCategoryInRecents(int categoryId, PlaceCategory updatedCategory) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Get existing recent categories
      List<PlaceCategory> recentCategories = await getRecentlySelectedSubcategories();

      // Find and update the category if it exists in recents
      final index = recentCategories.indexWhere((cat) => cat.id == categoryId);
      if (index != -1) {
        // Replace with updated category
        recentCategories[index] = updatedCategory;

        // Convert to the same format for storage
        final List<Map<String, dynamic>> recentList = recentCategories.map((cat) => {
          'id': cat.id,
          'name': cat.name,
          'emoji': cat.emoji,
          'parentId': cat.parentId,
          'order': cat.order,
          'isCustom': cat.isCustom,
          'createdAt': cat.createdAt.toIso8601String(),
          'updatedAt': cat.updatedAt.toIso8601String(),
        }).toList();

        await prefs.setString(_recentSubcategoriesKey, json.encode(recentList));

        debugPrint('[CategoryPickerWidget] Updated category in recents: ${updatedCategory.emoji} ${updatedCategory.name} (${updatedCategory.id})');
      } else {
        debugPrint('[CategoryPickerWidget] Category not found in recents, skipping update');
      }
    } catch (e) {
      debugPrint('[CategoryPickerWidget] Error updating category in recents: $e');
    }
  }

  /// Clear recently selected subcategories
  static Future<void> clearRecentlySelectedSubcategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentSubcategoriesKey);
      debugPrint('[CategoryPickerWidget] Cleared recent subcategories');
    } catch (e) {
      debugPrint('[CategoryPickerWidget] Error clearing recent subcategories: $e');
    }
  }

  /// Remove a specific category from recent subcategories
  static Future<void> removeFromRecentSubcategories(int categoryId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingJson = prefs.getString(_recentSubcategoriesKey);

      if (existingJson == null) return;

      final decoded = json.decode(existingJson) as List;
      List<Map<String, dynamic>> recentList = decoded.cast<Map<String, dynamic>>();

      // Remove the category with the given ID
      recentList.removeWhere((item) => item['id'] == categoryId);

      // Save back to preferences
      await prefs.setString(_recentSubcategoriesKey, json.encode(recentList));

      debugPrint('[CategoryPickerWidget] Removed category ID $categoryId from recent subcategories');
    } catch (e) {
      debugPrint('[CategoryPickerWidget] Error removing category from recents: $e');
    }
  }

  /// Example method to demonstrate how to use recent subcategories
  /// Call this from other screens to get and display recent subcategories
  static Future<void> printRecentSubcategories() async {
    final recentSubcategories = await getRecentlySelectedSubcategories();
    debugPrint('[CategoryPickerWidget] Recent subcategories (${recentSubcategories.length}):');
    for (final subcategory in recentSubcategories) {
      debugPrint('  - ${subcategory.emoji} ${subcategory.name} (ID: ${subcategory.id}, Parent: ${subcategory.parentId})');
    }
  }

  /// Save inline added subcategory
  Future<void> _saveInlineSubcategory(int parentCategoryId) async {
    final nameController = _inlineNameControllers[parentCategoryId];
    final emojiController = _inlineEmojiControllers[parentCategoryId];

    if (nameController == null || emojiController == null) return;

    final name = nameController.text.trim();
    final emoji = emojiController.text.trim();

    // Validate that both name and emoji are provided
    if (name.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please enter a place name',
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
      return;
    }

    if (emoji.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please select an icon',
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
      return;
    }

    try {
      debugPrint(
        '[CategoryPickerWidget][_saveInlineSubcategory] Adding: $name ($emoji)',
      );

      final newCategory = await _categoryService.addCustomCategory(
        name: name,
        emoji: emoji,
        parentId: parentCategoryId,
      );

      if (newCategory == null) {
        Get.snackbar(
          'Error',
          'Failed to add Place',
          backgroundColor: Colors.red,
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
        return;
      } else if (newCategory.id == -1) {
        // Duplicate subcategory name
        Get.snackbar(
          'Duplicate Place',
          'Place with this name already exists.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
        return;
      } else if (newCategory.id == -4) {
        // Subcategory name conflicts with parent category
        Get.snackbar(
          'Name Conflict',
          'This name is already used by the Place Category.',
          backgroundColor: Colors.orange,
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
        return;
      }

      // Clean up the inline adding state
      _cancelInlineAdding(parentCategoryId);

      // Refresh categories from database to show the new addition
      await _refreshCategoriesFromDatabase();

      // Also trigger global refresh for any other category pickers that might be open
      _globalRefreshNotifier.value = DateTime.now().millisecondsSinceEpoch;

      // Get.snackbar(
      //   'Success',
      //   'Place "$name" added successfully!',
      //   backgroundColor: Colors.green,
      //   colorText: Colors.white,
      // );

      debugPrint(
        '[CategoryPickerWidget][_saveInlineSubcategory] Successfully added subcategory: ${newCategory.id}',
      );
    } catch (e) {
      debugPrint('[CategoryPickerWidget][_saveInlineSubcategory] Error: $e');
      // Get.snackbar(
      //   'Error',
      //   'Failed to add place: $e',
      //   backgroundColor: Colors.red,
      //   colorText: Colors.white,
      // );
    }
  }

  // /// Add a new custom category
  Future<void> _addNewCategory(String name, String emoji, int? parentId) async {
    if (name.isEmpty || emoji.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please enter both name and icon',
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
      return;
    }

    try {
      debugPrint(
        '[CategoryPickerWidget][_addNewCategory] Adding: $name ($emoji)',
      );

      final newCategory = await _categoryService.addCustomCategory(
        name: name,
        emoji: emoji,
        parentId: parentId,
      );

      if (newCategory != null) {
        Get.back(); // Close dialog

        // Refresh categories from database to show the new addition
        debugPrint(
          '[CategoryPickerWidget][_addNewCategory] Refreshing categories from database after addition',
        );
        await _refreshCategoriesFromDatabase();

        // Also trigger global refresh for any other category pickers that might be open
        debugPrint(
          '[CategoryPickerWidget][_addNewCategory] Triggering global refresh for other instances',
        );
        _globalRefreshNotifier.value = DateTime.now().millisecondsSinceEpoch;

        // Get.snackbar(
        //   'Success',
        //   'Place "$name" added successfully!',
        //   backgroundColor: Colors.green,
        //   colorText: Colors.white,
        // );

        debugPrint(
          '[CategoryPickerWidget][_addNewCategory] Successfully added category: ${newCategory.id}',
        );
      } else {
        Get.snackbar(
          'Error',
          'Failed to add Place',
          backgroundColor: Colors.red,
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
      }
    } catch (e) {
      debugPrint('[CategoryPickerWidget][_addNewCategory] Error: $e');
      Get.snackbar(
        'Error',
        'Failed to add Place',
        backgroundColor: Colors.red,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
    }
  }

  /// Show edit category dialog - now uses AddPlaceCategoryPopup
  void _showEditCategoryDialog(PlaceCategory category) {
    // Allow editing of all categories (both custom and predefined)
    debugPrint(
      '[CategoryPickerWidget][_showEditCategoryDialog] Opening edit popup for: ${category.name} (${category.isCustom ? 'Custom' : 'Predefined'})',
    );

    // Show popup for editing category
    Get.dialog(
      AddPlaceCategoryPopupForCategoryPicker(
        editCategory: category,
        isEditingMainCategory: true,
        onCategoryAdded: (updatedCategory) async {
          // Refresh categories from database to show the updated category
          await _refreshCategoriesFromDatabase();

          // Also trigger global refresh for any other category pickers that might be open
          _globalRefreshNotifier.value = DateTime.now().millisecondsSinceEpoch;
        },
      ),
      barrierDismissible: false,
    );
  }

  /// Update an existing category
  Future<void> _updateCategory(
    int categoryId,
    String name,
    String emoji,
  ) async {
    if (name.isEmpty || emoji.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please enter both name and icon',
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
      return;
    }

    try {
      debugPrint(
        '[CategoryPickerWidget][_updateCategory] Updating category ID: $categoryId',
      );

      final success = await _categoryService.updateCategory(
        categoryId: categoryId,
        name: name,
        emoji: emoji,
      );

      if (success) {
        Get.back(); // Close dialog

        // Refresh categories from database to show the update
        debugPrint(
          '[CategoryPickerWidget][_updateCategory] Refreshing categories from database after update',
        );
        await _refreshCategoriesFromDatabase();

        // Also trigger global refresh for any other category pickers that might be open
        debugPrint(
          '[CategoryPickerWidget][_updateCategory] Triggering global refresh for other instances',
        );
        _globalRefreshNotifier.value = DateTime.now().millisecondsSinceEpoch;

        // Get.snackbar(
        //   'Success',
        //   'Place updated successfully!',
        //   backgroundColor: Colors.green,
        //   colorText: Colors.white,
        // );
      } else {
        Get.snackbar(
          'Error',
          'Failed to update Place',
          backgroundColor: Colors.red,
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
      }
    } catch (e) {
      debugPrint('[CategoryPickerWidget][_updateCategory] Error: $e');
      Get.snackbar(
        'Error',
        'Failed to update Place: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
    }
  }

  /// Get memory count for a category
  Future<int> _getMemoryCountForCategory(PlaceCategory category) async {
    // Check cache first
    if (_categoryMemoryCount.containsKey(category.id)) {
      return _categoryMemoryCount[category.id]!;
    }

    // Fetch from database
    final count = await _categoryService.getMemoryCountForCategoryByEmojiAndName(
      category.emoji,
      category.name,
    );

    // Cache the result
    _categoryMemoryCount[category.id!] = count;

    return count;
  }

  /// Delete a category (with or without confirmation based on memory count)
  Future<void> _handleDeleteCategory(PlaceCategory category) async {
    // Check if category has associated memories
    final memoryCount = await _getMemoryCountForCategory(category);

    if (memoryCount > 0) {
      // Show cannot delete dialog
      _showCannotDeleteDialog(
        category.name,
        memoryCount,
        category.parentId == null,
      );
    } else {
      // Delete directly without confirmation
      //
      await _deleteCategory(category.id!);
    }
  }

  /// Delete a custom category
  Future<void> _deleteCategory(int categoryId) async {
    try {
      debugPrint(
        '[CategoryPickerWidget][_deleteCategory] Deleting category ID: $categoryId',
      );

      final result = await _categoryService.deleteCategory(categoryId);

      if (result == true) {
        // Successfully deleted
        // Get.back(); // Close confirmation dialog
        // Get.back(); // Close edit dialog

        // Remove from recent subcategories
        await removeFromRecentSubcategories(categoryId);

        // Refresh categories from database to show the deletion
        debugPrint(
          '[CategoryPickerWidget][_deleteCategory] Refreshing categories from database after deletion',
        );
        await _refreshCategoriesFromDatabase();

      
      } else if (result == null) {
        // Cannot delete - has memories
        Get.back(); // Close confirmation dialog

        // Show error dialog with memory count
        final category = await _categoryService.getCategoryById(categoryId);
        final memoryCount =
            category != null
                ? await _categoryService
                    .getMemoryCountForCategoryByEmojiAndName(
                      category.emoji,
                      category.name,
                    )
                : 0;

        _showCannotDeleteDialog(category?.name ?? 'Unknown', memoryCount, category?.parentId == null);
      } else {
        // Failed to delete
        Get.snackbar(
          'Error',
          'Failed to delete Place',
          backgroundColor: Colors.red,
          colorText: Colors.white,        duration: const Duration(seconds: 2),

        );
      }
    } catch (e) {
      debugPrint('[CategoryPickerWidget][_deleteCategory] Error: $e');
      Get.snackbar(
        'Error',
        'Failed to delete Place: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,        duration: const Duration(seconds: 2),

      );
    }
  }

  /// Show dialog when category cannot be deleted due to existing memories
  void _showCannotDeleteDialog(String categoryName, int memoryCount, bool isMainCategory) {
    final uiController = Get.find<UiController>();
    final categoryType = isMainCategory ? 'Place Category' : 'Place';

    Get.dialog(
      AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        backgroundColor:
            uiController.darkMode.value ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            Text(
              'Cannot Delete $categoryType',
              style: gfonts.GoogleFonts.kumbhSans(
                color:
                    uiController.darkMode.value ? Colors.white : Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The $categoryType "$categoryName" cannot be deleted because it is being used by $memoryCount ${memoryCount == 1 ? 'memory' : 'memories'}.',
              style: gfonts.GoogleFonts.kumbhSans(
                color:
                    uiController.darkMode.value
                        ? Colors.white70
                        : Colors.grey[700],
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'To delete this $categoryType, first change the Place of all memories that use it, or delete those memories.',
                      style: gfonts.GoogleFonts.kumbhSans(color: Colors.orange[700], fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              'OK',
              style: gfonts.GoogleFonts.kumbhSans(
                color: uiController.currentMainColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Handle quick add from search
  void _quickAddFromSearch() {

    final query = _searchController.text.trim();
    
    if (query.isEmpty) return;

  }

  /// Show emoji picker as bottom sheet
  Future<void> _showEmojiPicker(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final uiController = Get.find<UiController>();

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      builder:
          (context) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color:
                    uiController.darkMode.value
                        ? const Color(0xFF1E1E1E)
                        : Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color:
                          uiController.darkMode.value
                              ? Colors.white30
                              : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '',
                          style: gfonts.GoogleFonts.kumbhSans(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color:
                                uiController.darkMode.value
                                    ? Colors.white
                                    : Colors.black87,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.close,
                            color:
                                uiController.darkMode.value
                                    ? Colors.white70
                                    : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Emoji Picker with custom cursor color theme
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        // inputDecorationTheme:
                        // theme
                        textSelectionTheme: TextSelectionThemeData(
                          cursorColor: uiController.currentMainColor,
                        ),
                      ),
                      child: EmojiPicker(
                        // theme: uiController.darkMode.value ? DarkMode : LightMode,
                        onEmojiSelected: (category, emoji) {
                          // Update the controller with selected emoji
                          controller.text = emoji.emoji;
                          // Close the bottom sheet
                          Navigator.pop(context);
                          // Force a rebuild of the parent dialog to show the new emoji
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        config: Config(
                          height: 256,
                          checkPlatformCompatibility: true,
                          emojiViewConfig: EmojiViewConfig(
                            backgroundColor:
                                uiController.darkMode.value
                                    ? const Color(0xFF1E1E1E)
                                    : Colors.white,
                            columns: 7,
                            emojiSizeMax: 32,
                          ),
                          categoryViewConfig: CategoryViewConfig(
                            indicatorColor: uiController.currentMainColor,
                            iconColorSelected: uiController.currentMainColor,
                            backgroundColor:
                                uiController.darkMode.value
                                    ? const Color(0xFF2E2E2E)
                                    : Colors.grey[100]!,
                          ),
                          bottomActionBarConfig: BottomActionBarConfig(
                            buttonColor: uiController.currentMainColor,
                            backgroundColor:
                                uiController.darkMode.value
                                    ? const Color(0xFF2E2E2E)
                                    : Colors.grey[100]!,
                          ),
                          searchViewConfig: SearchViewConfig(
                            backgroundColor:
                                uiController.darkMode.value
                                    ? const Color(0xFF1E1E1E)
                                    : Colors.white,
                            buttonIconColor:
                                !uiController.darkMode.value
                                    ? const Color(0xFF2E2E2E)
                                    : Colors.grey[100]!,
                            hintText: 'Search icons...',
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }

  /// Fix category inconsistencies (debug method)
  Future<void> _fixCategoryInconsistencies() async {
    final uiController = Get.find<UiController>();

    // Show loading dialog
    Get.dialog(
      AlertDialog(
        backgroundColor:
            uiController.darkMode.value
                ? const Color(0xFF1E1E1E)
                : Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Fixing Place inconsistencies...',
              style: gfonts.GoogleFonts.kumbhSans(
                color:
                    uiController.darkMode.value ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
      barrierDismissible: false,
    );

    try {
      // Fix the specific School → School1 issue
      await _categoryService.fixSchoolToSchool1Issue();

      // Fix all other inconsistencies
      final totalFixed = await _categoryService.fixAllCategoryInconsistencies();

      // Close loading dialog
      Get.back();

      // Refresh the category picker to show updated categories
      await _refreshCategoriesFromDatabase();

      // Show result dialog
      Get.dialog(
        AlertDialog(
          backgroundColor:
              uiController.darkMode.value
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Fix Complete',
                  style: gfonts.GoogleFonts.kumbhSans(
                    color:
                        uiController.darkMode.value
                            ? Colors.white
                            : Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Fixed $totalFixed Place inconsistencies.\n\nMemories and Place picker now show the correct updated Place names.',
            style: gfonts.GoogleFonts.kumbhSans(
              color:
                  uiController.darkMode.value
                      ? Colors.white70
                      : Colors.grey[700],
              fontSize: 16,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: Text(
                'OK',
                style: gfonts.GoogleFonts.kumbhSans(
                  color: uiController.currentMainColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      // Close loading dialog
      Get.back();

      // Show error dialog
      Get.dialog(
        AlertDialog(
          backgroundColor:
              uiController.darkMode.value
                  ? const Color(0xFF1E1E1E)
                  : Colors.white,
          title: Row(
            children: [
              Icon(Icons.error, color: Colors.red, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Fix Failed',
                  style: gfonts.GoogleFonts.kumbhSans(
                    color:
                        uiController.darkMode.value
                            ? Colors.white
                            : Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'An error occurred while fixing Place inconsistencies:\n\n$e',
            style: gfonts.GoogleFonts.kumbhSans(
              color:
                  uiController.darkMode.value
                      ? Colors.white70
                      : Colors.grey[700],
              fontSize: 16,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Get.back(),
              child: Text(
                'OK',
                style: gfonts.GoogleFonts.kumbhSans(
                  color: uiController.currentMainColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return PopScope(
      canPop: !widget.allowMultipleSelection,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.allowMultipleSelection) {
          // Call _onDonePressed even when selection is empty to properly clear filters
          _onDonePressed();
        }
      },
      child: Scaffold(
              appBar: AppBar(
          leading:
              widget.allowMultipleSelection
                  ? Obx(
                    () => IconButton(
                      onPressed: _onDonePressed,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: _selectedCategories.isNotEmpty ? 'Done' : 'Back',
                    ),
                  )
                  : null,
          title: Obx(
            () => Text(
              widget.allowMultipleSelection
                  ? '📍 Places'
                  : '📍 Places',
              style: gfonts.GoogleFonts.kumbhSans(
                color:
                    uiController.darkMode.value ? Colors.white : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              maxLines: null, // Allow unlimited lines
              overflow: TextOverflow.visible, // Show all text
              textAlign: TextAlign.center, // Keep centered
            ),
          ),
          centerTitle: true,
          backgroundColor: uiController.currentMainColor,
          foregroundColor:
              uiController.darkMode.value ? Colors.white : Colors.white,
          elevation: 1,
          iconTheme: IconThemeData(
            color: uiController.darkMode.value ? Colors.white : Colors.white,
          ),

          actions: [
            // Hide add button when in filter mode
            if (!widget.allowMultipleSelection)
              // Add main category button
              IconButton(
                onPressed: _startInlineAddingMainCategory,
                icon: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                  child: Image.asset(
                    'assets/images/ic_add.png',
                    width: 25,
                    height: 25,
                  ),
                ),
                tooltip: 'Add Place Category',
              ),
          ],
        ),
        body: Column(
          children: [
            // Selection indicator when in filter mode
            if (widget.allowMultipleSelection)
              Obx(() {
                // Count only subcategories (exclude main categories)
                final subcategoryCount = _selectedCategories.where((c) => c.isSubcategory).length;
                return Center(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text(
                      subcategoryCount == 0
                          ? '0 selected'
                          : '$subcategoryCount ${subcategoryCount == 1 ? 'Place' : 'Places'} selected',
                      textAlign: TextAlign.center,
                      style: gfonts.GoogleFonts.kumbhSans(
                        color: uiController.currentMainColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }),

            // Inline add main category widget (removed - now using popup)

            // Search Field
            // Container(
            //   color:
            //       uiController.darkMode.value
            //           ? Colors.white.withValues(alpha: 0.06)
            //           : uiController.getLightModeBackgroundColor(
            //                 uiController.mainColor.value,
            //               ) ??
            //               const Color(0xFFF8FBFF),
            //   child: Padding(
            //     padding: const EdgeInsets.all(16.0),
            //     child: TextField(
            //       controller: _searchController,
            //       decoration: InputDecoration(
            //         hintText: 'Search or add new category...',
            //         hintStyle: TextStyle(
            //           color:
            //               uiController.darkMode.value
            //                   ? Colors.white.withValues(alpha: 0.6)
            //                   : Colors.grey[600],
            //         ),
            //         prefixIcon: Icon(
            //           Icons.search,
            //           color:
            //               uiController.darkMode.value
            //                   ? Colors.white.withValues(alpha: 0.7)
            //                   : Colors.grey[600],
            //         ),
            //         suffixIcon: null,
            //         border: OutlineInputBorder(
            //           borderRadius: BorderRadius.circular(12),
            //           borderSide: BorderSide(
            //             color:
            //                 uiController.darkMode.value
            //                     ? Colors.white.withValues(alpha: 0.3)
            //                     : Colors.grey.shade300,
            //           ),
            //         ),
            //         enabledBorder: OutlineInputBorder(
            //           borderRadius: BorderRadius.circular(12),
            //           borderSide: BorderSide(
            //             color:
            //                 uiController.darkMode.value
            //                     ? Colors.white.withValues(alpha: 0.3)
            //                     : Colors.grey.shade300,
            //           ),
            //         ),
            //         focusedBorder: OutlineInputBorder(
            //           borderRadius: BorderRadius.circular(12),
            //           borderSide: BorderSide(
            //             color:
            //                 uiController.darkMode.value
            //                     ? Colors.white.withValues(alpha: 0.5)
            //                     : (uiController.primaryColor ?? Colors.blue),
            //             width: 2,
            //           ),
            //         ),
            //         filled: true,
            //         fillColor:
            //             uiController.darkMode.value
            //                 ? Colors.black
            //                 : Colors.white,
            //       ),
            //       style: TextStyle(
            //         color:
            //             uiController.darkMode.value
            //                 ? Colors.white
            //                 : Colors.black,
            //       ),
            //     ),
            //   ),
            // ),
        
            // Categories List
            Expanded(
              child: Obx(() {
                if (_isLoading.value) {
                  return const Center(child: CircularProgressIndicator());
                }
        
                // Show search results when searching
                if (_isSearching.value) {
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _buildSearchResults(),
                  );
                }
        
                // Show hierarchical categories when not searching
                return Container(
                  color:
                       uiController.darkMode.value
              ? Colors.black
              :                    uiController.currentMainColor.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: _buildHierarchicalCategories(),
                  ),
                );
              }),
            ),
          ],
        ),
        // floatingActionButton: FloatingActionButton(
        //   onPressed: () => _showAddCategoryDialog(),
        //   backgroundColor: uiController.currentMainColor,
        //   tooltip: 'Add New Category',
        //   child: const Icon(Icons.add, color: Colors.white),
        // ),
      ),
    );
  }

  /// Build search results view
  Widget _buildSearchResults() {
    final uiController = Get.find<UiController>();

    if (_searchResults.isEmpty) {
      return Container(
        color:
            uiController.darkMode.value
                ? Colors.white.withValues(alpha: 0.06)
                : uiController.getLightModeBackgroundColor(
                  uiController.mainColor.value,
                ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color:
                    uiController.darkMode.value
                        ? Colors.white.withValues(alpha: 0.4)
                        : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No Places match your search',
                style: gfonts.GoogleFonts.kumbhSans(
                  color:
                      uiController.darkMode.value
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              // ElevatedButton.icon(
              //   onPressed: _quickAddFromSearch,
              //   icon: const Icon(Icons.add),
              //   label: Text('Add "${_searchController.text}"'),
              //   style: ElevatedButton.styleFrom(
              //     backgroundColor: uiController.currentMainColor,
              //     foregroundColor: Colors.white,
              //     shape: RoundedRectangleBorder(
              //       borderRadius: BorderRadius.circular(12),
              //     ),
              //   ),
              // ),
            ],
          ),
        ),
      );
    }

    return Container(
      color:
          uiController.darkMode.value
              ? Colors.white.withValues(alpha: 0.06)
              : uiController.getLightModeBackgroundColor(
                uiController.mainColor.value,
              ),
      child: ListView.builder(
        itemCount: _searchResults.length,
        itemBuilder: (context, index) {
          final category = _searchResults[index];
          return _buildCategoryTile(category, isSearchResult: true);
        },
      ),
    );
  }

  /// Build hierarchical categories view
  Widget _buildHierarchicalCategories() {
    final uiController = Get.find<UiController>();

    if (_mainCategories.isEmpty) {
      return Container(
        color:
            uiController.darkMode.value
                ? Colors.white.withValues(alpha: 0.06)
                : uiController.getLightModeBackgroundColor(
                  uiController.mainColor.value,
                ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.category_outlined,
                size: 64,
                color:
                    uiController.darkMode.value
                        ? Colors.white.withValues(alpha: 0.4)
                        : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No Place Categories found',
                style: gfonts.GoogleFonts.kumbhSans(
                  color:
                      uiController.darkMode.value
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              
            ],
          ),
        ),
      );
    }

    return Obx(() {
      // Check if any category is expanded
      final hasExpandedCategory = _expandedCategories.values.any((expanded) => expanded == true);

      return Container(
        // color:
        child: ListView.builder(
          itemCount: _mainCategories.length + (hasExpandedCategory ? 1 : 0),
          itemBuilder: (context, index) {
            // Add spacing at the end if any category is expanded
            if (index == _mainCategories.length) {
              return const SizedBox(height: 15);
            }

            final mainCategory = _mainCategories[index];
            return _buildMainCategoryExpansionTile(mainCategory);
          },
        ),
      );
    });
  }

  /// Build inline add widget for main categories
  Widget _buildInlineAddMainCategoryWidget() {
    final uiController = Get.find<UiController>();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: uiController.darkMode.value
            ? Colors.black
            : uiController.currentMainColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          // Text input field
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: TextSelectionThemeData(
                  cursorColor: uiController.currentMainColor,
                  selectionColor: uiController.currentMainColor.withValues(alpha: 0.3),
                  selectionHandleColor: uiController.currentMainColor,
                ),
              ),
              child: TextField(
                controller: _mainCategoryNameController,
                cursorColor: uiController.currentMainColor,
                style: gfonts.GoogleFonts.kumbhSans(
                  color: uiController.darkMode.value ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'Place Category',
                  hintStyle: gfonts.GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value
                        ? Colors.white.withValues(alpha: 0.6)
                        : Colors.grey[600],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                autofocus: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Cancel button (red cross)
          GestureDetector(
            onTap: _cancelInlineAddingMainCategory,
            child: Container(
              width: 18,
              height: 18,
              child: Image.asset(
                'assets/images/ic_cross.png',
                width: 10,
                height: 10,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Save button (green tick)
          GestureDetector(
            onTap: _saveInlineMainCategory,
            child: Container(
              width: 18,
              height: 18,
              child: Image.asset(
                'assets/images/ic_tick.png',
                width: 10,
                height: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build inline add widget for subcategories
  Widget _buildInlineAddWidget(int parentCategoryId) {
    
    final uiController = Get.find<UiController>();
    final nameController = _inlineNameControllers[parentCategoryId];
    final emojiController = _inlineEmojiControllers[parentCategoryId];

    if (nameController == null || emojiController == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: uiController.darkMode.value
                ? Colors.black
                :                    uiController.currentMainColor.withValues(alpha: 0.1)
,borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          // Emoji picker button
          StatefulBuilder(
            builder: (context, setEmojiState) {
              return GestureDetector(
                onTap: () async {
                  await _showEmojiPicker(context, emojiController);
                  // Update the emoji display after selection
                  setEmojiState(() {});
                },
                child: Container(
                  width: 35,
                  height: 35,
                  decoration: BoxDecoration(
                    color:           (!uiController.darkMode.value
                          ? Colors.white.withValues(alpha: 0.8)
                          : Colors.grey[800]),
                    borderRadius: BorderRadius.circular(6),
                    // border: Border.all(
                      // color: Colors.grey.withValues(alpha: 0.3),
                    // ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Center(
                      child: emojiController.text.isEmpty
                          ? ColorFiltered(
                              colorFilter: ColorFilter.mode(
                              uiController.currentMainColor,
                                BlendMode.srcIn,
                              ),
                              child: Image.asset(
                                'assets/images/ic_add.png',
                                width: 25,
                                height: 25,
                              ),
                            )
                          : Text(
                              emojiController.text,
                              style: gfonts.GoogleFonts.kumbhSans(fontSize: 20),
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          // Name input field
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: TextSelectionThemeData(
                  cursorColor: uiController.currentMainColor,
                  selectionColor: uiController.currentMainColor.withValues(alpha: 0.3),
                  selectionHandleColor: uiController.currentMainColor,
                ),
              ),
              child: TextField(
                controller: nameController,
                cursorColor: uiController.currentMainColor,
                style: gfonts.GoogleFonts.kumbhSans(
                  color: uiController.darkMode.value ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'Place Name',
                  hintStyle: gfonts.GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value
                        ? Colors.white.withValues(alpha: 0.6)
                        : Colors.grey[600],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                autofocus: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Cancel button (red cross)
          GestureDetector(
            onTap: () => _cancelInlineAdding(parentCategoryId),
            child: Container(
              width: 18,
              height: 18,

              child: Image.asset(
                'assets/images/ic_cross.png',
                width: 10,
                height: 10,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Save button (green tick)
          GestureDetector(
            onTap: () => _saveInlineSubcategory(parentCategoryId),
            child: Container(
              width: 18,
              height: 18,
             
              child: Image.asset(
                'assets/images/ic_tick.png',
                width: 10,
                height: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build inline edit widget for subcategories
  Widget _buildInlineEditWidget(int categoryId) {
    final uiController = Get.find<UiController>();
    final nameController = _editNameControllers[categoryId];
    final emojiController = _editEmojiControllers[categoryId];

    if (nameController == null || emojiController == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: 18, // Same as subcategory margin
        vertical: 2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: uiController.darkMode.value
                ? Colors.black
                :                    uiController.currentMainColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(2),
        
      ),
      child: Row(
        children: [
          // Emoji picker button
          StatefulBuilder(
            builder: (context, setEmojiState) {
              return GestureDetector(
                onTap: () async {
                  await _showEmojiPicker(context, emojiController);
                  // Update the emoji display after selection
                  setEmojiState(() {});
                },
                child: Container(
                  width: 35,
                  height: 35,
                  decoration: BoxDecoration(
                   color:    (!uiController.darkMode.value
                          ? Colors.white.withValues(alpha: 0.8)
                          : Colors.grey[800]),
                    borderRadius: BorderRadius.circular(6),
                    // border: Border.all(
                      // color: Colors.grey.withValues(alpha: 0.3),
                    // ),
                                      // borderRadius: BorderRadius.circular(6),
                   
                  ),
                  child: Center(
                    child: emojiController.text.isEmpty
                        ? ColorFiltered(
                            colorFilter: ColorFilter.mode(
                              Colors.grey[600] ?? Colors.grey,
                              BlendMode.srcIn,
                            ),
                            child: Image.asset(
                              'assets/images/ic_add.png',
                              width: 25,
                              height: 25,
                            ),
                          )
                        : Text(
                            emojiController.text,
                            style: gfonts.GoogleFonts.kumbhSans(fontSize: 20),
                          ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 12),
          // Name input field
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                textSelectionTheme: TextSelectionThemeData(
                  cursorColor: uiController.currentMainColor,
                  selectionColor: uiController.currentMainColor.withValues(alpha: 0.3),
                  selectionHandleColor: uiController.currentMainColor,
                ),
              ),
              child: TextField(
                controller: nameController,
                cursorColor: uiController.currentMainColor,
                style: gfonts.GoogleFonts.kumbhSans(
                  color: uiController.darkMode.value ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'Place Name',
                  hintStyle: gfonts.GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value
                        ? Colors.white.withValues(alpha: 0.6)
                        : Colors.grey[600],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
                autofocus: true,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Cancel button (red cross)
          GestureDetector(
            onTap: () => _cancelInlineEditing(categoryId),
            child: Container(
              width: 18,
              height: 18,
              // decoration: BoxDecoration(
                // color: Colors.red.withValues(alpha: 0.1),
                // borderRadius: BorderRadius.circular(16),
              // ),
              child: Image.asset(
                'assets/images/ic_cross.png',
                width: 10,
                height: 10,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Save button (green tick)
          GestureDetector(
            onTap: () => _saveInlineEditedSubcategory(categoryId),
            child: Container(
              width: 18,
              height: 18,
           
              child: Image.asset(
                'assets/images/ic_tick.png',
                width: 10,
                height: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build main category expansion tile
  Widget _buildMainCategoryExpansionTile(PlaceCategory mainCategory) {
    final uiController = Get.find<UiController>();

    // Create or get the expansion controller for this category (outside Obx to avoid recreation)
    final categoryId = mainCategory.id!;
    if (_expansionControllers[categoryId] == null) {
      _expansionControllers[categoryId] = ExpansionTileController();
    }
    final controller = _expansionControllers[categoryId]!;

    return Obx(() {
      final isExpanded = _expandedCategories[mainCategory.id] ?? false;

      // Check if all subcategories are selected (for filter mode)
      final allSubcategoriesSelected = widget.allowMultipleSelection &&
          mainCategory.subcategories != null &&
          mainCategory.subcategories!.isNotEmpty &&
          mainCategory.subcategories!.every((subcategory) =>
              _selectedCategories.any((c) => c.id == subcategory.id));

      // Count selected subcategories
      final selectedSubcategoriesCount = widget.allowMultipleSelection &&
          mainCategory.subcategories != null
          ? mainCategory.subcategories!.where((subcategory) =>
              _selectedCategories.any((c) => c.id == subcategory.id)).length
          : 0;

      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: uiController.darkMode.value ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(2),
          // Add border to entire container when all subcategories are selected (filter mode only)
          border: widget.allowMultipleSelection && allSubcategoriesSelected
              ? Border.all(
                  color: uiController.currentMainColor,
                  width: 2,
                )
              : null,
        ),
        child: Column(
          children: [
            // Grey container with border for the category header
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              decoration: BoxDecoration(
                // Changed background color: white in light mode, grey in dark mode
                color: uiController.darkMode.value
                    ? Colors.grey[900]
                    : Colors.white,
                borderRadius: BorderRadius.circular(2),
                // No border on main category header since we only select subcategories
                border: null,
              ),
              child: ExpansionTile(
                key: ValueKey(mainCategory.id),
                controller: controller,
                initiallyExpanded: isExpanded,
                onExpansionChanged:
                    (expanded) => _toggleCategoryExpansion(mainCategory.id!),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                backgroundColor: Colors.transparent,
                collapsedBackgroundColor: Colors.transparent,
                collapsedShape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
                // Show checkbox on the left when in filter mode
                leading: widget.allowMultipleSelection
                    ? GestureDetector(
                        onTap: () => _selectCategory(mainCategory),
                        child: Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.only(left: 16),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: allSubcategoriesSelected
                                  ? uiController.currentMainColor
                                  : (uiController.darkMode.value
                                      ? Colors.white.withValues(alpha: 0.6)
                                      : Colors.grey[400]!),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(4),
                            color: allSubcategoriesSelected
                                ? uiController.currentMainColor
                                : Colors.transparent,
                          ),
                          child: allSubcategoriesSelected
                              ? Icon(
                                  Icons.check,
                                  size: 18,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      )
                    : null,
                title: GestureDetector(
                  onTap: widget.allowMultipleSelection
                      ? () => _selectCategory(mainCategory)
                      : null,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: widget.allowMultipleSelection ? 8.0 : 20.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: mainCategory.name,
                                  style: gfonts.GoogleFonts.kumbhSans(
                                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                                // Show selection count when in filter mode
                                if (widget.allowMultipleSelection)
                                  TextSpan(
                                    text: ' (',
                                    style: gfonts.GoogleFonts.kumbhSans(
                                      color: uiController.darkMode.value
                                          ? Colors.white.withValues(alpha: 0.6)
                                          : Colors.grey[600],
                                      fontSize: 15,
                                    ),
                                  ),
                                if (widget.allowMultipleSelection)
                                  TextSpan(
                                    text: '$selectedSubcategoriesCount',
                                    style: gfonts.GoogleFonts.kumbhSans(
                                      color: uiController.currentMainColor,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (widget.allowMultipleSelection)
                                  TextSpan(
                                    text: '/${mainCategory.subcategories?.length ?? 0})',
                                    style: gfonts.GoogleFonts.kumbhSans(
                                      color: uiController.darkMode.value
                                          ? Colors.white.withValues(alpha: 0.6)
                                          : Colors.grey[600],
                                      fontSize: 15,
                                    ),
                                  )
                                else
                                  TextSpan(
                                    text: ' (${mainCategory.subcategories?.length ?? 0})',
                                    style: gfonts.GoogleFonts.kumbhSans(
                                      color:
                                          uiController.darkMode.value
                                              ? Colors.white.withValues(alpha: 0.6)
                                              : Colors.grey[600],
                                      fontSize: 15,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: null, // Allow unlimited lines
                            overflow: TextOverflow.visible, // Show all text
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hide edit/delete/add buttons when in filter mode
                    if (!widget.allowMultipleSelection) ...[
                      // Show edit button for all categories
                      IconButton(
                        icon: ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            uiController.darkMode.value
                                ? Colors.white.withValues(alpha: 0.6)
                                : Colors.grey[500] ?? Colors.grey,
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            'assets/images/ic_edit.png',
                            width: 25,
                            height: 25,
                          ),
                        ),
                        onPressed: () => _showEditCategoryDialog(mainCategory),
                        tooltip:
                            mainCategory.isCustom
                                ? 'Edit Places'
                                : 'Edit',
                      ),
                      // Show delete button only when category has no subcategories
                      if (mainCategory.subcategories == null ||
                          mainCategory.subcategories!.isEmpty)
                        FutureBuilder<int>(
                          future: _getMemoryCountForCategory(mainCategory),
                          builder: (context, snapshot) {
                            final memoryCount = snapshot.data ?? 0;
                            final hasMemories = memoryCount > 0;

                            return IconButton(
                              icon: ColorFiltered(
                                colorFilter: ColorFilter.mode(
                                  hasMemories
                                      ? Colors.red.withValues(alpha: 0.6)
                                      : Colors.red,
                                  BlendMode.srcIn,
                                ),
                                child: Image.asset(
                                  'assets/images/ic_cross.png',
                                  width: 25,
                                  height: 25,
                                ),
                              ),
                              onPressed: () => _handleDeleteCategory(mainCategory),
                              tooltip: 'Delete',
                            );
                          },
                        ),
                      Obx(
                        () => IconButton(
                          icon: ColorFiltered(
                            colorFilter: ColorFilter.mode(
                              (_addingToCategory[mainCategory.id] ?? false)
                                  ? Colors.grey
                                  : uiController.darkMode.value
                                      ? Colors.white.withValues(alpha: 0.6)
                                      : uiController.currentMainColor,
                              BlendMode.srcIn,
                            ),
                            child: Image.asset(
                              'assets/images/ic_add.png',
                              width: 25,
                              height: 25,
                            ),
                          ),
                          onPressed: (_addingToCategory[mainCategory.id] ?? false)
                              ? null
                              : () => _startInlineAdding(mainCategory.id!),
                          tooltip: 'Add Subcategory',
                        ),
                      ),
                    ],
                    Obx(
                      () => ColorFiltered(
                        colorFilter: ColorFilter.mode(
                          uiController.darkMode.value
                              ? Colors.white.withValues(alpha: 0.6)
                              : Colors.grey[600] ?? Colors.grey,
                          BlendMode.srcIn,
                        ),
                        child: Image.asset(
                          (_expandedCategories[mainCategory.id] ?? false)
                              ? 'assets/images/ic_expand_close.png'
                              : 'assets/images/ic_expand_open.png',
                          width: 25,
                          height: 25,
                        ),
                      ),
                    ),
                    Container(width: 15),
                  ],
                ),
                children: [],
              ),
            ),
            // Subcategories section (outside the grey container)
            if (isExpanded) ...[
              // Inline adding widget at index 0 (removed - now using popup)
              if (mainCategory.hasSubcategories) ...[
                ...mainCategory.subcategories!.asMap().entries.map(
                  (entry) {
                    final index = entry.key;
                    final subCategory = entry.value;
                    final isLast = index == mainCategory.subcategories!.length - 1;

                    return Column(
                      children: [
                        _buildCategoryTile(subCategory, isSubcategory: true),
                        // Add bottom padding after last subcategory
                        if (isLast)
                          const SizedBox(height: 10),
                      ],
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      );
    });
  }

  /// Build individual category tile
  Widget _buildCategoryTile(
    PlaceCategory category, {
    bool isSubcategory = false,
    bool isSearchResult = false,
  }) {
    final uiController = Get.find<UiController>();

    return Obx(() {
      // Inline editing removed - now using popup

      final bool isSelected;
      if (widget.allowMultipleSelection) {
        isSelected = _selectedCategories.any((c) => c.id == category.id);
      } else {
        isSelected = widget.selectedCategory?.id == category.id;
      }

      return Container(
        margin: EdgeInsets.symmetric(
          horizontal: isSubcategory ? 10 : 16,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          // Changed background color to #F1F1F1 in light mode
          color: uiController.darkMode.value
              ? Colors.grey[900]
              : const Color(0xFFF1F1F1),
          borderRadius: BorderRadius.circular(2),
          border: isSelected
              ? Border.all(
                  color: uiController.currentMainColor,
                  width: 2,
                )
              : null,
        ),
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 5),
          dense: true,
          title: RichText(
            text: TextSpan(
              children: [
                if (isSubcategory)
                  TextSpan(
                    text: '${category.emoji} ',
                    style: gfonts.GoogleFonts.kumbhSans(fontSize: 18),
                  ),
                TextSpan(
                  text: category.name,
                  style: gfonts.GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          subtitle: isSearchResult && category.isSubcategory
              ? Text(
                  'in ${_getParentCategoryName(category.parentId!)}',
                  style: gfonts.GoogleFonts.kumbhSans(
                    color:
                        uiController.darkMode.value
                            ? Colors.white.withValues(alpha: 0.5)
                            : Colors.grey[500],
                    fontSize: 15,
                  ),
                )
              : null,
          trailing: (widget.allowMultipleSelection || isSearchResult)
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Edit button
                    GestureDetector(
                      onTap: () => _startInlineEditing(category),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            uiController.darkMode.value
                                ? Colors.white.withValues(alpha: 0.6)
                                : Colors.grey[500] ?? Colors.grey,
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            'assets/images/ic_edit.png',
                            width: 20,
                            height: 20,
                          ),
                        ),
                      ),
                    ),
                    // Delete button (always show for subcategories)
                    FutureBuilder<int>(
                      future: _getMemoryCountForCategory(category),
                      builder: (context, snapshot) {
                        final memoryCount = snapshot.data ?? 0;
                        final hasMemories = memoryCount > 0;

                        return GestureDetector(
                          onTap: () => _handleDeleteCategory(category),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                hasMemories
                                    ? Colors.red.withValues(alpha: 0.6)
                                    : Colors.red,
                                BlendMode.srcIn,
                              ),
                              child: Image.asset(
                                'assets/images/ic_cross.png',
                                width: 20,
                                height: 20,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
          onTap: () => _selectCategory(category),
        ),
      );
    });
  }

  /// Get parent category name for display
  String _getParentCategoryName(int parentId) {
    for (final mainCategory in _mainCategories) {
      if (mainCategory.id == parentId) {
        return mainCategory.name;
      }
    }
    return 'Unknown';
  }
}
