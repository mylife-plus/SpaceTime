import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/models/place_category_model.dart';
import 'package:spacetime/app/models/hashtag_group_model.dart';
import 'package:spacetime/app/models/contact_group_model.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/place_category_service.dart';
import 'package:spacetime/app/services/hashtag_group_service.dart';
import 'package:spacetime/app/services/contact_group_service.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/app/widgets/tappable_back_button.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';

/// Popup for adding/editing groups (place categories, hashtag groups, or contact groups)
class AddEditGroupPopupNew extends StatefulWidget {
  /// Mode: 'place', 'hashtag', or 'contact'
  final String mode;

  /// Callback when a new category is successfully added or edited (for places)
  final Function(PlaceCategory category)? onCategoryAdded;

  /// Callback when a hashtag group is added or edited
  final Function(HashtagGroup group)? onHashtagGroupAdded;

  /// Callback when a contact group is added or edited
  final Function(ContactGroup group)? onContactGroupAdded;

  /// Whether to show subcategory creation options
  final bool allowSubcategories;

  /// If editing, the category to edit (for places)
  final PlaceCategory? editCategory;

  /// If editing, the hashtag group to edit
  final HashtagGroup? editHashtagGroup;

  /// If editing, the contact group to edit
  final ContactGroup? editContactGroup;

  /// If adding a subcategory, the parent category ID
  final int? parentCategoryId;

  /// Whether adding a main category
  final bool isMainCategory;

  /// Whether this popup is opened from Memory View
  /// When true, shows category dropdown with add button, subcategory name, and icon picker
  final bool fromMemoryView;

  /// Whether to show both category and subcategory editing options
  final bool shouldShowEditCategoryAndSubCategory;

  /// Whether to show only category editing or adding
  final bool shouldOnlyShowEditCategoryOrAddCategory;

  /// Whether to show only subcategory editing
  final bool shouldOnlyShowEditSubCategory;

  const AddEditGroupPopupNew({
    super.key,
    this.mode = 'place', // Default to place mode for backward compatibility
    this.onCategoryAdded,
    this.onHashtagGroupAdded,
    this.onContactGroupAdded,
    this.allowSubcategories = true,
    this.editCategory,
    this.editHashtagGroup,
    this.editContactGroup,
    this.parentCategoryId,
    this.isMainCategory = false,
    this.fromMemoryView = false,
    this.shouldShowEditCategoryAndSubCategory = false,
    this.shouldOnlyShowEditCategoryOrAddCategory = false,
    this.shouldOnlyShowEditSubCategory = false,
  });

  @override
  State<AddEditGroupPopupNew> createState() => _AddEditGroupPopupNewState();
}

