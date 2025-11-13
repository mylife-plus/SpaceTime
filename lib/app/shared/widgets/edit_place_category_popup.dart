import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/models/place_category_model.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/place_category_service.dart';

/// Popup dialog for editing place categories
class EditPlaceCategoryPopup extends StatefulWidget {
  final PlaceCategory category;
  final Function(PlaceCategory category)? onCategoryUpdated;

  const EditPlaceCategoryPopup({
    super.key,
    required this.category,
    this.onCategoryUpdated,
  });

  @override
  State<EditPlaceCategoryPopup> createState() => _EditPlaceCategoryPopupState();
}

class _EditPlaceCategoryPopupState extends State<EditPlaceCategoryPopup> {
  final TextEditingController _nameController = TextEditingController();
  final PlaceCategoryService _categoryService = PlaceCategoryService();
  
  String _selectedEmoji = '';
  String? _selectedParentId;
  List<PlaceCategory> _mainCategories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.category.name;
    _selectedEmoji = widget.category.emoji;
    _selectedParentId = widget.category.parentId?.toString();
    _loadMainCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadMainCategories() async {
    try {
      final categories = await _categoryService.getAllCategoriesHierarchical();
      _mainCategories = categories.where((cat) => cat.parentId == null).toList();
    } catch (e) {
      debugPrint('Error loading main categories: $e');
      _mainCategories = [];
    }
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _showEmojiPicker() async {
    final uiController = Get.find<UiController>();
    
    // Show emoji picker bottom sheet
    await showModalBottomSheet(
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

            // Emoji grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: _commonEmojis.length,
                itemBuilder: (context, index) {
                  final emoji = _commonEmojis[index];
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedEmoji = emoji;
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: _selectedEmoji == emoji
                            ? uiController.currentMainColor.withValues(alpha: 0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateCategory() async {
    // Validation
    if (_nameController.text.trim().isEmpty) {
      _showError('Please enter a Places name');
      return;
    }

    if (_selectedEmoji.isEmpty) {
      _showError('Please select an emoji');
      return;
    }

    // For subcategories, parent must be selected
    if (widget.category.parentId != null && _selectedParentId == null) {
      _showError('Please select a parent category');
      return;
    }

    try {
      final success = await _categoryService.updateCategory(
        categoryId: widget.category.id!,
        name: _nameController.text.trim(),
        emoji: _selectedEmoji,
      );

      if (success) {
        // Get the updated category
        final updatedCategory = await _categoryService.getCategoryById(widget.category.id!);

        if (mounted) {
          Navigator.of(context).pop();
          if (updatedCategory != null) {
            widget.onCategoryUpdated?.call(updatedCategory);
          }
        }
      } else {
        _showError('Failed to update category');
      }
    } catch (e) {
      debugPrint('Error updating category: $e');
      if (e.toString().contains('DUPLICATE_CATEGORY_NAME')) {
        if (mounted) {
          final message = widget.category.parentId == null
              ? 'Places with this name already exists.'
              : 'Place with this name already exists.';
          Get.snackbar(
            'Duplicate Category',
            message,
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
        }
      } else if (e.toString().contains('MAIN_CATEGORY_CONFLICTS_WITH_SUBCATEGORY')) {
        if (mounted) {
          Get.snackbar(
            'Name Conflict',
            'This name is already used by a place in another category.',
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
        }
      } else if (e.toString().contains('SUBCATEGORY_CONFLICTS_WITH_PARENT')) {
        if (mounted) {
          Get.snackbar(
            'Name Conflict',
            'This name is already used by the parent category.',
            backgroundColor: Colors.orange,
            colorText: Colors.white,
          );
        }
      } else {
        _showError('Failed to update category');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.kumbhSans()),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: uiController.darkMode.value ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close and check buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Close button
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(
                    Icons.close,
                    color: Colors.red,
                    size: 28,
                  ),
                ),
                // Title
                Text(
                  '📍 Edit Places',
                  style: GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // Check button
                GestureDetector(
                  onTap: _updateCategory,
                  child: const Icon(
                    Icons.check,
                    color: Colors.green,
                    size: 28,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Emoji selector
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text(
                  'Emoji',
                  style: GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

            InkWell(
              onTap: _showEmojiPicker,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Text(
                      _selectedEmoji.isEmpty ? '😀' : _selectedEmoji,
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tap to change emoji',
                      style: GoogleFonts.kumbhSans(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 6),

            // Parent category dropdown (only for subcategories)
            if (widget.category.parentId != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                  child: Text(
                    'Places Group',
                    style: GoogleFonts.kumbhSans(
                      color: uiController.darkMode.value ? Colors.white : Colors.black,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _isLoading
                    ? Text(
                        'Loading categories...',
                        style: GoogleFonts.kumbhSans(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      )
                    : DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedParentId,
                          hint: Text(
                            'Select Category',
                            style: GoogleFonts.kumbhSans(
                              color: uiController.darkMode.value ? Colors.white : Colors.black,
                              fontSize: 16,
                            ),
                          ),
                          isExpanded: true,
                          icon: Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.grey.shade600,
                          ),
                          items: _mainCategories.map((category) {
                            return DropdownMenuItem<String>(
                              value: category.id!.toString(),
                              child: Text(
                                '${category.emoji} ${category.name}',
                                style: GoogleFonts.kumbhSans(
                                  color: uiController.darkMode.value ? Colors.white : Colors.black,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedParentId = newValue;
                            });
                          },
                        ),
                      ),
              ),

              const SizedBox(height: 6),
            ],

            // Name input field
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 4),
                child: Text(
                  'Places',
                  style: GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: TextSelectionTheme(
                data: TextSelectionThemeData(
                  cursorColor: uiController.currentMainColor,
                  selectionColor: uiController.currentMainColor.withValues(alpha: 0.3),
                  selectionHandleColor: uiController.currentMainColor,
                ),
                child: TextField(
                  controller: _nameController,
                  style: GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Places Name',
                    hintStyle: GoogleFonts.kumbhSans(
                      color: Colors.grey.shade400,
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Common emojis for place categories
  static const List<String> _commonEmojis = [
    '🏠', '🏢', '🏪', '🏫', '🏨', '🏩',
    '🏭', '🏯', '🏰', '⛪', '🕌', '🛕',
    '🗼', '🗽', '⛲', '⛺', '🌁', '🌃',
    '🏔', '⛰', '🌋', '🗻', '🏕', '🏖',
    '🏜', '🏝', '🏞', '🏟', '🏛', '🏗',
    '🧱', '🪨', '🪵', '🛖', '🏘', '🏚',
    '🏙', '🌆', '🌇', '🌉', '♨', '🎠',
    '🎡', '🎢', '💈', '🎪', '🚂', '🚃',
    '🚄', '🚅', '🚆', '🚇', '🚈', '🚉',
    '🚊', '🚝', '🚞', '🚋', '🚌', '🚍',
    '🚎', '🚐', '🚑', '🚒', '🚓', '🚔',
    '🚕', '🚖', '🚗', '🚘', '🚙', '🛻',
    '🚚', '🚛', '🚜', '🏎', '🏍', '🛵',
    '🦽', '🦼', '🛺', '🚲', '🛴', '🛹',
    '🛼', '🚏', '🛣', '🛤', '🛢', '⛽',
    '🚨', '🚥', '🚦', '🛑', '🚧', '⚓',
    '⛵', '🛶', '🚤', '🛳', '⛴', '🛥',
    '🚢', '✈', '🛩', '🛫', '🛬', '🪂',
    '💺', '🚁', '🚟', '🚠', '🚡', '🛰',
    '🚀', '🛸', '🎆', '🎇', '🎈', '🎉',
  ];
}
