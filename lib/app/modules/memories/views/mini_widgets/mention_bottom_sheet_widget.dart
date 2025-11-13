import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/config/app_colors.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/services/hashtag_group_service.dart';
import 'package:spacetime/app/services/contact_group_service.dart';
import 'package:spacetime/app/services/memory_db.dart';
import 'package:spacetime/app/models/hashtag_group_model.dart';
import 'package:spacetime/app/models/contact_group_model.dart';
import 'package:spacetime/app/modules/add_memories/controllers/add_memories_controller.dart';
import 'package:spacetime/app/modules/memories/helpers/tagmention_helper.dart';

import '../../controllers/memory_controller.dart';

class TagMentionBottomSheet extends StatefulWidget {
  final Function(String) onItemSelected;
  final bool isTagMode;
  final String initialKeyword;
  final ValueNotifier<String> searchNotifier;
  final VoidCallback? onEditingComplete;

  const TagMentionBottomSheet({
    super.key,
    required this.onItemSelected,
    required this.initialKeyword,
    required this.searchNotifier,
    this.isTagMode = true,
    this.onEditingComplete,
  });

  @override
  State<TagMentionBottomSheet> createState() => _TagMentionBottomSheetState();
}

class _TagMentionBottomSheetState extends State<TagMentionBottomSheet> {
  final TextEditingController editController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  late TagMentionController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(TagMentionController(isTagMode: widget.isTagMode));
    controller.loadSavedItems();

    // Set initial search text
    searchController.text = widget.initialKeyword;

    // Filter items based on initial keyword
    controller.filterItems(widget.initialKeyword);

    // Listen to search notifier changes
    widget.searchNotifier.addListener(_onSearchChanged);

