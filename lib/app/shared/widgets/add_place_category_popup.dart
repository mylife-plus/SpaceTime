import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/models/place_category_model.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/place_category_service.dart';

/// Popup for adding new place categories with emoji selection
class AddPlaceCategoryPopup extends StatefulWidget {
  /// Callback when a new category is successfully added
  final Function(PlaceCategory category)? onCategoryAdded;
  
  /// Whether to show subcategory creation options
  final bool allowSubcategories;

  const AddPlaceCategoryPopup({
    super.key,
    this.onCategoryAdded,
    this.allowSubcategories = true,
  });

  @override
  State<AddPlaceCategoryPopup> createState() => _AddPlaceCategoryPopupState();
}

class _AddPlaceCategoryPopupState extends State<AddPlaceCategoryPopup> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _placeNameController = TextEditingController();
  final TextEditingController _placeEmojiController = TextEditingController();
  final PlaceCategoryService _categoryService = PlaceCategoryService();
  final FocusNode _nameFocusNode = FocusNode();

  final RxList<PlaceCategory> _mainCategories = <PlaceCategory>[].obs;
  final RxString _selectedParentId = ''.obs;
  final RxBool _isLoading = false.obs;
  final RxBool _isCreatingMainCategory = true.obs;

  @override
  void initState() {
    super.initState();
    _loadMainCategories();
    
    // Auto-focus name field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _placeNameController.dispose();
    _placeEmojiController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  /// Show emoji picker for place name
  Future<void> _showPlaceEmojiPicker() async {
    final uiController = Get.find<UiController>();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: uiController.darkMode.value ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Emoji',
                style: AppFonts.medium(18,
                  color: uiController.darkMode.value ? Colors.white : Colors.black87),
              ),
            ),

            // Emoji Picker
            Expanded(
              child: Theme(
                data: Theme.of(context).copyWith(
                  textSelectionTheme: TextSelectionThemeData(
                    cursorColor: uiController.currentMainColor,
                  ),
                ),
                child: emoji_picker.EmojiPicker(
                  onEmojiSelected: (category, emoji) {
                    _placeEmojiController.text = emoji.emoji;
                    Navigator.pop(context);
                    setState(() {});
                  },
                  config: emoji_picker.Config(
                    height: 256,
                    checkPlatformCompatibility: true,
                    emojiViewConfig: emoji_picker.EmojiViewConfig(
                      backgroundColor: uiController.darkMode.value
                          ? const Color(0xFF1E1E1E)
                          : Colors.white,
                      columns: 7,
                      emojiSizeMax: 32,
                    ),
                    categoryViewConfig: emoji_picker.CategoryViewConfig(
                      indicatorColor: uiController.currentMainColor,
                      iconColorSelected: uiController.currentMainColor,
                      backgroundColor: uiController.darkMode.value
                          ? const Color(0xFF2E2E2E)
                          : Colors.grey[100]!,
                    ),
                    bottomActionBarConfig: emoji_picker.BottomActionBarConfig(
                      buttonColor: uiController.currentMainColor,
                      backgroundColor: uiController.darkMode.value
                          ? const Color(0xFF2E2E2E)
                          : Colors.grey[100]!,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Load main categories for parent selection
  Future<void> _loadMainCategories() async {
    try {
      final categories = await _categoryService.getMainCategories();
      _mainCategories.value = categories;
    } catch (e) {
      debugPrint('[AddPlaceCategoryPopup] Error loading main categories: $e');
    }
  }



  /// Add new category
  Future<void> _addCategory() async {
    final placeName = _placeNameController.text.trim();

    if (placeName.isEmpty) {
      Get.snackbar(
        'Validation Error',
        'Please enter a place name',
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    _isLoading.value = true;

    try {
      PlaceCategory? parentCategoryToUse;
      PlaceCategory? newPlaceCategory;

      // If creating a new main category
      if (_selectedParentId.value == 'add_new_main_category') {
        final categoryName = _nameController.text.trim();

        if (categoryName.isEmpty) {
          Get.snackbar(
            'Validation Error',
            'Please enter a Places name',
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
          _isLoading.value = false;
          return;
        }

        // Create new main category first
        parentCategoryToUse = await _categoryService.addCustomCategory(
          name: categoryName,
          emoji: '📍', // Default emoji for place categories
          parentId: null,
        );

        if (parentCategoryToUse == null) {
          Get.snackbar(
            'Error',
            'Failed to create new Place Group',
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
          _isLoading.value = false;
          return;
        } else if (parentCategoryToUse.id == -1) {
          // Duplicate category name
          Get.snackbar(
            'Duplicate Place Group',
            'Place Group with this name already exists.',
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
          _isLoading.value = false;
          return;
        } else if (parentCategoryToUse.id == -3) {
          // Main category name conflicts with existing subcategory
          Get.snackbar(
            'Name Conflict',
            'This name is already used by a Place in another Place Group.',
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
          _isLoading.value = false;
          return;
        }
      } else if (_selectedParentId.value.isNotEmpty) {
        // Use existing category
        final categoryId = int.parse(_selectedParentId.value);
        parentCategoryToUse = _mainCategories.firstWhere((cat) => cat.id == categoryId);
      }

      if (parentCategoryToUse != null) {
        // Now create the place as a subcategory under the selected/created main category
        final placeEmoji = _placeEmojiController.text.isEmpty ? '📍' : _placeEmojiController.text;

        debugPrint(
          '[AddPlaceCategoryPopup][_addCategory] Creating place subcategory: $placeName ($placeEmoji) under parent: ${parentCategoryToUse.name} (ID: ${parentCategoryToUse.id})',
        );

        newPlaceCategory = await _categoryService.addCustomCategory(
          name: placeName,
          emoji: placeEmoji,
          parentId: parentCategoryToUse.id!, // This makes it a subcategory
        );

        if (newPlaceCategory == null) {
          Get.snackbar(
            'Error',
            'Failed to create places',
            backgroundColor: Colors.red,
            colorText: Colors.white,
          );
          _isLoading.value = false;
          return;
        } else if (newPlaceCategory.id == -1) {
          // Duplicate subcategory name
          Get.snackbar(
            'Duplicate Category',
            'Place with this name already exists.',
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
          _isLoading.value = false;
          return;
        } else if (newPlaceCategory.id == -4) {
          // Subcategory name conflicts with parent category
          Get.snackbar(
            'Name Conflict',
            'This name is already used by the category "${parentCategoryToUse.name}".',
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
          _isLoading.value = false;
          return;
        }

        Get.back(); // Close popup

        // Call the callback with the newly created place subcategory
        widget.onCategoryAdded?.call(newPlaceCategory);

        // Refresh memory controllers to update their data after category changes
        await _categoryService.refreshMemoryControllersAfterMemoryChange();

        final placeDisplayName = placeEmoji == '📍'
            ? placeName
            : '$placeEmoji $placeName';

        Get.snackbar(
          'Success',
          'Place "$placeDisplayName" added under category "${parentCategoryToUse.name}"!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );

        debugPrint(
          '[AddPlaceCategoryPopup][_addCategory] Successfully created place subcategory: ${newPlaceCategory.id}',
        );
      } else {
        Get.snackbar(
          'Error',
          'Please select or create a category',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      debugPrint('[AddPlaceCategoryPopup][_addCategory] Error: $e');
      Get.snackbar(
        'Error',
        'Failed to add place: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      _isLoading.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.all(0),
        decoration: BoxDecoration(
          color: uiController.darkMode.value ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close, title, and save buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  // Close button (red X)
                  GestureDetector(
                    onTap: () => Get.back(),
                    child: Container(
                      width: 32,
                      height: 32,
                      child: Icon(
                        Icons.close,
                        color: Colors.red,
                        size: 24,
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Pin icon and title
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                     
                      Text( 
                        '📍 new Place',
                        style: GoogleFonts.kumbhSans(
                          fontSize: 18,
                          // fontWeight: FontWeight.,
                          color: uiController.darkMode.value ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Save button (green checkmark)
                  Obx(() => GestureDetector(
                    onTap: _isLoading.value ? null : _addCategory,
                    child: Container(
                      width: 32,
                      height: 32,
                      child: _isLoading.value
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                              ),
                            )
                          : Icon(
                              Icons.check,
                              color: Colors.green,
                              size: 24,
                            ),
                    ),
                  )),
                ],
              ),
            ),

            // Content area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  // Category selection dropdown
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: uiController.darkMode.value ? Colors.grey[600]! : Colors.grey[300]!,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Obx(() => DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedParentId.value.isEmpty ? null : _selectedParentId.value,
                        hint: Text(
                          'select Places',
                          style: GoogleFonts.kumbhSans(
                            fontSize: 16,
                            color: uiController.darkMode.value ? Colors.white70 : Colors.black87,
                          ),
                        ),
                        isExpanded: true,
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          color: uiController.darkMode.value ? Colors.white70 : Colors.grey[600],
                        ),
                        dropdownColor: uiController.darkMode.value ? Colors.grey[800] : Colors.white,
                        items: [
                          // Add "Add New Category" option
                          DropdownMenuItem<String>(
                            value: 'add_new_main_category',
                            child: Text(
                              '+ Add New Category',
                              style: GoogleFonts.kumbhSans(
                                fontSize: 16,
                                color: uiController.currentMainColor,
                                // fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          // Existing categories
                          ..._mainCategories.map((category) {
                            return DropdownMenuItem<String>(
                              value: category.id.toString(),
                              child: Text(
                                '${category.emoji} ${category.name}',
                                style: GoogleFonts.kumbhSans(
                                  fontSize: 16,
                                  color: uiController.darkMode.value ? Colors.white : Colors.black87,
                                ),
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          if (value == 'add_new_main_category') {
                            _isCreatingMainCategory.value = true;
                            _selectedParentId.value = 'add_new_main_category';
                          } else {
                            _isCreatingMainCategory.value = false;
                            _selectedParentId.value = value ?? '';
                          }
                        },
                      ),
                    )),
                  ),

                  const SizedBox(height: 8),

                  // New category name input (shown when "Add New Category" is selected)
                  Obx(() {
                    if (_selectedParentId.value == 'add_new_main_category') {
                      return Column(
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: uiController.darkMode.value ? Colors.grey[600]! : Colors.grey[300]!,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: TextField(
                              controller: _nameController,
                              focusNode: _nameFocusNode,
                              style: GoogleFonts.kumbhSans(
                                fontSize: 16,
                                color: uiController.darkMode.value ? Colors.white : Colors.black87,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Places Name',
                                hintStyle: GoogleFonts.kumbhSans(
                                  fontSize: 16,
                                  color: uiController.darkMode.value ? Colors.white54 : Colors.grey[500],
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      );
                    }
                    return const SizedBox.shrink();
                  }),

                  // Place name input
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: uiController.darkMode.value ? Colors.grey[600]! : Colors.grey[300]!,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      children: [
                        // Emoji picker button
                        GestureDetector(
                          onTap: _showPlaceEmojiPicker,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: uiController.darkMode.value ? Colors.grey[600]! : Colors.grey[400]!,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: _placeEmojiController.text.isEmpty
                                  ? Icon(
                                      Icons.add,
                                      size: 20,
                                      color: uiController.currentMainColor,
                                    )
                                  : Text(
                                      _placeEmojiController.text,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Place name input
                        Expanded(
                          child: TextField(
                            controller: _placeNameController,
                            style: GoogleFonts.kumbhSans(
                              fontSize: 16,
                              color: uiController.darkMode.value ? Colors.white : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Place Name',
                              hintStyle: GoogleFonts.kumbhSans(
                                fontSize: 16,
                                color: uiController.darkMode.value ? Colors.white54 : Colors.grey[500],
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
