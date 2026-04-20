import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/models/place_category_model.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/category_picker_widget.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/place_category_service.dart';
import 'package:spacetime/app/shared/widgets/add_place_category_popup.dart';

/// Generic searchable category widget that can be used across the app
///
/// Usage examples:
/// 1. Memory creation: SearchableCategoryWidget(onCategorySelected: (category) => controller.setCategory(category))
/// 2. Filter popup: SearchableCategoryWidget(title: "Search Place Categories", onCategorySelected: (category) => addToFilter(category))
class SearchableCategoryWidget extends StatefulWidget {
  /// Title/placeholder text to display when no category is selected
  final String title;

  /// Current selected category text (optional)
  final String? selectedCategory;

  /// Callback when a category is selected
  final Function(PlaceCategory category) onCategorySelected;

  /// Callback when multiple categories are selected from the picker (for filter mode)
  /// This is called when user returns from the picker with a new selection
  final Function(List<PlaceCategory> categories)? onMultipleCategoriesSelectedFromPicker;

  /// Whether to allow multiple selection in the full category picker (default: true)
  /// Set to false when opening from Memory Info Widget for single selection
  final bool allowMultipleSelectionInPicker;

  /// Callback when focus state changes (optional)
  final Function(bool isFocused)? onFocusChanged;

  /// Callback when selected category is deleted (optional)
  final VoidCallback? onSelectedCategoryDeleted;

  /// Whether to show the "See all" and "Add new" buttons (default: true)
  final bool showActionButtons;

  /// Whether to show the "Add new" button (default: true)
  final bool showAddNewButton;

  /// Custom icon to display (optional, defaults to category2 icon)
  final String? iconPath;

  /// Whether to save selected categories to recent preferences (default: true)
  final bool saveToRecent;

  /// Custom background color (optional, defaults to theme-based)
  final Color? backgroundColor;

  /// Whether to show as a compact version (smaller padding, no background)
  final bool isCompact;

  /// Previously selected categories to pass to the picker (for filter mode)
  final List<String>? previouslySelectedCategories;

  /// Whether this widget is being used inside a filter overlay (affects padding)
  final bool isInFilterMode;

  /// Border radius for the container (optional)
  final double? borderRadius;

  const SearchableCategoryWidget({
    super.key,
    this.title = '',
    this.selectedCategory,
    required this.onCategorySelected,
    this.onMultipleCategoriesSelectedFromPicker,
    this.onFocusChanged,
    this.onSelectedCategoryDeleted,
    this.showActionButtons = true,
    this.showAddNewButton = true,
    this.iconPath,
    this.saveToRecent = true,
    this.backgroundColor,
    this.isCompact = false,
    this.allowMultipleSelectionInPicker = true,
    this.previouslySelectedCategories,
    this.isInFilterMode = false,
    this.borderRadius,
  });

  @override
  State<SearchableCategoryWidget> createState() => _SearchableCategoryWidgetState();

  /// Static method to trigger refresh of recents list from external sources (e.g., category picker)
  static void triggerRecentsRefresh() {
    _SearchableCategoryWidgetState._globalRefreshNotifier.value = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[SearchableCategoryWidget] Triggered global recents refresh');
  }
}

class _SearchableCategoryWidgetState extends State<SearchableCategoryWidget> {
  final TextEditingController _searchController = TextEditingController();
  final PlaceCategoryService _categoryService = PlaceCategoryService();
  final FocusNode _focusNode = FocusNode();

  // Reactive state variables
  final RxList<PlaceCategory> _searchResults = <PlaceCategory>[].obs;
  final RxList<PlaceCategory> _recentCategories = <PlaceCategory>[].obs;
  final RxBool _isSearching = false.obs;
  final RxBool _isLoading = false.obs;
  final RxBool _showResults = false.obs;

  // Recently selected subcategories storage (max 6 items)
  static const String _recentSubcategoriesKey = 'recent_subcategories';
  static const int _maxRecentItems = 6;