    // Listen to editing state changes
    ever(controller.isEditing, (isEditing) {
      if (isEditing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          editController.text = controller.editingItem.value;
          // Position cursor at the end of the text
          editController.selection = TextSelection.fromPosition(
            TextPosition(offset: editController.text.length),
          );
        });
      }
    });
  }

  void _onSearchChanged() {
    final searchText = widget.searchNotifier.value;
    controller.filterItems(searchText);

    // Update search controller if needed
    if (searchController.text != searchText) {
      searchController.text = searchText;
    }
  }

  void _showAddGroupPopup(BuildContext context, String searchText) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _AddGroupPopupDialog(
          isTagMode: widget.isTagMode,
          initialName: searchText,
          onItemSelected: widget.onItemSelected,
          onComplete: widget.onEditingComplete,
        );
      },
    );
  }

  void _showEditGroupPopup(BuildContext context, Map<String, dynamic> item) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return _AddGroupPopupDialog(
          isTagMode: widget.isTagMode,
          initialName: item['name'],
          onItemSelected: widget.onItemSelected,
          onComplete: widget.onEditingComplete,
          editItemId: item['id'],
          editParentId: item['parentId']?.toString(),
        );
      },
    );
  }

  void _navigateToGroupsScreen(String groupName) {
    // Close the current popup first
    widget.onEditingComplete?.call();

    // Navigate to the appropriate groups screen
    if (widget.isTagMode) {
      Get.toNamed('/hashtag-groups', arguments: {'newGroupName': groupName});
    } else {
      Get.toNamed('/contact-groups', arguments: {'newGroupName': groupName});
    }
  }

  @override
  void dispose() {
    widget.searchNotifier.removeListener(_onSearchChanged);
    editController.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();
    final prefixChar = widget.isTagMode ? '#' : '@';

    return Obx(
      () => Container(
        height: MediaQuery.of(context).size.height * 0.35,
        decoration: BoxDecoration(
          color: uiController.darkMode.value ? Colors.black : Colors.white,
          // borderRadius: const BorderRadius.all(Radius.circular(12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              height: 40,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    
                        // ? (
                            (uiController.darkMode.value
                                ? Colors.black
                                : Color(0xFFF4FFF5)),
                        // : Colors.black,

                // color:
                //     widget.isTagMode
                //         ? uiController.darkMode.value
                //             ? uiController.mainColor.value == 'blue'
                //                 ? widget.isTagMode
                //                     ? Color(0xBAC8FDC7)
                //                     : Color(0xBA8FB3F3)
                //                 : uiController.secondaryColor
                //             : uiController.primaryColor
                //         : uiController.getPopUpColors(widget.isTagMode),
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Text(
                    widget.isTagMode ? '#' : '@',
                    style: GoogleFonts.kumbhSans(
                      color:
                          (
                                  uiController.darkMode.value)
                              ? Colors.white
                              : Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      enabled: false, // Disable clicks and editing
                      style: GoogleFonts.kumbhSans(
                        color: uiController.darkMode.value
                            ? Colors.white
                            : Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: GoogleFonts.kumbhSans(
                          color: uiController.darkMode.value
                              ? Colors.grey
                              : Colors.black.withValues(alpha: 0.5),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        disabledBorder: InputBorder.none, // Remove border when disabled
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Obx(
              () =>
                  controller.isEditing.value
                      ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Column(
                          children: [
                            TextField(
                              controller: editController,
                              autofocus: true,
                              style: GoogleFonts.kumbhSans(
                                color: uiController.darkMode.value ? Colors.white : Colors.black,
                                fontSize: 16,
                              ),
                              onChanged:
                                  (val) => controller.editingItem.value = val,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    controller.cancelEditing();
                                    widget.onEditingComplete?.call();
                                  },
                                  child: Text(
                                    'Cancel',
                                    style: GoogleFonts.kumbhSans(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: () {
                                    controller.saveEditedItem(
                                      controller.editingItem.value,
                                    );
                                    // Remove the callback to keep popup open and show updated list
                                    // widget.onEditingComplete?.call();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    // backgroundColor:
                                    //     Colors.blue, // Button background color
                                    backgroundColor:
                                        uiController.darkMode.value
                                            ? uiController.mainColor.value ==
                                                    'blue'
                                                ? Colors.black
                                                : uiController.primaryColorDark
                                            : uiController.mainColor.value ==
                                                'blue'
                                            ? AppColors.blue
                                            : uiController.secondaryColor,
                                    foregroundColor: Colors.white, // Text color
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 15,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  child: Text(
                                    'Save',
                                    style: GoogleFonts.kumbhSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                      : Expanded(
                        child: ValueListenableBuilder<String>(
                          valueListenable: widget.searchNotifier,
                          builder: (context, searchText, child) {
                            final trimmedSearchText = searchText.trim();
                            final hasExactMatch = controller.filteredItems
                                .any((item) => item['name'] == trimmedSearchText);

                            return Obx(() {
                              return controller.filteredItems.isEmpty &&
                                      trimmedSearchText.isEmpty
                                  ? Center(
                                    child: Text(
                                      'No ${widget.isTagMode ? 'hashtag groups' : 'contact groups'} available',
                                      style: GoogleFonts.kumbhSans(
                                        color: Colors.grey.shade600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  )
                                  : ListView.separated(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    itemCount:
                                        (trimmedSearchText.isNotEmpty &&
                                                !hasExactMatch
                                            ? 1
                                            : 0) +
                                        controller.filteredItems.length,
                                    separatorBuilder:
                                        (context, index) =>
                                            const Divider(height: 0.1),
                                    itemBuilder: (context, index) {
                                      // Handle "add new item" case
                                      if (trimmedSearchText.isNotEmpty &&
                                          !hasExactMatch &&
                                          index == 0) {
                                        return Container(
                                          height: 40,
                                          margin: const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          child: InkWell(
                                            onTap: () {
                                              _showAddGroupPopup(context, trimmedSearchText);
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    // vertical: 12,
                                                  ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    '$prefixChar$trimmedSearchText',
                                                    style: GoogleFonts.kumbhSans(
                                                      color:
                                                          uiController
                                                                  .darkMode
                                                                  .value
                                                              ? Colors.white
                                                              : Colors.black,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                              
                                                    child: Text(
                                                      'add',
                                                      style: GoogleFonts.kumbhSans(
                                                        color:
                                                            !widget.isTagMode
                                                                ? Colors.green
                                                                : Colors.blue,
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      }

                                      // Handle existing items
                                      final itemIndex =
                                          trimmedSearchText.isNotEmpty &&
                                                  !hasExactMatch
                                              ? index - 1
                                              : index;
                                      final item =
                                          controller.filteredItems[itemIndex];


                                      return (item['type'] == 'main_group') ? SizedBox.shrink(): Container(
                                        height: 40,
                                        margin: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: InkWell(
                                          onTap: () {
                                            widget.onItemSelected(
                                              '$prefixChar${item['name']}',
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            child: Row(
                                              children: [
                                                // Left side: Item name with prefix
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    '$prefixChar${item['name']}',
                                                    style: GoogleFonts.kumbhSans(
                                                      color:
                                                          widget.isTagMode
                                                              ? AppColors.blue
                                                              : AppColors.green,
                                                      fontSize: 16,
                                                      fontWeight: item['type'] == 'main_group'
                                                          ? FontWeight.w600
                                                          : FontWeight.w500,
                                                    ),
                                                  ),
                                                ),
                                                // Right side: Parent group name (only for subcategories)
                                                if (item['type'] == 'subgroup' &&
                                                    item['parentName'] != null &&
                                                    item['parentName'].toString().isNotEmpty)
                                                  Expanded(
                                                    flex: 1,
                                                    child: Text(
                                                      item['parentName'].toString(),
                                                      textAlign: TextAlign.end,
                                                      style: GoogleFonts.kumbhSans(
                                                        color: Colors.grey.shade600,
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.w400,
                                                      ),
                                                    ),
                                                  ),
                                                // For main groups, show a small indicator
                                                if (item['type'] == 'main_group')
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: (widget.isTagMode
                                                          ? AppColors.blue
                                                          : AppColors.green).withValues(alpha: 0.1),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(
                                                      'Group',
                                                      style: GoogleFonts.kumbhSans(
                                                        color: widget.isTagMode
                                                            ? AppColors.blue
                                                            : AppColors.green,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ),
                                                // Edit icon
                                                const SizedBox(width: 8),
                                                GestureDetector(
                                                  onTap: () {
                                                    _showEditGroupPopup(context, item);
                                                  },
                                                  child: Image.asset(
                                                    'assets/images/edit_pencil_1.png',
                                                    width: 18,
                                                    height: 18,
                                                    color: uiController.darkMode.value
                                                        ? Colors.white.withValues(alpha: 0.7)
                                                        : Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                            });
                          },
                        ),
                      ),
            ),

            // See List button at bottom
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
              ),
              child: GestureDetector(
                onTap: () async {
                  // Close the current popup
                  widget.onEditingComplete?.call();

                  // Navigate to the appropriate groups screen
                  final result = widget.isTagMode
                      ? await Get.toNamed('/hashtag-groups')
                      : await Get.toNamed('/contact-groups');

                  // Handle the returned result
                  if (result != null) {
                    final prefixChar = widget.isTagMode ? '#' : '@';
                    String itemName = '';

                    if (widget.isTagMode && result is HashtagGroup) {
                      itemName = result.name;
                    } else if (!widget.isTagMode && result is ContactGroup) {
                      itemName = result.name;
                    }

                    if (itemName.isNotEmpty) {
                      widget.onItemSelected('$prefixChar$itemName');
                    }
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'See List',
                      style: GoogleFonts.kumbhSans(
                        color: widget.isTagMode ? AppColors.blue : AppColors.green,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: widget.isTagMode ? AppColors.blue : AppColors.green,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddGroupPopupDialog extends StatefulWidget {
  final bool isTagMode;
  final String initialName;
  final Function(String) onItemSelected;
  final VoidCallback? onComplete;
  final int? editItemId;
  final String? editParentId;

  const _AddGroupPopupDialog({
    required this.isTagMode,
    required this.initialName,
    required this.onItemSelected,
    this.onComplete,
    this.editItemId,
    this.editParentId,
  });

  @override
  State<_AddGroupPopupDialog> createState() => _AddGroupPopupDialogState();
}

class _AddGroupPopupDialogState extends State<_AddGroupPopupDialog> {
  final TextEditingController _nameController = TextEditingController();
  String? _selectedCategoryId;
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  bool _showNewCategoryInput = false;
  final TextEditingController _newCategoryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
    _selectedCategoryId = widget.editParentId;
    _loadCategories();
  }



  Future<void> _loadCategories() async {
    try {
      if (widget.isTagMode) {
        final hashtagGroupService = HashtagGroupService();
        final mainGroups = await hashtagGroupService.getMainGroups();
        _categories = mainGroups.map((group) => {
          'id': group.id.toString(),
          'name': group.name,
        }).toList();
      } else {
        final contactGroupService = ContactGroupService();
        final mainGroups = await contactGroupService.getMainGroups();
        _categories = mainGroups.map((group) => {
          'id': group.id.toString(),
          'name': group.name,
        }).toList();
      }
    } catch (e) {
      debugPrint('Error loading categories: $e');
      _categories = [];
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _addSubcategory() async {
    // Validation: Check if subcategory name is provided
    if (_nameController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please enter a ${widget.isTagMode ? 'hashtag' : 'mention'} name',
              style: GoogleFonts.kumbhSans(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // If editing, update the name and parent category
    if (widget.editItemId != null) {
      // Validation: Check if category is selected when editing
      if (_selectedCategoryId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Please select a category',
                style: GoogleFonts.kumbhSans(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (_selectedCategoryId == 'add_new_category' && _newCategoryController.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Please enter a new category name',
                style: GoogleFonts.kumbhSans(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      try {
        final newName = _nameController.text.trim();
        final oldName = widget.initialName; // Store old name for memory updates
        int parentId;

        // Handle creating new category if "Add New Category" was selected
        if (_selectedCategoryId == 'add_new_category') {
          final newCategoryName = _newCategoryController.text.trim();

          if (widget.isTagMode) {
            final hashtagGroupService = HashtagGroupService();
            final newGroup = await hashtagGroupService.addCustomGroup(newCategoryName);
            if (newGroup?.id == null) {
              throw Exception('Failed to create new hashtag category');
            }
            parentId = newGroup!.id!;
          } else {
            final contactGroupService = ContactGroupService();
            final newGroup = await contactGroupService.addCustomGroup(newCategoryName);
            if (newGroup?.id == null) {
              throw Exception('Failed to create new contact category');
            }
            parentId = newGroup!.id!;
          }
        } else {
          parentId = int.parse(_selectedCategoryId!);
        }

        // Update the item with new name and parent category
        if (widget.isTagMode) {
          final databaseHelper = DatabaseHelper.instance;
          await databaseHelper.updateHashtagGroup(widget.editItemId!, {
            'hashtag_group_name': newName,
            'hashtag_group_parent_id': parentId,
            'hashtag_group_updated_at': DateTime.now().toIso8601String(),
          });

          // ✅ Update all memories that use this hashtag
          if (oldName != newName) {
            await _updateMemoriesWithTag(oldName, newName);
          }
        } else {
          final databaseHelper = DatabaseHelper.instance;
          await databaseHelper.updateContactGroup(widget.editItemId!, {
            'contact_group_name': newName,
            'contact_group_parent_id': parentId,
            'contact_group_updated_at': DateTime.now().toIso8601String(),
          });

          // ✅ Update all memories that use this mention
          if (oldName != newName) {
            await _updateMemoriesWithMention(oldName, newName);
          }
        }

        // Call the onItemSelected callback with the updated item
        final prefixChar = widget.isTagMode ? '#' : '@';
        widget.onItemSelected('$prefixChar$newName');

        // Close the dialog
        if (mounted) {
          Navigator.of(context).pop();
        }
        widget.onComplete?.call();
        return;
      } catch (e) {
        debugPrint('Error updating item: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to update ${widget.isTagMode ? 'hashtag' : 'contact'}',
                style: GoogleFonts.kumbhSans(),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    // Validation: Check if category is selected or new category name is provided
    if (_selectedCategoryId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please select a category or add a new category',
              style: GoogleFonts.kumbhSans(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (_selectedCategoryId == 'add_new_category' && _newCategoryController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Please enter a new category name',
              style: GoogleFonts.kumbhSans(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      final subcategoryName = _nameController.text.trim();
      int parentId;

      // Handle creating new category if "Add New Category" was selected
      if (_selectedCategoryId == 'add_new_category') {
        final newCategoryName = _newCategoryController.text.trim();

        if (widget.isTagMode) {
          final hashtagGroupService = HashtagGroupService();
          // Create new main category
          final newGroup = await hashtagGroupService.addCustomGroup(newCategoryName);
          if (newGroup?.id == null) {
            throw Exception('Failed to create new hashtag category');
          }
          parentId = newGroup!.id!;
        } else {
          final contactGroupService = ContactGroupService();
          // Create new main category
          final newGroup = await contactGroupService.addCustomGroup(newCategoryName);
          if (newGroup?.id == null) {
            throw Exception('Failed to create new contact category');
          }
          parentId = newGroup!.id!;
        }
      } else {
        // Use existing category
        parentId = int.parse(_selectedCategoryId!);
      }

      // Add subcategory under the parent category
      if (widget.isTagMode) {
        final hashtagGroupService = HashtagGroupService();
        await hashtagGroupService.addCustomGroup(subcategoryName, parentId: parentId);
      } else {
        final contactGroupService = ContactGroupService();
        await contactGroupService.addCustomGroup(subcategoryName, parentId: parentId);
      }

      // Call the onItemSelected callback with the new item
      final prefixChar = widget.isTagMode ? '#' : '@';
      widget.onItemSelected('$prefixChar$subcategoryName');

      // Close the dialog
      if (mounted) {
        Navigator.of(context).pop();
      }
      widget.onComplete?.call();

    } catch (e) {
      debugPrint('Error adding subcategory: $e');
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to add ${widget.isTagMode ? 'hashtag' : 'contact'} ${_selectedCategoryId == 'add_new_category' ? 'category and subcategory' : 'subcategory'}',
              style: GoogleFonts.kumbhSans(),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();
    final prefixChar = widget.isTagMode ? '#' : '@';

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
                  child: Container(
                    // padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.close,
                      color: Colors.red,
                      size: 28,
                    ),
                  ),
                ),
                // Title
                Text(
                  widget.editItemId != null
                      ? '$prefixChar edit ${widget.isTagMode ? 'Hashtag' : 'Mention'}'
                      : '$prefixChar new ${widget.isTagMode ? 'Hashtag' : 'Mention'}',
                  style: GoogleFonts.kumbhSans(
                    color: uiController.darkMode.value ? Colors.white : Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // Check button
                GestureDetector(
                  onTap: _addSubcategory,
                  child: Container(
                    // padding: const EdgeInsets.all(8),
                    child: Icon(
                      Icons.check,
                      color: Colors.green,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // Category dropdown
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              decoration: BoxDecoration(
                // color: Colors.grey.shade100,
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
                        value: _selectedCategoryId,
                        hint: Text(
                          'select $prefixChar Category',
                          style: GoogleFonts.kumbhSans(
                            color: (uiController.darkMode.value) ?  Colors.white :  Colors.black,
                            fontSize: 16,
                          ),
                        ),
                        isExpanded: true,
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.grey.shade600,
                        ),
                        items: [
                          ..._categories.map((category) {
                            return DropdownMenuItem<String>(
                              value: category['id'],
                              child: Text(
                                category['name'],
                                style: GoogleFonts.kumbhSans(
                            color: (uiController.darkMode.value) ?  Colors.white :  Colors.black,
                                  fontSize: 16,
                                ),
                              ),
                            );
                          }),
                          // Add "Add New Category" option
                          DropdownMenuItem<String>(
                            value: 'add_new_category',
                            child: Text(
                              'Add New Category',
                              style: GoogleFonts.kumbhSans(
                                color: widget.isTagMode ? Colors.green : Colors.blue,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedCategoryId = newValue;
                            _showNewCategoryInput = newValue == 'add_new_category';
                            if (!_showNewCategoryInput) {
                              _newCategoryController.clear();
                            }
                          });
                        },
                      ),
                    ),
            ),

            // New category input field (shown when "Add New Category" is selected)
            if (_showNewCategoryInput) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  // color: Colors.white,
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
                    controller: _newCategoryController,
                    decoration: InputDecoration(
                      hintText: 'Enter new category name',
                      hintStyle: GoogleFonts.kumbhSans(
                        color: Colors.grey.shade600,
                        fontSize: 16,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                    style: GoogleFonts.kumbhSans(
                            color: (uiController.darkMode.value) ?  Colors.white :  Colors.black,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 6),

            // Name input field
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              decoration: BoxDecoration(
                // color: Colors.grey.shade100,
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
                            color: (uiController.darkMode.value) ?  Colors.white :  Colors.black,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    hintText: '$prefixChar Name',
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

  /// Update all memories that contain the old mention with the new mention
  Future<void> _updateMemoriesWithMention(String oldMention, String newMention) async {
    try {
      debugPrint('🔄 ========================================');
      debugPrint('🔄 UPDATING MEMORIES WITH MENTION');
      debugPrint('🔄 Old mention: "$oldMention"');
      debugPrint('🔄 New mention: "$newMention"');
      debugPrint('🔄 ========================================');

      final databaseHelper = DatabaseHelper.instance;
      final allMemories = await databaseHelper.queryAllMemories();

      debugPrint('📊 Total memories in database: ${allMemories.length}');

      int updatedCount = 0;
      int checkedCount = 0;

      for (final memory in allMemories) {
        final memoryId = memory['id'] as int;
        final mentionsString = memory['mentions'] as String?;
        final descriptionText = memory['description'] as String?;  // ✅ FIXED: Read from 'description' not 'text'

        debugPrint('🔍 Checking memory #$memoryId');
        debugPrint('   mentions field: "$mentionsString"');
        debugPrint('   description: "$descriptionText"');

        if (mentionsString != null && mentionsString.isNotEmpty) {
          // Split mentions by comma
          final mentions = mentionsString.split(',').map((m) => m.trim()).toList();

          debugPrint('   📝 Parsed mentions: $mentions');
          debugPrint('   🔎 Looking for: "$oldMention"');
          debugPrint('   ❓ Contains old mention: ${mentions.contains(oldMention)}');

          // Check if this memory contains the old mention
          if (mentions.contains(oldMention)) {
            checkedCount++;

            // Replace old mention with new mention in the mentions field
            final updatedMentions = mentions.map((m) => m == oldMention ? newMention : m).toList();

            // Also replace in the description text
            String updatedDescription = descriptionText ?? '';
            if (updatedDescription.isNotEmpty) {
              // Replace @oldMention with @newMention in the description text
              // Use word boundary to avoid partial replacements
              updatedDescription = updatedDescription.replaceAll('@$oldMention', '@$newMention');
            }

            debugPrint('   🔄 Updating mentions from: $mentions');
            debugPrint('   🔄 Updating mentions to: $updatedMentions');
            debugPrint('   🔄 Old description: "$descriptionText"');
            debugPrint('   🔄 New description: "$updatedDescription"');

            // Update the memory with both mentions field AND description text
            await databaseHelper.updateMemory({
              'id': memoryId,
              'mentions': updatedMentions.join(','),
              'description': updatedDescription,  // ✅ FIXED: Use 'description' not 'text'
            });

            updatedCount++;
            debugPrint('   ✅ Updated memory #$memoryId');
          }
        }
      }

      debugPrint('🔄 ========================================');
      debugPrint('✅ SUMMARY:');
      debugPrint('   Total memories checked: ${allMemories.length}');
      debugPrint('   Memories with mentions: $checkedCount');
      debugPrint('   Memories updated: $updatedCount');
      debugPrint('🔄 ========================================');

      // Update recently selected mentions
      await _updateRecentMentions(oldMention, newMention);

      // Refresh the memories list in AddMemoriesController
      try {
        final addMemoriesController = Get.find<AddMemoriesController>();
        addMemoriesController.onAgainInit();
        debugPrint('✅ Refreshed AddMemoriesController');
      } catch (e) {
        debugPrint('⚠️ Could not refresh AddMemoriesController: $e');
      }
    } catch (e) {
      debugPrint('❌ Error updating memories with mention: $e');
      rethrow;
    }
  }

  /// Update all memories that contain the old tag with the new tag
  Future<void> _updateMemoriesWithTag(String oldTag, String newTag) async {
    try {
      debugPrint('🔄 ========================================');
      debugPrint('🔄 UPDATING MEMORIES WITH TAG');
      debugPrint('🔄 Old tag: "$oldTag"');
      debugPrint('🔄 New tag: "$newTag"');
      debugPrint('🔄 ========================================');

      final databaseHelper = DatabaseHelper.instance;
      final allMemories = await databaseHelper.queryAllMemories();

      debugPrint('📊 Total memories in database: ${allMemories.length}');

      int updatedCount = 0;
      int checkedCount = 0;

      for (final memory in allMemories) {
        final memoryId = memory['id'] as int;
        final tagsString = memory['tags'] as String?;
        final descriptionText = memory['description'] as String?;  // ✅ FIXED: Read from 'description' not 'text'

        debugPrint('🔍 Checking memory #$memoryId');
        debugPrint('   tags field: "$tagsString"');
        debugPrint('   description: "$descriptionText"');

        if (tagsString != null && tagsString.isNotEmpty) {
          // Split tags by comma
          final tags = tagsString.split(',').map((t) => t.trim()).toList();

          debugPrint('   📝 Parsed tags: $tags');
          debugPrint('   🔎 Looking for: "$oldTag"');
          debugPrint('   ❓ Contains old tag: ${tags.contains(oldTag)}');

          // Check if this memory contains the old tag
          if (tags.contains(oldTag)) {
            checkedCount++;

            // Replace old tag with new tag in the tags field
            final updatedTags = tags.map((t) => t == oldTag ? newTag : t).toList();

            // Also replace in the description text
            String updatedDescription = descriptionText ?? '';
            if (updatedDescription.isNotEmpty) {
              // Replace #oldTag with #newTag in the description text
              // Use word boundary to avoid partial replacements
              updatedDescription = updatedDescription.replaceAll('#$oldTag', '#$newTag');
            }

            debugPrint('   🔄 Updating tags from: $tags');
            debugPrint('   🔄 Updating tags to: $updatedTags');
            debugPrint('   🔄 Old description: "$descriptionText"');
            debugPrint('   🔄 New description: "$updatedDescription"');

            // Update the memory with both tags field AND description text
            await databaseHelper.updateMemory({
              'id': memoryId,
              'tags': updatedTags.join(','),
              'description': updatedDescription,  // ✅ FIXED: Use 'description' not 'text'
            });

            updatedCount++;
            debugPrint('✅ Updated memory #$memoryId');
          }
        }
      }

      debugPrint('🔄 ========================================');
      debugPrint('✅ SUMMARY:');
      debugPrint('   Total memories checked: ${allMemories.length}');
      debugPrint('   Memories with tags: $checkedCount');
      debugPrint('   Memories updated: $updatedCount');
      debugPrint('🔄 ========================================');

      // Update recently selected tags
      await _updateRecentTags(oldTag, newTag);

      // Refresh the memories list in AddMemoriesController
      try {
        final addMemoriesController = Get.find<AddMemoriesController>();
        addMemoriesController.onAgainInit();
        debugPrint('✅ Refreshed AddMemoriesController');
      } catch (e) {
        debugPrint('⚠️ Could not refresh AddMemoriesController: $e');
      }
    } catch (e) {
      debugPrint('❌ Error updating memories with tag: $e');
      rethrow;
    }
  }

  /// Update recently selected mentions in SharedPreferences
  Future<void> _updateRecentMentions(String oldMention, String newMention) async {
    try {
      await TagMentionStorage.editMention(oldMention, newMention);
      debugPrint('✅ Updated recent mentions');
    } catch (e) {
      debugPrint('⚠️ Error updating recent mentions: $e');
    }
  }

  /// Update recently selected tags in SharedPreferences
  Future<void> _updateRecentTags(String oldTag, String newTag) async {
    try {
      await TagMentionStorage.editTag(oldTag, newTag);
      debugPrint('✅ Updated recent tags');
    } catch (e) {
      debugPrint('⚠️ Error updating recent tags: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _newCategoryController.dispose();
    super.dispose();
  }
}