class _AddEditGroupPopupNewState extends State<AddEditGroupPopupNew> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _placeNameController = TextEditingController();
  final TextEditingController _placeEmojiController = TextEditingController();
  final PlaceCategoryService _categoryService = PlaceCategoryService();
  final HashtagGroupService _hashtagGroupService = HashtagGroupService();
  final ContactGroupService _contactGroupService = ContactGroupService();
  final FocusNode _nameFocusNode = FocusNode();

  final RxList<PlaceCategory> _mainCategories = <PlaceCategory>[].obs;
  final RxList<HashtagGroup> _mainHashtagGroups = <HashtagGroup>[].obs;
  final RxList<ContactGroup> _mainContactGroups = <ContactGroup>[].obs;
  final RxString _selectedParentId = ''.obs;
  final RxBool _isLoading = false.obs;
  final RxBool _isCreatingMainCategory = true.obs;

  bool get _isPlaceMode => widget.mode == 'place';
  bool get _isHashtagMode => widget.mode == 'hashtag';
  bool get _isContactMode => widget.mode == 'contact';

  @override
  void initState() {
    super.initState();

    // If editing, pre-fill the fields
    if (_isPlaceMode && widget.editCategory != null) {
      _placeNameController.text = widget.editCategory!.name;
      _placeEmojiController.text = widget.editCategory!.emoji;
    } else if (_isHashtagMode && widget.editHashtagGroup != null) {
      _placeNameController.text = widget.editHashtagGroup!.name;
    } else if (_isContactMode && widget.editContactGroup != null) {
      _placeNameController.text = widget.editContactGroup!.name;
    }

    // If adding a main category, set the flag
    if (widget.isMainCategory) {
      _isCreatingMainCategory.value = true;
    } else if (widget.parentCategoryId != null) {
      // If adding a subcategory with a specific parent, don't load categories
      _isCreatingMainCategory.value = false;
    } else if (widget.fromMemoryView) {
      // From Memory View, always load categories for dropdown
      if (_isPlaceMode) {
        _loadMainCategoriesAndSetParent();
      } else if (_isHashtagMode) {
        _loadMainHashtagGroupsAndSetParent();
      } else if (_isContactMode) {
        _loadMainContactGroupsAndSetParent();
      }
      _isCreatingMainCategory.value = false;
    } else {
      // Otherwise load categories for parent selection
      if (_isPlaceMode) {
        _loadMainCategories();
      } else if (_isHashtagMode) {
        _loadMainHashtagGroups();
      } else if (_isContactMode) {
        _loadMainContactGroups();
      }
    }

    // Auto-focus name field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
      // Position cursor at end of text when editing
      if (widget.editCategory != null || widget.editHashtagGroup != null || widget.editContactGroup != null) {
        _placeNameController.selection = TextSelection.fromPosition(
          TextPosition(offset: _placeNameController.text.length),
        );
      }
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
                'text_select_icon'.tr,
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

  /// Load main categories and set parent ID if editing from Memory View
  Future<void> _loadMainCategoriesAndSetParent() async {
    try {
      final categories = await _categoryService.getMainCategories();
      _mainCategories.value = categories;

      // If editing from Memory View, set the parent category only if it exists in the loaded categories
      if (widget.editCategory != null && widget.fromMemoryView && widget.editCategory!.parentId != null) {
        final parentIdString = widget.editCategory!.parentId.toString();
        final parentExists = categories.any((cat) => cat.id.toString() == parentIdString);

        if (parentExists) {
          _selectedParentId.value = parentIdString;
          debugPrint('[AddEditGroupPopupNew] Set parent ID to: $parentIdString');
        } else {
          debugPrint('[AddEditGroupPopupNew] Warning: Parent category with ID $parentIdString not found in loaded categories');
          // Reset to empty so dropdown shows hint instead of invalid value
          _selectedParentId.value = '';
        }
      }
    } catch (e) {
      debugPrint('[AddEditGroupPopupNew] Error loading main categories: $e');
    }
  }

  /// Load main hashtag groups
  Future<void> _loadMainHashtagGroups() async {
    try {
      final groups = await _hashtagGroupService.getMainGroups();
      _mainHashtagGroups.value = groups;
    } catch (e) {
      debugPrint('[AddEditGroupPopupNew] Error loading main hashtag groups: $e');
    }
  }

  /// Load main hashtag groups and set parent ID if editing
  Future<void> _loadMainHashtagGroupsAndSetParent() async {
    try {
      final groups = await _hashtagGroupService.getMainGroups();
      _mainHashtagGroups.value = groups;

      // If editing, set the parent group if it exists
      if (widget.editHashtagGroup != null && widget.editHashtagGroup!.parentId != null) {
        final parentIdString = widget.editHashtagGroup!.parentId.toString();
        final parentExists = groups.any((g) => g.id.toString() == parentIdString);

        if (parentExists) {
          _selectedParentId.value = parentIdString;
          debugPrint('[AddEditGroupPopupNew] Set hashtag parent ID to: $parentIdString');
        } else {
          debugPrint('[AddEditGroupPopupNew] Warning: Parent hashtag group with ID $parentIdString not found');
          _selectedParentId.value = '';
        }
      }
    } catch (e) {
      debugPrint('[AddEditGroupPopupNew] Error loading main hashtag groups: $e');
    }
  }

  /// Load main contact groups
  Future<void> _loadMainContactGroups() async {
    try {
      final groups = await _contactGroupService.getMainGroups();
      _mainContactGroups.value = groups;
    } catch (e) {
      debugPrint('[AddEditGroupPopupNew] Error loading main contact groups: $e');
    }
  }

  /// Load main contact groups and set parent ID if editing
  Future<void> _loadMainContactGroupsAndSetParent() async {
    try {
      final groups = await _contactGroupService.getMainGroups();
      _mainContactGroups.value = groups;

      // If editing, set the parent group if it exists
      if (widget.editContactGroup != null && widget.editContactGroup!.parentId != null) {
        final parentIdString = widget.editContactGroup!.parentId.toString();
        final parentExists = groups.any((g) => g.id.toString() == parentIdString);

        if (parentExists) {
          _selectedParentId.value = parentIdString;
          debugPrint('[AddEditGroupPopupNew] Set contact parent ID to: $parentIdString');
        } else {
          debugPrint('[AddEditGroupPopupNew] Warning: Parent contact group with ID $parentIdString not found');
          _selectedParentId.value = '';
        }
      }
    } catch (e) {
      debugPrint('[AddEditGroupPopupNew] Error loading main contact groups: $e');
    }
  }



  /// Add or edit category/group (router method)
  Future<void> _addCategory() async {
    if (_isHashtagMode) {
      await _addOrEditHashtagGroup();
    } else if (_isContactMode) {
      await _addOrEditContactGroup();
    } else {
      await _addOrEditPlaceCategory();
    }
  }

  /// Add or edit hashtag group
  Future<void> _addOrEditHashtagGroup() async {
    // If editing, use edit logic
    if (widget.editHashtagGroup != null) {
      await _editHashtagGroup();
      return;
    }

    // Validate group name when "Add New Group" is selected
    if (_selectedParentId.value == 'add_new_main_category') {
      final groupName = _nameController.text.trim();
      if (groupName.isEmpty) {
        showTrSnackbar('snackbar_validation_error_10', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
        return;
      }
    }

    final hashtagName = _placeNameController.text.trim();

    // Validation
    if (hashtagName.isEmpty) {
      showTrSnackbar('snackbar_validation_error_11', 
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),);
      return;
    }

    _isLoading.value = true;

    try {
      HashtagGroup? newGroup;

      // Determine if we're adding a main group or subgroup
      bool isAddingMainGroup = widget.isMainCategory ||
                               _selectedParentId.value == 'add_new_main_category';
      int? parentId = widget.parentCategoryId;

      // If using dropdown and not adding main group, get parent ID from dropdown
      if (!isAddingMainGroup &&
          widget.parentCategoryId == null &&
          _selectedParentId.value.isNotEmpty &&
          _selectedParentId.value != 'add_new_main_category') {
        parentId = int.tryParse(_selectedParentId.value);
      }

      // If adding a main group
      if (isAddingMainGroup) {
        final groupName = _selectedParentId.value == 'add_new_main_category'
            ? _nameController.text.trim()
            : hashtagName;

        if (groupName.isEmpty) {
          showTrSnackbar('snackbar_validation_error_12', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

        newGroup = await _hashtagGroupService.addCustomGroup(groupName);

        if (newGroup == null) {
          showTrSnackbar('snackbar_error_32', 
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -1) {
          showTrSnackbar('snackbar_duplicate_hashtag_group', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -3) {
          showTrSnackbar('snackbar_name_conflict_22', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

        Get.back();
        widget.onHashtagGroupAdded?.call(newGroup);
      }
      // If adding a subgroup
      else if (parentId != null) {
        newGroup = await _hashtagGroupService.addCustomGroup(hashtagName, parentId: parentId);

        if (newGroup == null) {
          showTrSnackbar('snackbar_error_33', 
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -1) {
          showTrSnackbar('snackbar_duplicate_hashtag_10', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -4) {
          showTrSnackbar('snackbar_name_conflict_23', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

        Get.back();
        widget.onHashtagGroupAdded?.call(newGroup);
      } else {
        showTrSnackbar('snackbar_validation_error_13', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
        _isLoading.value = false;
        return;
      }
    } catch (e) {
      debugPrint('[AddEditGroupPopupNew][_addOrEditHashtagGroup] Error: $e');
      showTrSnackbar('snackbar_error_34', args: [e], 
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),);
    } finally {
      _isLoading.value = false;
    }
  }

  /// Add or edit contact group
  Future<void> _addOrEditContactGroup() async {
    // If editing, use edit logic
    if (widget.editContactGroup != null) {
      await _editContactGroup();
      return;
    }

    // Validate group name when "Add New Group" is selected
    if (_selectedParentId.value == 'add_new_main_category') {
      final groupName = _nameController.text.trim();
      if (groupName.isEmpty) {
        showTrSnackbar('snackbar_validation_error_14', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
        return;
      }
    }

    final contactName = _placeNameController.text.trim();

    // Validation
    if (contactName.isEmpty) {
      showTrSnackbar('snackbar_validation_error_15', 
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),);
      return;
    }

    _isLoading.value = true;

    try {
      ContactGroup? newGroup;

      // Determine if we're adding a main group or subgroup
      bool isAddingMainGroup = widget.isMainCategory ||
                               _selectedParentId.value == 'add_new_main_category';
      int? parentId = widget.parentCategoryId;

      // If using dropdown and not adding main group, get parent ID from dropdown
      if (!isAddingMainGroup &&
          widget.parentCategoryId == null &&
          _selectedParentId.value.isNotEmpty &&
          _selectedParentId.value != 'add_new_main_category') {
        parentId = int.tryParse(_selectedParentId.value);
      }

      // If adding a main group
      if (isAddingMainGroup) {
        final groupName = _selectedParentId.value == 'add_new_main_category'
            ? _nameController.text.trim()
            : contactName;

        if (groupName.isEmpty) {
          showTrSnackbar('snackbar_validation_error_16', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

        newGroup = await _contactGroupService.addCustomGroup(groupName);

        if (newGroup == null) {
          showTrSnackbar('snackbar_error_35', 
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -1) {
          showTrSnackbar('snackbar_duplicate_contact_group', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -3) {
          showTrSnackbar('snackbar_name_conflict_24', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

        Get.back();
        widget.onContactGroupAdded?.call(newGroup);
      }
      // If adding a subgroup
      else if (parentId != null) {
        newGroup = await _contactGroupService.addCustomGroup(contactName, parentId: parentId);

        if (newGroup == null) {
          showTrSnackbar('snackbar_error_36', 
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -1) {
          showTrSnackbar('snackbar_duplicate_contact_10', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -4) {
          showTrSnackbar('snackbar_name_conflict_25', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

        Get.back();
        widget.onContactGroupAdded?.call(newGroup);
      } else {
        showTrSnackbar('snackbar_validation_error_17', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
        _isLoading.value = false;
        return;
      }
    } catch (e) {
      debugPrint('[AddEditGroupPopupNew][_addOrEditContactGroup] Error: $e');
      showTrSnackbar('snackbar_error_37', args: [e], 
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),);
    } finally {
      _isLoading.value = false;
    }
  }

  /// Add or edit place category
  Future<void> _addOrEditPlaceCategory() async {
    // If editing, use edit logic
    if (widget.editCategory != null) {
       if (_selectedParentId.value == 'add_new_main_category') {
      final categoryName = _nameController.text.trim();
      if (categoryName.isEmpty) {
        showTrSnackbar('snackbar_validation_error_18', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,        duration: const Duration(seconds: 2),);
        return;
      }
    }

      await _editCategory();
      return;
    }

    // Validate category name when "Add New Category" is selected
    if (_selectedParentId.value == 'add_new_main_category') {
      final categoryName = _nameController.text.trim();
      if (categoryName.isEmpty) {
        showTrSnackbar('snackbar_validation_error_18', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,        duration: const Duration(seconds: 2),);
        return;
      }
    }

    final placeName = _placeNameController.text.trim();
    final placeEmoji = _placeEmojiController.text.trim();

    // Validation
    if (placeName.isEmpty) {
      showTrSnackbar('snackbar_validation_error_20', 
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),);
      return;
    }

    // Validate emoji for subcategories (not for main categories) or when in Memory View mode
    if (((!widget.isMainCategory &&
        _selectedParentId.value != 'add_new_main_category') ||
        widget.fromMemoryView) &&
        placeEmoji.isEmpty) {
      showTrSnackbar('snackbar_validation_error_21', 
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),);
      return;
    }

    _isLoading.value = true;

    try {
      PlaceCategory? newCategory;

      // Determine if we're adding a main category or subcategory
      bool isAddingMainCategory = widget.isMainCategory ||
                                   _selectedParentId.value == 'add_new_main_category';
      int? parentId = widget.parentCategoryId;

      // If using dropdown and not adding main category, get parent ID from dropdown
      if (!isAddingMainCategory &&
          widget.parentCategoryId == null &&
          _selectedParentId.value.isNotEmpty &&
          _selectedParentId.value != 'add_new_main_category') {
        parentId = int.tryParse(_selectedParentId.value);
      }

      // If adding a main category
      if (isAddingMainCategory) {
        // Use _nameController for dropdown mode, _placeNameController for direct mode
        final categoryName = _selectedParentId.value == 'add_new_main_category'
            ? _nameController.text.trim()
            : placeName;

        if (categoryName.isEmpty) {
          showTrSnackbar('snackbar_validation_error_22', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,        duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

        newCategory = await _categoryService.addCustomCategory(
          name: categoryName,
          emoji: '📍', // Default emoji for main categories
          parentId: null,
        );

        if (newCategory == null) {
          showTrSnackbar('snackbar_error_38', 
            backgroundColor: Colors.red,
            colorText: Colors.white,        duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newCategory.id == -1) {
          showTrSnackbar('snackbar_duplicate_place_category', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,        duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newCategory.id == -3) {
          showTrSnackbar('snackbar_name_conflict_26', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,        duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

        Get.back(); // Close popup
        widget.onCategoryAdded?.call(newCategory);

        // Only refresh controllers if not in Memory View mode
        // In Memory View, we're just selecting a category, not saving a memory yet
        if (!widget.fromMemoryView) {
          await _categoryService.refreshMemoryControllersAfterMemoryChange();
        }

        // Get.snackbar(
        //   'Success',
        //   'Place Category "$categoryName" added successfully!',
        //   backgroundColor: Colors.green,
        //   colorText: Colors.white,
        // );
      }
      // If adding a subcategory
      else if (parentId != null) {
        newCategory = await _categoryService.addCustomCategory(
          name: placeName,
          emoji: placeEmoji,
          parentId: parentId,
        );

        if (newCategory == null) {
          showTrSnackbar('snackbar_error_39', 
            backgroundColor: Colors.red,
            colorText: Colors.white,        duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newCategory.id == -1) {
          showTrSnackbar('snackbar_duplicate_place_2', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,        duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newCategory.id == -4) {
          showTrSnackbar('snackbar_name_conflict_27', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,        duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

Navigator.of(context).pop();
        widget.onCategoryAdded?.call(newCategory);

        // Only refresh controllers if not in Memory View mode
        // In Memory View, we're just selecting a category, not saving a memory yet
        if (!widget.fromMemoryView) {
          await _categoryService.refreshMemoryControllersAfterMemoryChange();
        }

        final placeDisplayName = placeEmoji == '📍'
            ? placeName
            : '$placeEmoji $placeName';

        // Get.snackbar(
        //   'Success',
        //   'Place "$placeDisplayName" added successfully!',
        //   backgroundColor: Colors.green,
        //   colorText: Colors.white,
        // );
      } else {
        // No parent selected
        showTrSnackbar('snackbar_validation_error_23', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,        duration: const Duration(seconds: 2),);
        _isLoading.value = false;
        return;
      }
    } catch (e) {
      debugPrint('[AddPlaceCategoryPopup][_addCategory] Error: $e');
      showTrSnackbar('snackbar_error_40', args: [e], 
        backgroundColor: Colors.red,
        colorText: Colors.white,        duration: const Duration(seconds: 2),);
    } finally {
      _isLoading.value = false;
    }
  }

  /// Edit existing category
  Future<void> _editCategory() async {
    final placeName = _placeNameController.text.trim();
    // Use existing emoji if not changed (since emoji picker is hidden when editing)
    final placeEmoji = _placeEmojiController.text.trim().isNotEmpty
        ? _placeEmojiController.text.trim()
        : widget.editCategory!.emoji;

    // Validation
    if (placeName.isEmpty) {
      showTrSnackbar('snackbar_validation_error_24', 
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),);
      return;
    }

    // Validate category name when "Add New Category" is selected
    if (_selectedParentId.value == 'add_new_main_category') {
      final categoryName = _nameController.text.trim();
      if (categoryName.isEmpty) {
        showTrSnackbar('snackbar_validation_error_19', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,        duration: const Duration(seconds: 2),);
        return;
      }
    }

    // Validate emoji when editing from Memory View
    if (widget.fromMemoryView && placeEmoji.isEmpty) {
      showTrSnackbar('snackbar_validation_error_26', 
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),);
      return;
    }

    // Validate parent category only when adding from Memory View
    // Skip validation when editing (already has a parent)
    if (widget.fromMemoryView &&
        widget.editCategory == null &&
        _selectedParentId.value.isEmpty &&
        _mainCategories.isNotEmpty) {
      showTrSnackbar('snackbar_validation_error_27', 
        backgroundColor: Colors.orange,
        colorText: Colors.white,        duration: const Duration(seconds: 2),);
      return;
    }

    _isLoading.value = true;

    try {
      // Get parent ID - check multiple scenarios
      int? parentId = widget.editCategory!.parentId;

      // If "Add New Category" is selected, create the new category first
      if (_selectedParentId.value == 'add_new_main_category') {
        final categoryName = _nameController.text.trim();

        final newCategory = await _categoryService.addCustomCategory(
          name: categoryName,
          emoji: '📍', // Default emoji for main categories
          parentId: null,
        );

        if (newCategory == null) {
          showTrSnackbar('snackbar_error_41', 
            backgroundColor: Colors.red,
            colorText: Colors.white,        duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newCategory.id == -1) {
          showTrSnackbar('snackbar_duplicate_place_category_2', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,        duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newCategory.id == -3) {
          showTrSnackbar('snackbar_name_conflict_28', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,        duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

        // Use the newly created category's ID as the parent
        parentId = newCategory.id;
      }
      // Update parent ID if dropdown is being used and a valid selection is made
      else if (_selectedParentId.value.isNotEmpty &&
          _selectedParentId.value != 'add_new_main_category') {
        parentId = int.tryParse(_selectedParentId.value);
      }

      final success = await _categoryService.updateCategory(
        categoryId: widget.editCategory!.id!,
        name: placeName,
        emoji: placeEmoji,
        parentId: parentId,
      );

      if (success) {
        Get.back(); // Close popup

        // Create updated category for callback
        final updatedCategory = PlaceCategory(
          id: widget.editCategory!.id,
          name: placeName,
          emoji: placeEmoji,
          parentId: parentId,
          isCustom: widget.editCategory!.isCustom,
          createdAt: widget.editCategory!.createdAt,
          updatedAt: DateTime.now(),
        );

        widget.onCategoryAdded?.call(updatedCategory);

        // Only refresh controllers if not in Memory View mode
        // In Memory View, we're just selecting a category, not saving a memory yet
        if (!widget.fromMemoryView) {
          await _categoryService.refreshMemoryControllersAfterMemoryChange();
        }

      
      } else {
        showTrSnackbar('snackbar_error_42', 
          backgroundColor: Colors.red,
          colorText: Colors.white,        duration: const Duration(seconds: 2),);
      }
    } catch (e) {
      debugPrint('[AddPlaceCategoryPopup][_editCategory] Error: $e');
      if (e.toString().contains('DUPLICATE_CATEGORY_NAME')) {
        showTrSnackbar('snackbar_duplicate_place_3', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,        duration: const Duration(seconds: 2),);
      } else if (e.toString().contains('SUBCATEGORY_CONFLICTS_WITH_PARENT')) {
        showTrSnackbar('snackbar_name_conflict_29', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,        duration: const Duration(seconds: 2),);
      } else {
        showTrSnackbar('snackbar_error_42', 
          backgroundColor: Colors.red,
          colorText: Colors.white,        duration: const Duration(seconds: 2),);
      }
    } finally {
      _isLoading.value = false;
    }
  }

  /// Edit existing hashtag group
  Future<void> _editHashtagGroup() async {
    final hashtagName = _placeNameController.text.trim();

    // Validation
    if (hashtagName.isEmpty) {
      showTrSnackbar('snackbar_validation_error_11', 
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),);
      return;
    }

    // Validate group name when "Add New Group" is selected
    if (_selectedParentId.value == 'add_new_main_category') {
      final groupName = _nameController.text.trim();
      if (groupName.isEmpty) {
        showTrSnackbar('snackbar_validation_error_10', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
        return;
      }
    }

    _isLoading.value = true;

    try {
      // Get parent ID
      int? parentId = widget.editHashtagGroup!.parentId;

      // If "Add New Group" is selected, create the new group first
      if (_selectedParentId.value == 'add_new_main_category') {
        final groupName = _nameController.text.trim();

        final newGroup = await _hashtagGroupService.addCustomGroup(groupName);

        if (newGroup == null) {
          showTrSnackbar('snackbar_error_32', 
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -1) {
          showTrSnackbar('snackbar_duplicate_hashtag_group_2', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -3) {
          showTrSnackbar('snackbar_name_conflict_30', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

        // Use the newly created group's ID as the parent
        parentId = newGroup.id;
      }
      // Update parent ID if dropdown is being used and a valid selection is made
      else if (_selectedParentId.value.isNotEmpty &&
          _selectedParentId.value != 'add_new_main_category') {
        parentId = int.tryParse(_selectedParentId.value);
      }

      // Update the hashtag group name
      await _hashtagGroupService.updateGroup(
        widget.editHashtagGroup!.id!,
        hashtagName,
      );

      // If parent changed, update it in the database
      if (parentId != widget.editHashtagGroup!.parentId) {
        debugPrint('[AddEditGroupPopupNew] Updating parent group from ${widget.editHashtagGroup!.parentId} to $parentId');
        final databaseHelper = DatabaseHelper.instance;
        await databaseHelper.updateHashtagGroup(widget.editHashtagGroup!.id!, {
          'hashtag_group_parent_id': parentId,
          'hashtag_group_updated_at': DateTime.now().toIso8601String(),
        });
      }

      Get.back();

      // Create updated group for callback
      final updatedGroup = HashtagGroup(
        id: widget.editHashtagGroup!.id,
        name: hashtagName,
        parentId: parentId,
        isCustom: widget.editHashtagGroup!.isCustom,
        createdAt: widget.editHashtagGroup!.createdAt,
        updatedAt: DateTime.now(),
      );

      widget.onHashtagGroupAdded?.call(updatedGroup);
    } catch (e) {
      debugPrint('[AddEditGroupPopupNew][_editHashtagGroup] Error: $e');
      if (e.toString().contains('DUPLICATE_HASHTAG_NAME')) {
        showTrSnackbar(
          widget.editHashtagGroup!.parentId == null
              ? 'snackbar_duplicate_hashtag_group'
              : 'snackbar_duplicate_hashtag',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
      } else if (e.toString().contains('MAIN_GROUP_CONFLICTS_WITH_SUBGROUP')) {
        showTrSnackbar('snackbar_name_conflict_31', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
      } else if (e.toString().contains('SUBGROUP_CONFLICTS_WITH_PARENT')) {
        showTrSnackbar('snackbar_name_conflict_35', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
      } else {
        showTrSnackbar('snackbar_error_45', args: [e], 
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
      }
    } finally {
      _isLoading.value = false;
    }
  }

  /// Edit existing contact group
  Future<void> _editContactGroup() async {
    final contactName = _placeNameController.text.trim();

    // Validation
    if (contactName.isEmpty) {
      showTrSnackbar('snackbar_validation_error_30', 
        backgroundColor: Colors.orange,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),);
      return;
    }

    // Validate group name when "Add New Group" is selected
    if (_selectedParentId.value == 'add_new_main_category') {
      final groupName = _nameController.text.trim();
      if (groupName.isEmpty) {
        showTrSnackbar('snackbar_validation_error_31', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
        return;
      }
    }

    _isLoading.value = true;

    try {
      // Get parent ID
      int? parentId = widget.editContactGroup!.parentId;

      // If "Add New Group" is selected, create the new group first
      if (_selectedParentId.value == 'add_new_main_category') {
        final groupName = _nameController.text.trim();

        final newGroup = await _contactGroupService.addCustomGroup(groupName);

        if (newGroup == null) {
          showTrSnackbar('snackbar_error_46', 
            backgroundColor: Colors.red,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -1) {
          showTrSnackbar('snackbar_duplicate_contact_group_2', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        } else if (newGroup.id == -3) {
          showTrSnackbar('snackbar_name_conflict_33', 
            backgroundColor: Colors.orange,
            colorText: Colors.white,
            duration: const Duration(seconds: 2),);
          _isLoading.value = false;
          return;
        }

        // Use the newly created group's ID as the parent
        parentId = newGroup.id;
      }
      // Update parent ID if dropdown is being used and a valid selection is made
      else if (_selectedParentId.value.isNotEmpty &&
          _selectedParentId.value != 'add_new_main_category') {
        parentId = int.tryParse(_selectedParentId.value);
      }

      // Update the contact group name
      await _contactGroupService.updateGroup(
        widget.editContactGroup!.id!,
        contactName,
      );

      // If parent changed, update it in the database
      if (parentId != widget.editContactGroup!.parentId) {
        debugPrint('[AddEditGroupPopupNew] Updating parent group from ${widget.editContactGroup!.parentId} to $parentId');
        final databaseHelper = DatabaseHelper.instance;
        await databaseHelper.updateContactGroup(widget.editContactGroup!.id!, {
          'contact_group_parent_id': parentId,
          'contact_group_updated_at': DateTime.now().toIso8601String(),
        });
      }

      Get.back();

      // Create updated group for callback
      final updatedGroup = ContactGroup(
        id: widget.editContactGroup!.id,
        name: contactName,
        parentId: parentId,
        isCustom: widget.editContactGroup!.isCustom,
        createdAt: widget.editContactGroup!.createdAt,
        updatedAt: DateTime.now(),
      );

      widget.onContactGroupAdded?.call(updatedGroup);
    } catch (e) {
      debugPrint('[AddEditGroupPopupNew][_editContactGroup] Error: $e');
      if (e.toString().contains('DUPLICATE_CONTACT_NAME')) {
        showTrSnackbar(
          widget.editContactGroup!.parentId == null
              ? 'snackbar_duplicate_contact_group'
              : 'snackbar_duplicate_contact',
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),
        );
      } else if (e.toString().contains('MAIN_GROUP_CONFLICTS_WITH_SUBGROUP')) {
        showTrSnackbar('snackbar_name_conflict_34', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
      } else if (e.toString().contains('SUBGROUP_CONFLICTS_WITH_PARENT')) {
        showTrSnackbar('snackbar_name_conflict_32', 
          backgroundColor: Colors.orange,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
      } else {
        showTrSnackbar('snackbar_error_47', args: [e], 
          backgroundColor: Colors.red,
          colorText: Colors.white,
          duration: const Duration(seconds: 2),);
      }
    } finally {
      _isLoading.value = false;
    }
  }

  /// Get title text based on mode and state
  String _getTitleText() {
    if (_isHashtagMode) {
      if (widget.editHashtagGroup != null) {
        return 'add_edit_popup_title_edit_hashtag'.tr;
      } else if (widget.isMainCategory) {
        return 'add_edit_popup_title_new_hashtag_group'.tr;
      } else {
        return 'add_edit_popup_title_new_hashtag'.tr;
      }
    } else if (_isContactMode) {
      if (widget.editContactGroup != null) {
        return 'add_edit_popup_title_edit_contact'.tr;
      } else if (widget.isMainCategory) {
        return 'add_edit_popup_title_new_contact_group'.tr;
      } else {
        return 'add_edit_popup_title_new_contact'.tr;
      }
    } else {
      // Place mode
      if (widget.editCategory != null) {
        return 'add_edit_popup_title_edit_place'.tr;
      } else if (widget.isMainCategory) {
        return 'add_edit_popup_title_new_place_category'.tr;
      } else {
        return 'add_edit_popup_title_new_place'.tr;
      }
    }
  }

  /// Get category/group label text
  String _getCategoryLabelText() {
    if (_isHashtagMode) {
      return 'l10n_group_label_h'.tr;
    } else if (_isContactMode) {
      return 'l10n_group_label_c'.tr;
    } else {
      return 'hinttext_place_category'.tr;
    }
  }

  /// Get item name label text
  String _getItemNameLabelText() {
    if (_isHashtagMode) {
      return trKey('hinttext_isplacemode_category_group_name', ['l10n_label_hashtag'.tr]);
    } else if (_isContactMode) {
      return trKey('hinttext_isplacemode_category_group_name', ['l10n_label_contact'.tr]);
    } else {
      return 'hinttext_place_name'.tr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(0),
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
                  // Close button (red X, large tappable area)
                  TappableBackArea(
                    onTap: () => Get.back(),
                    child: Icon(
                      Icons.close,
                      color: Colors.red,
                      size: 24,
                    ),
                  ),

                  const Spacer(),

                  // Icon and title
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _getTitleText(),
                        style: GoogleFonts.kumbhSans(
                          fontSize: 18,
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
                  // Memory View Mode: Show category dropdown with label
                  if (widget.fromMemoryView || widget.isMainCategory || widget.editCategory != null || widget.editHashtagGroup != null || widget.editContactGroup != null) ...[
                    // Category/Group label
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          _getCategoryLabelText(),
                          style: GoogleFonts.kumbhSans(
                            fontSize: 15,
                            color: uiController.darkMode.value ? Colors.white70 : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                    // Category dropdown
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: uiController.darkMode.value ? Colors.grey[600]! : Colors.grey[300]!,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Obx(() {
                        // Validate that the selected value exists in the items list
                        final selectedValue = _selectedParentId.value;
                        bool hasValidValue = false;

                        if (_isPlaceMode) {
                          hasValidValue = selectedValue.isEmpty ||
                                          selectedValue == 'add_new_main_category' ||
                                          _mainCategories.any((cat) => cat.id.toString() == selectedValue);
                        } else if (_isHashtagMode) {
                          hasValidValue = selectedValue.isEmpty ||
                                          selectedValue == 'add_new_main_category' ||
                                          _mainHashtagGroups.any((g) => g.id.toString() == selectedValue);
                        } else if (_isContactMode) {
                          hasValidValue = selectedValue.isEmpty ||
                                          selectedValue == 'add_new_main_category' ||
                                          _mainContactGroups.any((g) => g.id.toString() == selectedValue);
                        }

                        return DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: hasValidValue && selectedValue.isNotEmpty ? selectedValue : null,
                            hint: Text(
                              trKey('text_select_getcategorylabeltext', [
                                _getCategoryLabelText(),
                              ]),
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
                              // Add "Add New Category/Group" option
                              DropdownMenuItem<String>(
                                value: 'add_new_main_category',
                                child: Text(
                                  trKey('text_add_new_isplacemode_category_group', [
                                    _isPlaceMode
                                        ? 'l10n_word_category'.tr
                                        : 'text_group'.tr,
                                  ]),
                                  style: GoogleFonts.kumbhSans(
                                    fontSize: 16,
                                    color: uiController.currentMainColor,
                                  ),
                                ),
                              ),
                              // Existing categories/groups
                              if (_isPlaceMode)
                                ..._mainCategories.map((category) {
                                  return DropdownMenuItem<String>(
                                    value: category.id.toString(),
                                    child: Text(
                                      '${category.name}',
                                      style: GoogleFonts.kumbhSans(
                                        fontSize: 16,
                                        color: uiController.darkMode.value ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  );
                                })
                              else if (_isHashtagMode)
                                ..._mainHashtagGroups.map((group) {
                                  return DropdownMenuItem<String>(
                                    value: group.id.toString(),
                                    child: Text(
                                      group.name,
                                      style: GoogleFonts.kumbhSans(
                                        fontSize: 16,
                                        color: uiController.darkMode.value ? Colors.white : Colors.black87,
                                      ),
                                    ),
                                  );
                                })
                              else if (_isContactMode)
                                ..._mainContactGroups.map((group) {
                                  return DropdownMenuItem<String>(
                                    value: group.id.toString(),
                                    child: Text(
                                      group.name,
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
                        );
                      }),
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
                                inputFormatters: [
                                  FilteringTextInputFormatter.deny(RegExp(r'\s')), // Deny all whitespace
                                ],
                                style: GoogleFonts.kumbhSans(
                                  fontSize: 16,
                                  color: uiController.darkMode.value ? Colors.white : Colors.black87,
                                ),
                                decoration: InputDecoration(
                                  hintText: _isPlaceMode
                                      ? trKey(
                                          'hinttext_isplacemode_category_group_name',
                                          ['l10n_word_category'.tr],
                                        )
                                      : (_isHashtagMode
                                          ? 'l10n_group_name_label_h'.tr
                                          : _isContactMode
                                              ? 'l10n_group_name_label_c'.tr
                                              : trKey(
                                                  'hinttext_isplacemode_category_group_name',
                                                  ['text_group'.tr],
                                                )),
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
                  ],

                  // Category selection dropdown (only show when not in category picker mode and not from Memory View)
                  if (!widget.fromMemoryView && !widget.isMainCategory && widget.parentCategoryId == null && widget.editCategory == null)
                    ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: uiController.darkMode.value ? Colors.grey[600]! : Colors.grey[300]!,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Obx(() {
                          // Validate that the selected value exists in the items list
                          final selectedValue = _selectedParentId.value;
                          final hasValidValue = selectedValue.isEmpty ||
                                                selectedValue == 'add_new_main_category' ||
                                                _mainCategories.any((cat) => cat.id.toString() == selectedValue);

                          return DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: hasValidValue && selectedValue.isNotEmpty ? selectedValue : null,
                              hint: Text(
                                'text_select_places'.tr,
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
                                    'text_add_new_category'.tr,
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
                                      '${category.name}',
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
                          );
                        }),
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
                                  inputFormatters: [
                                    FilteringTextInputFormatter.deny(RegExp(r'\s')), // Deny all whitespace
                                  ],
                                  style: GoogleFonts.kumbhSans(
                                    fontSize: 16,
                                    color: uiController.darkMode.value ? Colors.white : Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'hinttext_places_name'.tr,
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
                    ],

                  // Memory View Mode: Subcategory name label
                  if (widget.fromMemoryView || widget.shouldOnlyShowEditSubCategory) ...[
                    Row(
                      children: [
                        Center(
                          child: Text(
                            _getItemNameLabelText(),
                            style: GoogleFonts.kumbhSans(
                              fontSize: 15,
                              color: uiController.darkMode.value ? Colors.white70 : Colors.grey[700],
                            ),
                          ),
                        ),
                        // SizedBox(width: 15,),
                        // Align(
                        //   alignment: Alignment.centerLeft,
                        //   child: Text(
                        //     'Place',
                        //     style: GoogleFonts.kumbhSans(
                        //       fontSize: 15,
                        //       color: uiController.darkMode.value ? Colors.white70 : Colors.grey[700],
                        //     ),
                        //   ),
                        // ),
                      ],
                    ),
                  ],

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
                        // Emoji picker button (show only for place mode when adding subcategories or when in Memory View mode)
                        if (_isPlaceMode &&
                            ((!widget.isMainCategory &&
                            _selectedParentId.value != 'add_new_main_category' &&
                            widget.editCategory == null) ||
                            widget.fromMemoryView ||widget.shouldOnlyShowEditSubCategory))
                          ...[
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
                          ],
                        // Item name input
                        Expanded(
                          child: TextField(
                            controller: _placeNameController,
                            focusNode: widget.isMainCategory ? _nameFocusNode : null,
                            inputFormatters: [
                              FilteringTextInputFormatter.deny(RegExp(r'\s')), // Deny all whitespace
                            ],
                            style: GoogleFonts.kumbhSans(
                              fontSize: 16,
                              color: uiController.darkMode.value ? Colors.white : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.isMainCategory
                                  ? (_isHashtagMode
                                      ? 'l10n_group_name_label_h'.tr
                                      : _isContactMode
                                          ? 'l10n_group_name_label_c'.tr
                                          : 'hinttext_category_name'.tr)
                                  : _getItemNameLabelText(),
                              hintStyle: GoogleFonts.kumbhSans(
                                fontSize: 16,
                                color: uiController.darkMode.value ? Colors.white54 : Colors.grey[500],
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 6),
                            ),
                            onSubmitted: (_) => _addCategory(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Memory View Mode: Icon label at bottom center
                 

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