  // Global refresh notifier for external updates
  static final RxInt _globalRefreshNotifier = 0.obs;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _focusNode.addListener(_onFocusChanged);
    if (widget.saveToRecent) {
      _loadRecentCategories();

      // Listen for global refresh triggers from category picker
      ever(_globalRefreshNotifier, (timestamp) {
        if (timestamp > 0) {
          debugPrint('[SearchableCategoryWidget] Global refresh triggered, reloading recents...');
          _loadRecentCategories();
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _focusNode.removeListener(_onFocusChanged);
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Handle focus changes
  void _onFocusChanged() {
    final isFocused = _focusNode.hasFocus;
    _showResults.value = isFocused;

    // If losing focus, collapse the widget
    if (!isFocused) {
      _showResults.value = false;
      debugPrint('[SearchableCategoryWidget] Collapsed due to focus loss');
    }

    widget.onFocusChanged?.call(isFocused);
    debugPrint('[SearchableCategoryWidget] Focus changed: $isFocused');
  }

  /// Handle search input changes
  void _onSearchChanged() async {
    final query = _searchController.text.trim();
    
    if (query.isEmpty) {
      _isSearching.value = false;
      _searchResults.clear();
      return;
    }

    _isSearching.value = true;
    debugPrint('[SearchableCategoryWidget] Searching for: "$query"');
    
    try {
      final results = await _categoryService.searchCategories(query);
      _searchResults.value = results;
      debugPrint('[SearchableCategoryWidget] Found ${results.length} results');
    } catch (e) {
      debugPrint('[SearchableCategoryWidget] Search error: $e');
      _searchResults.clear();
    }
  }

  /// Load recently selected categories from SharedPreferences
  Future<void> _loadRecentCategories() async {
    if (!widget.saveToRecent) return;

    try {
      _isLoading.value = true;
      final recentCategories = await _getRecentlySelectedSubcategories();
      _recentCategories.value = recentCategories;
      debugPrint('[SearchableCategoryWidget] Loaded ${recentCategories.length} recent categories');
    } catch (e) {
      debugPrint('[SearchableCategoryWidget] Error loading recent categories: $e');
    } finally {
      _isLoading.value = false;
    }
  }

  /// Get recently selected subcategories from SharedPreferences
  /// Uses the same format as CategoryPickerWidget for compatibility
  Future<List<PlaceCategory>> _getRecentlySelectedSubcategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recentJson = prefs.getString(_recentSubcategoriesKey);

      if (recentJson == null || recentJson.isEmpty) {
        return [];
      }

      final decoded = json.decode(recentJson) as List;
      final recentList = decoded.cast<Map<String, dynamic>>();
      final List<PlaceCategory> categories = [];

      for (final item in recentList) {
        try {
          // Use the same format as CategoryPickerWidget
          final category = PlaceCategory(
            id: item['id'],
            name: item['name'],
            emoji: item['emoji'],
            parentId: item['parentId'],
            order: item['order'] ?? 0,
            isCustom: item['isCustom'] ?? false,
            createdAt: DateTime.parse(item['createdAt']),
            updatedAt: item['updatedAt'] != null ? DateTime.parse(item['updatedAt']) : DateTime.now(),
          );
          categories.add(category);
        } catch (e) {
          debugPrint('[SearchableCategoryWidget] Error parsing recent category: $e');
        }
      }

      return categories.take(_maxRecentItems).toList();
    } catch (e) {
      debugPrint('[SearchableCategoryWidget] Error getting recent subcategories: $e');
      return [];
    }
  }

  /// Save recently selected subcategory to SharedPreferences
  Future<void> _saveRecentlySelectedSubcategory(PlaceCategory subcategory) async {
    if (!widget.saveToRecent) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Get existing recent categories
      List<PlaceCategory> recentCategories = await _getRecentlySelectedSubcategories();

      // Remove if already exists (to move to front)
      recentCategories.removeWhere((cat) => cat.id == subcategory.id);

      // Add to front
      recentCategories.insert(0, subcategory);

      // Keep only max items
      if (recentCategories.length > _maxRecentItems) {
        recentCategories = recentCategories.take(_maxRecentItems).toList();
      }

      // Convert to the same format as CategoryPickerWidget for compatibility
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

      debugPrint('[SearchableCategoryWidget] Saved recent subcategory: ${subcategory.name} (${subcategory.id})');
    } catch (e) {
      debugPrint('[SearchableCategoryWidget] Error saving recent subcategory: $e');
    }
  }

  /// Update a category in the recents list (when edited)
  Future<void> _updateCategoryInRecents(int categoryId, PlaceCategory updatedCategory) async {
    if (!widget.saveToRecent) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Get existing recent categories
      List<PlaceCategory> recentCategories = await _getRecentlySelectedSubcategories();

      // Find and update the category if it exists in recents
      final index = recentCategories.indexWhere((cat) => cat.id == categoryId);
      if (index != -1) {
        // Replace with updated category
        recentCategories[index] = updatedCategory;

        // Convert to the same format as CategoryPickerWidget for compatibility
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

        debugPrint('[SearchableCategoryWidget] Updated category in recents: ${updatedCategory.emoji} ${updatedCategory.name} (${updatedCategory.id})');
      } else {
        debugPrint('[SearchableCategoryWidget] Category not found in recents, skipping update');
      }
    } catch (e) {
      debugPrint('[SearchableCategoryWidget] Error updating category in recents: $e');
    }
  }

