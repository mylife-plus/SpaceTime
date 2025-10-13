import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/place_category_service.dart';
import 'package:spacetime/app/models/place_category_model.dart';

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

  // Multiple selection state
  final RxList<PlaceCategory> _selectedCategories = <PlaceCategory>[].obs;

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

      Get.snackbar(
        'Database Error',
        'Failed to load place categories: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );

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

      final categories = await _categoryService.getAllCategoriesHierarchical();
      _mainCategories.value = categories;

      debugPrint(
        '[CategoryPickerWidget][_refreshCategoriesFromDatabase] Successfully refreshed ${categories.length} main categories',
      );
    } catch (e) {
      debugPrint(
        '[CategoryPickerWidget][_refreshCategoriesFromDatabase] Error refreshing categories: $e',
      );

      Get.snackbar(
        'Refresh Error',
        'Failed to refresh categories: $e',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
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
    final isSelected = _selectedCategories.any((c) => c.id == category.id);

    if (isSelected) {
      _selectedCategories.removeWhere((c) => c.id == category.id);
      debugPrint(
        '[CategoryPickerWidget][_toggleCategorySelection] Removed: ${category.name}',
      );
    } else {
      _selectedCategories.add(category);
      debugPrint(
        '[CategoryPickerWidget][_toggleCategorySelection] Added: ${category.name}',
      );
    }

    debugPrint(
      '[CategoryPickerWidget][_toggleCategorySelection] Total selected: ${_selectedCategories.length}',
    );
  }

  /// Handle done button press for multiple selection mode
  void _onDonePressed() {
    debugPrint(
      '[CategoryPickerWidget][_onDonePressed] Returning ${_selectedCategories.length} selected categories',
    );

    if (widget.onMultipleCategoriesSelected != null) {
      widget.onMultipleCategoriesSelected!(_selectedCategories.toList());
    }

    Get.back(result: _selectedCategories.toList());
  }

  /// Toggle expansion state of a main category
  void _toggleCategoryExpansion(int categoryId) {
    _expandedCategories[categoryId] =
        !(_expandedCategories[categoryId] ?? false);
  }

  /// Show add new category dialog
  void _showAddCategoryDialog({PlaceCategory? parentCategory}) {
    final uiController = Get.find<UiController>();
    final nameController = TextEditingController();
    final emojiController = TextEditingController();

    Get.dialog(
      AlertDialog(
        backgroundColor:
            uiController.darkMode.value ? Colors.grey[900] : Colors.white,
        title: Text(
          parentCategory == null
              ? 'Add New Main Category'
              : 'Add New Subcategory',
          style: TextStyle(
            color: uiController.darkMode.value ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (parentCategory != null) ...[
              Text(
                'Adding to: ${parentCategory.name}',
                style: TextStyle(
                  color:
                      uiController.darkMode.value
                          ? Colors.white70
                          : Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: nameController,
              cursorColor:
                  uiController.darkMode.value
                      ? Colors.white70
                      : Colors.grey[600],
              decoration: InputDecoration(
                labelText: 'Category Name',
                labelStyle: TextStyle(
                  color:
                      uiController.darkMode.value
                          ? Colors.white70
                          : Colors.grey[600],
                ),
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color:
                        uiController.darkMode.value
                            ? Colors.white30
                            : Colors.grey,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: uiController.currentMainColor),
                ),
              ),
              style: TextStyle(
                color:
                    uiController.darkMode.value ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            // Emoji Picker Button with StatefulBuilder for reactivity
            if (parentCategory != null)
              StatefulBuilder(
                builder: (context, setEmojiState) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color:
                            uiController.darkMode.value
                                ? Colors.white30
                                : Colors.grey,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: InkWell(
                      onTap: () async {
                        await _showEmojiPicker(context, emojiController);
                        // Update the emoji display after selection
                        setEmojiState(() {});
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            // Selected emoji display or placeholder
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color:
                                    uiController.darkMode.value
                                        ? Colors.white10
                                        : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  emojiController.text.isEmpty
                                      ? '🏠'
                                      : emojiController.text,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Label and instruction
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Emoji',
                                    style: TextStyle(
                                      color:
                                          uiController.darkMode.value
                                              ? Colors.white70
                                              : Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    emojiController.text.isEmpty
                                        ? 'Tap to select emoji'
                                        : 'Tap to change emoji',
                                    style: TextStyle(
                                      color:
                                          uiController.darkMode.value
                                              ? Colors.white
                                              : Colors.black87,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Arrow icon
                            Icon(
                              Icons.keyboard_arrow_right,
                              color:
                                  uiController.darkMode.value
                                      ? Colors.white54
                                      : Colors.grey[600],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color:
                    uiController.darkMode.value
                        ? Colors.white70
                        : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed:
                () => _addNewCategory(
                  nameController.text.trim(),
                  emojiController.text.trim(),
                  parentCategory?.id,
                ),
            style: ElevatedButton.styleFrom(
              backgroundColor: uiController.currentMainColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  /// Add a new custom category
  Future<void> _addNewCategory(String name, String emoji, int? parentId) async {
    if (name.isEmpty || emoji.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please enter both name and emoji',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
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

        Get.snackbar(
          'Success',
          'Category "$name" added successfully!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );

        debugPrint(
          '[CategoryPickerWidget][_addNewCategory] Successfully added category: ${newCategory.id}',
        );
      } else {
        Get.snackbar(
          'Error',
          'Failed to add category',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      debugPrint('[CategoryPickerWidget][_addNewCategory] Error: $e');
      Get.snackbar(
        'Error',
        'Failed to add category: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// Show edit category dialog
  void _showEditCategoryDialog(PlaceCategory category) {
    // Allow editing of all categories (both custom and predefined)
    debugPrint(
      '[CategoryPickerWidget][_showEditCategoryDialog] Opening edit dialog for: ${category.name} (${category.isCustom ? 'Custom' : 'Predefined'})',
    );

    final uiController = Get.find<UiController>();
    final nameController = TextEditingController(text: category.name);
    final emojiController = TextEditingController(text: category.emoji);

    Get.dialog(
      AlertDialog(
        backgroundColor:
            uiController.darkMode.value ? Colors.grey[900] : Colors.white,
        title: Text(
          'Edit Category',
          style: TextStyle(
            color: uiController.darkMode.value ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Category Name',

                labelStyle: TextStyle(
                  color:
                      uiController.darkMode.value
                          ? Colors.white70
                          : Colors.grey[600],
                ),
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(
                    color:
                        uiController.darkMode.value
                            ? Colors.white30
                            : Colors.grey,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: uiController.currentMainColor),
                ),
              ),
              style: TextStyle(
                color:
                    uiController.darkMode.value ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            if (!category.isMainCategory)
              // Emoji Picker Button with StatefulBuilder for reactivity
              StatefulBuilder(
                builder: (context, setEmojiState) {
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color:
                            uiController.darkMode.value
                                ? Colors.white30
                                : Colors.grey,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: InkWell(
                      onTap: () async {
                        await _showEmojiPicker(context, emojiController);
                        // Update the emoji display after selection
                        setEmojiState(() {});
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            // Selected emoji display or placeholder
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color:
                                    uiController.darkMode.value
                                        ? Colors.white10
                                        : Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  emojiController.text.isEmpty
                                      ? '🏠'
                                      : emojiController.text,
                                  style: const TextStyle(fontSize: 24),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Label and instruction
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Emoji',
                                    style: TextStyle(
                                      color:
                                          uiController.darkMode.value
                                              ? Colors.white70
                                              : Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    emojiController.text.isEmpty
                                        ? 'Tap to select emoji'
                                        : 'Tap to change emoji',
                                    style: TextStyle(
                                      color:
                                          uiController.darkMode.value
                                              ? Colors.white
                                              : Colors.black87,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Arrow icon
                            Icon(
                              Icons.keyboard_arrow_right,
                              color:
                                  uiController.darkMode.value
                                      ? Colors.white54
                                      : Colors.grey[600],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color:
                    uiController.darkMode.value
                        ? Colors.white70
                        : Colors.grey[600],
              ),
            ),
          ),
          // Allow deletion of custom categories and predefined subcategories (but not main categories)
          if (category.isCustom || category.isSubcategory)
            TextButton(
              onPressed: () => _showDeleteConfirmation(category),
              child: Text(
                'Delete',
                style: TextStyle(
                  color: Colors.red,
                  fontSize:
                      category.isCustom
                          ? 14
                          : 12, // Slightly smaller for predefined
                ),
              ),
            ),
          ElevatedButton(
            onPressed:
                () => _updateCategory(
                  category.id!,
                  nameController.text.trim(),
                  emojiController.text.trim(),
                ),
            style: ElevatedButton.styleFrom(
              backgroundColor: uiController.currentMainColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Update'),
          ),
        ],
      ),
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
        'Please enter both name and emoji',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
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

        Get.snackbar(
          'Success',
          'Category updated successfully!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } else {
        Get.snackbar(
          'Error',
          'Failed to update category',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      debugPrint('[CategoryPickerWidget][_updateCategory] Error: $e');
      Get.snackbar(
        'Error',
        'Failed to update category: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// Show delete confirmation dialog
  void _showDeleteConfirmation(PlaceCategory category) {
    final uiController = Get.find<UiController>();

    Get.dialog(
      AlertDialog(
        backgroundColor:
            uiController.darkMode.value ? Colors.grey[900] : Colors.white,
        title: Text(
          'Delete Category',
          style: TextStyle(
            color: uiController.darkMode.value ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${category.emoji} ${category.name}"?',
              style: TextStyle(
                color:
                    uiController.darkMode.value
                        ? Colors.white70
                        : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            if (!category.isCustom) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This is a predefined category. Deleting it will remove it permanently.',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              'This action cannot be undone.',
              style: TextStyle(
                color:
                    uiController.darkMode.value
                        ? Colors.white60
                        : Colors.grey[600],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(
              'Cancel',
              style: TextStyle(
                color:
                    uiController.darkMode.value
                        ? Colors.white70
                        : Colors.grey[600],
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => _deleteCategory(category.id!),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
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
        Get.back(); // Close confirmation dialog
        Get.back(); // Close edit dialog

        // Refresh categories from database to show the deletion
        debugPrint(
          '[CategoryPickerWidget][_deleteCategory] Refreshing categories from database after deletion',
        );
        await _refreshCategoriesFromDatabase();

        Get.snackbar(
          'Success',
          'Category deleted successfully!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
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

        _showCannotDeleteDialog(category?.name ?? 'Unknown', memoryCount);
      } else {
        // Failed to delete
        Get.snackbar(
          'Error',
          'Failed to delete category',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      debugPrint('[CategoryPickerWidget][_deleteCategory] Error: $e');
      Get.snackbar(
        'Error',
        'Failed to delete category: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  /// Show dialog when category cannot be deleted due to existing memories
  void _showCannotDeleteDialog(String categoryName, int memoryCount) {
    final uiController = Get.find<UiController>();

    Get.dialog(
      AlertDialog(
        backgroundColor:
            uiController.darkMode.value ? Colors.grey[900] : Colors.white,
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange, size: 24),
            const SizedBox(width: 8),
            Text(
              'Cannot Delete Category',
              style: TextStyle(
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
              'The category "$categoryName" cannot be deleted because it is being used by $memoryCount ${memoryCount == 1 ? 'memory' : 'memories'}.',
              style: TextStyle(
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
                      'To delete this category, first change the category of all memories that use it, or delete those memories.',
                      style: TextStyle(color: Colors.orange[700], fontSize: 14),
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
              style: TextStyle(
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

    _showAddCategoryDialog();
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
                          style: TextStyle(
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
                            hintText: 'Search emojis...',
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
              'Fixing category inconsistencies...',
              style: TextStyle(
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
                  style: TextStyle(
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
            'Fixed $totalFixed category inconsistencies.\n\nMemories and category picker now show the correct updated category names.',
            style: TextStyle(
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
                style: TextStyle(
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
                  style: TextStyle(
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
            'An error occurred while fixing category inconsistencies:\n\n$e',
            style: TextStyle(
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
                style: TextStyle(
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
      canPop: !widget.allowMultipleSelection || _selectedCategories.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop &&
            widget.allowMultipleSelection &&
            _selectedCategories.isNotEmpty) {
          _onDonePressed();
        }
      },
      child: Scaffold(
        backgroundColor:
            uiController.darkMode.value
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.white,
        appBar: AppBar(
          leading:
              widget.allowMultipleSelection
                  ? Obx(
                    () => IconButton(
                      onPressed:
                          _selectedCategories.isNotEmpty
                              ? _onDonePressed
                              : () => Get.back(),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: _selectedCategories.isNotEmpty ? 'Done' : 'Back',
                    ),
                  )
                  : null,
          title: Obx(
            () => Text(
              widget.allowMultipleSelection
                  ? 'Select Categories (${_selectedCategories.length})'
                  : 'Select Place Category',
              style: TextStyle(
                color:
                    uiController.darkMode.value ? Colors.white : Colors.white,
              ),
            ),
          ),
          backgroundColor: uiController.currentMainColor,
          foregroundColor:
              uiController.darkMode.value ? Colors.white : Colors.white,
          elevation: 1,
          iconTheme: IconThemeData(
            color: uiController.darkMode.value ? Colors.white : Colors.white,
          ),

          actions: [
            // Debug button to fix category inconsistencies
            // IconButton(
            //   onPressed: _fixCategoryInconsistencies,
            //   icon: const Icon(Icons.build_circle_outlined),
            //   tooltip: 'Fix Category Inconsistencies',
            // ),
            // if (widget.allowMultipleSelection) ...[
            //   Obx(() => TextButton(
            //     onPressed: _selectedCategories.isNotEmpty ? _onDonePressed : null,
            //     child: Text(
            //       'Done',
            //       style: TextStyle(
            //         color: _selectedCategories.isNotEmpty
            //             ? Colors.white
            //             : Colors.white.withValues(alpha: 0.5),
            //         fontWeight: FontWeight.bold,
            //       ),
            //     ),
            //   )),
            // ],
          ],
        ),
        body: Column(
          children: [
            // Search Field
            Container(
              color:
                  uiController.darkMode.value
                      ? Colors.white.withValues(alpha: 0.06)
                      : uiController.getLightModeBackgroundColor(
                            uiController.mainColor.value,
                          ) ??
                          const Color(0xFFF8FBFF),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search or add new category...',
                    hintStyle: TextStyle(
                      color:
                          uiController.darkMode.value
                              ? Colors.white.withValues(alpha: 0.6)
                              : Colors.grey[600],
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color:
                          uiController.darkMode.value
                              ? Colors.white.withValues(alpha: 0.7)
                              : Colors.grey[600],
                    ),
                    suffixIcon: null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color:
                            uiController.darkMode.value
                                ? Colors.white.withValues(alpha: 0.3)
                                : Colors.grey.shade300,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color:
                            uiController.darkMode.value
                                ? Colors.white.withValues(alpha: 0.3)
                                : Colors.grey.shade300,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color:
                            uiController.darkMode.value
                                ? Colors.white.withValues(alpha: 0.5)
                                : (uiController.primaryColor ?? Colors.blue),
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor:
                        uiController.darkMode.value
                            ? Colors.black
                            : Colors.white,
                  ),
                  style: TextStyle(
                    color:
                        uiController.darkMode.value
                            ? Colors.white
                            : Colors.black,
                  ),
                ),
              ),
            ),

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
                          ? Colors.white.withValues(alpha: 0.06)
                          : uiController.getLightModeBackgroundColor(
                            uiController.mainColor.value,
                          ),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
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
                'No categories match your search',
                style: TextStyle(
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
                'No categories found',
                style: TextStyle(
                  color:
                      uiController.darkMode.value
                          ? Colors.white.withValues(alpha: 0.6)
                          : Colors.grey[600],
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _showAddCategoryDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add First Category'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: uiController.currentMainColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      // color:
      child: ListView.builder(
        itemCount: _mainCategories.length,
        itemBuilder: (context, index) {
          final mainCategory = _mainCategories[index];
          return _buildMainCategoryExpansionTile(mainCategory);
        },
      ),
    );
  }

  /// Build main category expansion tile
  Widget _buildMainCategoryExpansionTile(PlaceCategory mainCategory) {
    final uiController = Get.find<UiController>();
    final isExpanded = _expandedCategories[mainCategory.id] ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: uiController.darkMode.value ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              uiController.darkMode.value
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.grey.shade300,
        ),
      ),
      child: ExpansionTile(
        key: ValueKey(mainCategory.id),
        initiallyExpanded: isExpanded,
        onExpansionChanged:
            (expanded) => _toggleCategoryExpansion(mainCategory.id!),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        collapsedShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        // leading: Text(
        //   ' ',
        //   style: const TextStyle(fontSize: 12),
        // ),
        title: Padding(
          padding: const EdgeInsets.only(left: 20.0),
          child: Text(
            mainCategory.name,
            style: TextStyle(
              color: uiController.darkMode.value ? Colors.white : Colors.black,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
        subtitle:
            mainCategory.hasSubcategories
                ? Padding(
                  padding: const EdgeInsets.only(left: 20.0),
                  child: Text(
                    '${mainCategory.subcategories!.length} subcategories',
                    style: TextStyle(
                      color:
                          uiController.darkMode.value
                              ? Colors.white.withValues(alpha: 0.6)
                              : Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                )
                : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show edit button for all categories
            IconButton(
              icon: Icon(
                Icons.edit,
                size: 20,
                color:
                    mainCategory.isCustom
                        ? uiController.currentMainColor
                        : (uiController.darkMode.value
                            ? Colors.white.withValues(alpha: 0.6)
                            : Colors.grey[500]),
              ),
              onPressed: () => _showEditCategoryDialog(mainCategory),
              tooltip:
                  mainCategory.isCustom
                      ? 'Edit Custom Category'
                      : 'Edit Category',
            ),
            IconButton(
              icon: Icon(
                Icons.add,
                size: 20,
                color: uiController.currentMainColor,
              ),
              onPressed:
                  () => _showAddCategoryDialog(parentCategory: mainCategory),
              tooltip: 'Add Subcategory',
            ),
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color:
                  uiController.darkMode.value
                      ? Colors.white.withValues(alpha: 0.6)
                      : Colors.grey[600],
            ),

            Container(width: 15),
          ],
        ),
        children: [
          if (mainCategory.hasSubcategories)
            ...mainCategory.subcategories!.map(
              (subCategory) =>
                  _buildCategoryTile(subCategory, isSubcategory: true),
            ),
          // Add subcategory option
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: Icon(
                Icons.add_circle_outline,
                color: uiController.currentMainColor,
              ),
              title: Text(
                'Add new subcategory',
                style: TextStyle(
                  color: uiController.currentMainColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
              onTap: () => _showAddCategoryDialog(parentCategory: mainCategory),
            ),
          ),
        ],
      ),
    );
  }

  /// Build individual category tile
  Widget _buildCategoryTile(
    PlaceCategory category, {
    bool isSubcategory = false,
    bool isSearchResult = false,
  }) {
    final uiController = Get.find<UiController>();

    return Obx(() {
      final bool isSelected;
      if (widget.allowMultipleSelection) {
        isSelected = _selectedCategories.any((c) => c.id == category.id);
      } else {
        isSelected = widget.selectedCategory?.id == category.id;
      }

      return Container(
        margin: EdgeInsets.symmetric(
          horizontal: isSubcategory ? 24 : 16,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? uiController.currentMainColor.withValues(alpha: 0.1)
                  : (uiController.darkMode.value
                      ? Colors.grey[900]
                      : Colors.grey[50]),
          borderRadius: BorderRadius.circular(8),
          border:
              isSelected
                  ? Border.all(color: uiController.currentMainColor, width: 2)
                  : Border.all(
                    color:
                        uiController.darkMode.value
                            ? Colors.white.withValues(alpha: 0.1)
                            : Colors.grey.shade200,
                  ),
        ),
        child: ListTile(
          dense: isSubcategory,
          leading: Text(
            !isSubcategory ? '' : category.emoji,
            style: TextStyle(fontSize: isSubcategory ? 20 : 24),
          ),
          title: Text(
            category.name,
            style: TextStyle(
              color: uiController.darkMode.value ? Colors.white : Colors.black,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              fontSize: isSubcategory ? 14 : 16,
            ),
          ),
          subtitle:
              isSearchResult && category.isSubcategory
                  ? Text(
                    'in ${_getParentCategoryName(category.parentId!)}',
                    style: TextStyle(
                      color:
                          uiController.darkMode.value
                              ? Colors.white.withValues(alpha: 0.5)
                              : Colors.grey[500],
                      fontSize: 12,
                    ),
                  )
                  : null,
          trailing:
              widget.allowMultipleSelection
                  ? Checkbox(
                    value: isSelected,
                    onChanged: (bool? value) => _selectCategory(category),
                    activeColor: uiController.currentMainColor,
                  )
                  : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Show edit button for all categories
                      IconButton(
                        icon: Icon(
                          Icons.edit,
                          size: 16,
                          color:
                              category.isCustom
                                  ? uiController.currentMainColor
                                  : (uiController.darkMode.value
                                      ? Colors.white.withValues(alpha: 0.5)
                                      : Colors.grey[400]),
                        ),
                        onPressed: () => _showEditCategoryDialog(category),
                        tooltip:
                            category.isCustom
                                ? 'Edit Custom Category'
                                : 'Edit Category',
                      ),
                      if (category.isCustom)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Custom',
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 14,
                        color:
                            uiController.darkMode.value
                                ? Colors.white.withValues(alpha: 0.4)
                                : Colors.grey[400],
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