  /// Handle deleted categories from CategoryPickerWidget
  Future<void> _handleDeletedCategories(List<PlaceCategory> deletedCategories) async {
    debugPrint('[SearchableCategoryWidget] Handling ${deletedCategories.length} deleted categories');

    bool selectedCategoryWasDeleted = false;

    for (final deletedCategory in deletedCategories) {
      debugPrint('[SearchableCategoryWidget] Processing deleted category: ${deletedCategory.emoji} ${deletedCategory.name} (ID: ${deletedCategory.id}, isSubcategory: ${deletedCategory.isSubcategory})');

      // Remove from recents
      if (deletedCategory.id != null) {
        await _removeCategoryFromRecents(deletedCategory.id!);
      }

      // Check if the currently selected category was deleted
      // This works for both main categories and subcategories
      if (widget.selectedCategory != null && widget.selectedCategory!.isNotEmpty) {
        final selectedCategoryName = _extractCategoryName(widget.selectedCategory!);

        // Check if the deleted category matches the selected category
        if (selectedCategoryName == deletedCategory.name) {
          debugPrint('[SearchableCategoryWidget] Currently selected category "${deletedCategory.name}" was deleted, clearing selection');
          selectedCategoryWasDeleted = true;
        }
      }
    }

    // Reload recent categories to reflect the deletions
    await _loadRecentCategories();

    // Notify parent if selected category was deleted
    if (selectedCategoryWasDeleted && widget.onSelectedCategoryDeleted != null) {

      widget.onSelectedCategoryDeleted!();
    }
  }

  /// Extract category name from "emoji name" format
  String _extractCategoryName(String categoryString) {
    if (categoryString.contains(' ')) {
      final parts = categoryString.split(' ');
      if (parts.length >= 2) {
        return parts.sublist(1).join(' ');
      }
    }
    return categoryString;
  }

  /// Remove a category from the recents list (when deleted)
  Future<void> _removeCategoryFromRecents(int categoryId) async {
    if (!widget.saveToRecent) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final recentJson = prefs.getString(_recentSubcategoriesKey);

      if (recentJson == null || recentJson.isEmpty) {
        return;
      }

      final decoded = json.decode(recentJson) as List;
      List<Map<String, dynamic>> recentList = decoded.cast<Map<String, dynamic>>();

      // Remove the category with the given ID
      recentList.removeWhere((item) => item['id'] == categoryId);

      // Save back to preferences
      await prefs.setString(_recentSubcategoriesKey, json.encode(recentList));

      // Update the UI by reloading recent categories
      await _loadRecentCategories();

      debugPrint('[SearchableCategoryWidget] Removed category ID $categoryId from recents');
    } catch (e) {
      debugPrint('[SearchableCategoryWidget] Error removing category from recents: $e');
    }
  }

  /// Select a category
  void _selectCategory(PlaceCategory category) {
    // Format category with emoji
    final categoryWithEmoji = category.emoji.isNotEmpty
        ? '${category.emoji} ${category.name}'
        : category.name;

    debugPrint('[SearchableCategoryWidget] Selected category: $categoryWithEmoji');

    // Call the provided callback
    widget.onCategorySelected(category);

    // Save to recent categories if enabled
    // if (widget.saveToRecent) {
      _saveRecentlySelectedSubcategory(category);
    // }

    // Clear search and hide results
    _searchController.clear();
    _showResults.value = false;
    _focusNode.unfocus();

    // Refresh recent categories
    if (widget.saveToRecent) {
      _loadRecentCategories();
    }
  }

  /// Navigate to full category picker
  void _navigateToFullPicker() async {
    if (widget.allowMultipleSelectionInPicker) {
      // Convert previously selected category strings to PlaceCategory objects
      List<PlaceCategory>? previouslySelected;
      if (widget.previouslySelectedCategories != null && widget.previouslySelectedCategories!.isNotEmpty) {
        previouslySelected = await _convertCategoryStringsToObjects(widget.previouslySelectedCategories!);
        debugPrint('[SearchableCategoryWidget] Passing ${previouslySelected.length} previously selected categories to picker');
      }

      // Navigate to Category Picker in multiple selection mode
      final result = await Get.to(
        () => CategoryPickerWidget(
          allowMultipleSelection: true,
          selectedCategories: previouslySelected,
          onMultipleCategoriesSelected: (selectedCategories) {
            // If we have a callback for replacing selection (filter mode), use it
            if (widget.onMultipleCategoriesSelectedFromPicker != null) {
              widget.onMultipleCategoriesSelectedFromPicker!(selectedCategories);
              // Save each selected category to recents if enabled
              if (widget.saveToRecent) {
                for (final category in selectedCategories) {
                  _saveRecentlySelectedSubcategory(category);
                }
                // Reload recent categories to update the UI
                _loadRecentCategories();
              }
            } else {
              // Otherwise, add categories individually (normal mode)
              for (final category in selectedCategories) {
                _selectCategory(category);
              }
            }
          },
        ),
      );

      // Handle result if returned via Get.back
      if (result != null && result is List<PlaceCategory>) {
        // If we have a callback for replacing selection (filter mode), use it
        if (widget.onMultipleCategoriesSelectedFromPicker != null) {
          widget.onMultipleCategoriesSelectedFromPicker!(result);
          // Save each selected category to recents if enabled
          if (widget.saveToRecent) {
            for (final category in result) {
              _saveRecentlySelectedSubcategory(category);
            }
            // Reload recent categories to update the UI
            _loadRecentCategories();
          }
        } else {
          // Otherwise, add categories individually (normal mode)
          for (final category in result) {
            _selectCategory(category);
          }
        }
      }
    } else {
      // Navigate to Category Picker in single selection mode
      final result = await Get.to(
        () => CategoryPickerWidget(
          allowMultipleSelection: false,
          onCategorySelected: (category) {
            _selectCategory(category);
          },
           onCategoryDeleted: (category) {
            _handleDeletedCategories([category]);
          },
        ),
      );

      // Handle result if returned via Get.back
      if (result != null) {
        if (result is Map) {
          // New format: {selected: category, deleted: [categories]}
          final selectedCategory = result['selected'] as PlaceCategory?;
          final deletedCategories = result['deleted'] as List<PlaceCategory>?;

          // Handle deleted categories
          if (deletedCategories != null && deletedCategories.isNotEmpty) {
            await _handleDeletedCategories(deletedCategories);
          }

          // Handle selected category
          if (selectedCategory != null) {
            _selectCategory(selectedCategory);
          }
        } else if (result is PlaceCategory) {
          // Legacy format: just the category
          _selectCategory(result);
        }
      }
    }
  }

  /// Convert category strings (with emoji) to PlaceCategory objects
  Future<List<PlaceCategory>> _convertCategoryStringsToObjects(List<String> categoryStrings) async {
    final List<PlaceCategory> categories = [];

    try {
      // Get all categories from the service
      final allCategories = await _categoryService.getAllCategoriesHierarchical();

      for (final categoryString in categoryStrings) {
        // Extract name from "emoji name" format
        String categoryName = categoryString;
        if (categoryString.contains(' ')) {
          final parts = categoryString.split(' ');
          if (parts.length >= 2) {
            // Remove emoji (first part) and get the name
            categoryName = parts.sublist(1).join(' ');
          }
        }

        // Find matching category in all categories (including subcategories)
        PlaceCategory? matchedCategory = _findCategoryByName(allCategories, categoryName);

        if (matchedCategory != null) {
          categories.add(matchedCategory);
          debugPrint('[SearchableCategoryWidget] Matched category: ${matchedCategory.name}');
        } else {
          debugPrint('[SearchableCategoryWidget] Could not find category for: $categoryString');
        }
      }
    } catch (e) {
      debugPrint('[SearchableCategoryWidget] Error converting category strings: $e');
    }

    return categories;
  }

  /// Recursively find a category by name in the hierarchical structure
  PlaceCategory? _findCategoryByName(List<PlaceCategory> categories, String name) {
    for (final category in categories) {
      if (category.name == name) {
        return category;
      }

      // Check subcategories
      if (category.subcategories != null) {
        final found = _findCategoryByName(category.subcategories!, name);
        if (found != null) {
          return found;
        }
      }
    }
    return null;
  }

  /// Show add category popup
  void _showAddCategoryPopup() {
    debugPrint('[SearchableCategoryWidget] Showing add category popup');
    Get.dialog(
      AddPlaceCategoryPopup(
        fromMemoryView: true, // Enable Memory View mode for adding
        onCategoryAdded: (category) async {
          debugPrint('[SearchableCategoryWidget] Category added: ${category.emoji} ${category.name} (ID: ${category.id}, isSubcategory: ${category.isSubcategory})');

          // Refresh the recent categories list
          await _loadRecentCategories();

          // Auto-select the newly created category using _selectCategory
          // This ensures proper formatting and saving to recents
          _selectCategory(category);
        },
        allowSubcategories: true,
      ),
    );
  }

  /// Show edit category popup
  void _showEditCategoryPopup(PlaceCategory category) {
    debugPrint('[SearchableCategoryWidget] Showing edit category popup for: ${category.name}');
    Get.dialog(
      AddPlaceCategoryPopup(
        editCategory: category,
        fromMemoryView: true, // Enable Memory View mode for editing
        onCategoryAdded: (updatedCategory) async {
          debugPrint('[SearchableCategoryWidget] Category updated: ${updatedCategory.emoji} ${updatedCategory.name} (ID: ${updatedCategory.id}, isSubcategory: ${updatedCategory.isSubcategory})');

          // Update the category in SharedPreferences if it exists in recents
          await _updateCategoryInRecents(category.id!, updatedCategory);

          // Auto-select the updated category using _selectCategory
          // This ensures proper formatting and saving to recents
          _selectCategory(updatedCategory);

          // Move to top of recents list
          if (widget.saveToRecent) {
            await _saveRecentlySelectedSubcategory(updatedCategory);
            await _loadRecentCategories();
          }

          // Update the search results list if the category is in it
          if (_searchResults.isNotEmpty) {
            final index = _searchResults.indexWhere((cat) => cat.id == updatedCategory.id);
            if (index != -1) {
              _searchResults[index] = updatedCategory;
              debugPrint('[SearchableCategoryWidget] Updated category in search results at index $index');
            }
          }

          // Update the recent categories list if the category is in it
          if (_recentCategories.isNotEmpty) {
            final index = _recentCategories.indexWhere((cat) => cat.id == updatedCategory.id);
            if (index != -1) {
              _recentCategories[index] = updatedCategory;
              debugPrint('[SearchableCategoryWidget] Updated category in recent categories at index $index');
            }
          }

          // Refresh the recent categories list from storage
          await _loadRecentCategories();

          // Refresh search results if searching
          if (_isSearching.value && _searchController.text.isNotEmpty) {
            _onSearchChanged();
          }

          // Auto-select the updated category
          widget.onCategorySelected(updatedCategory);

          // Clear search and hide results
          _searchController.clear();
          _showResults.value = false;
          _focusNode.unfocus();
        },
      ),
      barrierDismissible: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Obx(() => GestureDetector(
      onTap: () {
        _showResults.value = true;
        _focusNode.requestFocus();
      },
      child: Container(
        padding: widget.isCompact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: widget.backgroundColor ??
              (widget.isCompact
                  ? Colors.transparent
                  : (uiController.darkMode.value ? Colors.grey[850] : Colors.white)),
          borderRadius: widget.borderRadius != null
              ? BorderRadius.circular(widget.borderRadius!)
              : null,
        ),
        child: Column(
          children: [
            // Search bar row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset(
                  widget.iconPath ?? AppImages.category2,
                  width: 20,
                  height: 20,
                  color: uiController.darkMode.value ? Colors.white : Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _showResults.value
                      ? _buildSearchField(uiController)
                      : _buildDisplayText(uiController),
                ),
              ],
            ),
            
            // Search results
            if (_showResults.value) ...[
              const SizedBox(height: 8),
              _buildSearchResults(uiController),
            ],
          ],
        ),
      ),
    ));
  }

  /// Build display text when not searching
  Widget _buildDisplayText(UiController uiController) {
    final placeholder =
        widget.title.isEmpty ? 'apptexts_places'.tr : widget.title;
    final displayText = widget.selectedCategory?.isNotEmpty == true
        ? widget.selectedCategory!
            .split(' ')
            .map((word) => word.isNotEmpty
                ? word[0].toUpperCase() + word.substring(1)
                : word)
            .join(' ')
        : placeholder;

    return GestureDetector(
      onTap: () {
        _showResults.value = true;
        _focusNode.requestFocus();
      },
      child: Text(
        displayText,
        style: widget.selectedCategory?.isNotEmpty == true
            ? TextStyle(
                fontFamily: 'KumbhSans',
                fontWeight: FontWeight.w500,
                fontSize: 16,
                color: uiController.darkMode.value ? Colors.white : Colors.grey[700]!,
              )
            : AppFonts.mediumBold(
                16,
                color: uiController.darkMode.value ? Colors.white54 : Colors.grey[700]!,
              ),
      ),
    );
  }

  /// Build search text field
  Widget _buildSearchField(UiController uiController) {
    return SizedBox(
      height: 22, // Fixed height to match icon height
      child: Obx(() => TextField(
      controller: _searchController,
      focusNode: _focusNode,
      style: AppFonts.medium(
        16,
        color: uiController.darkMode.value ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        hintText: widget.title.isEmpty ? 'apptexts_places'.tr : widget.title,
        hintStyle: AppFonts.medium(
          16,
          color: uiController.darkMode.value ? Colors.white54 : Colors.grey[700]!,
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 2), // Center text with 20px icon
        suffixIcon: (widget.isInFilterMode && _showResults.value) || _searchController.text.isNotEmpty
            ? GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _showResults.value = false;
                  _focusNode.unfocus();
                },
                child: Icon(
                  Icons.clear,
                  size: 20,
                  color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600],
                ),
              )
            : null,
      ),
    )),
    );
  }

  /// Build search results container
  Widget _buildSearchResults(UiController uiController) {
    return Container(
      constraints: BoxConstraints(maxHeight: widget.isInFilterMode ? 225 : 300),
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        children: [
          // Results list
          Expanded(
            child: _buildResultsList(uiController),
          ),

          // Bottom buttons
          if (widget.showActionButtons) _buildBottomButtons(uiController),
        ],
      ),
    );
  }

  /// Build results list
  Widget _buildResultsList(UiController uiController) {
    final categoriesToShow = _isSearching.value && _searchController.text.isNotEmpty
        ? _searchResults
        : _recentCategories;

    if (_isLoading.value) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (categoriesToShow.isEmpty) {
      // Show "No recent categories" message but don't return early
      // This allows the "See List" button to still be shown below
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        child: Text(
          _isSearching.value && _searchController.text.isNotEmpty
              ? 'No Places found'
              : 'No recent Places',
          style: AppFonts.medium(
            14,
            color: uiController.darkMode.value ? Colors.white54 : Colors.grey[600]!,
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: categoriesToShow.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: uiController.darkMode.value
            ? Colors.grey[700]!
            : Colors.grey[300]!,
      ),
      itemBuilder: (context, index) {
        final category = categoriesToShow[index];
        return _buildCategoryItem(category, uiController);
      },
    );
  }

  /// Build individual category item
  Widget _buildCategoryItem(PlaceCategory category, UiController uiController) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectCategory(category),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Subcategory emoji and name
              Text(
                category.emoji,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
             Expanded(
               child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,

                children: [ AutoSizeText(
                  category.name,
                  style: AppFonts.medium(
                    14, // Default font size
                    color: uiController.darkMode.value ? Colors.white : Colors.black87,
                  ),
                  minFontSize: 10, // Minimum font size for scaling
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),

                // Parent category name (if available)
                if (category.parentId != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FutureBuilder<PlaceCategory?>(
                      future: _categoryService.getCategoryById(category.parentId!),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return AutoSizeText(
                            snapshot.data!.name,
                            textAlign: TextAlign.right,
                            style: AppFonts.regular(
                              14, // Smaller base font size for category name (secondary)
                              color: uiController.darkMode.value
                                  ? Colors.white54
                                  : Colors.grey[600]!,
                            ),
                            minFontSize: 8, // Minimum font size for scaling
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ],],),
             ),
              // Edit button with increased clickable area
              const SizedBox(width: 4),
              if(!widget.isInFilterMode)
              InkWell(
                onTap: () => _showEditCategoryPopup(category),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    AppImages.edit,
                    width: 16,
                    height: 16,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build bottom action buttons
  Widget _buildBottomButtons(UiController uiController) {
    return Column(
      children: [
        Divider(height: 1, color: Colors.grey.withValues(alpha: 0.3)),
        Container(
          height: widget.isInFilterMode ? 40 : null, // Fixed height only in filter mode
          padding: widget.isInFilterMode
              ?  EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: !(widget.showAddNewButton) ? 0 : 0,
                  top: !(widget.showAddNewButton) ? 12 : 8
                ) // No padding in filter mode - let Center/Alignment handle it
              : EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: !(widget.showAddNewButton) ? 4 : 0,
                  top: !(widget.showAddNewButton) ? 8 : 8
                ),
          child: widget.showAddNewButton
              ? Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _navigateToFullPicker(),
                        child: Container(
                          alignment: Alignment.center,
                          child: Text(
                            'text_see_list_2'.tr,
                            style: AppFonts.medium(
                              18,
                              color: uiController.darkMode.value ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      // height: 20,
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () => _showAddCategoryPopup(),
                        child: Container(
                          alignment: Alignment.center,
                          child: Text(
                            'text_add_new'.tr,
                            style: AppFonts.medium(
                              18,
                              color: uiController.currentMainColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : InkWell(
                  onTap: () => _navigateToFullPicker(),
                  child: Center(
                    child: Text(
                      'text_see_list_3'.tr,
                      style: AppFonts.medium(
                        18,
                        color: uiController.currentMainColor,
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}
