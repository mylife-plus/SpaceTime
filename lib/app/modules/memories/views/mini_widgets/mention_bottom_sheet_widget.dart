import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_colors.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import '../../../../config/app_fonts.dart';
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
  late TagMentionController controller;

  @override
  void initState() {
    super.initState();
    controller = Get.put(TagMentionController(isTagMode: widget.isTagMode));
    controller.loadSavedItems();

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
    controller.filterItems(widget.searchNotifier.value);
  }

  @override
  void dispose() {
    widget.searchNotifier.removeListener(_onSearchChanged);
    editController.dispose();
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
              height: 50,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color:
                    widget.isTagMode
                        ? (uiController.secondaryColor ??
                            (uiController.darkMode.value
                                ? Color(0xFFF4FFF5)
                                : Color(0xFFF4FFF5)))
                        : uiController.getPopUpColors(widget.isTagMode),

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
                  ValueListenableBuilder<String>(
                    valueListenable: widget.searchNotifier,
                    builder: (context, searchText, child) {
                      final displayText =
                          searchText.trim().isEmpty
                              ? '${widget.isTagMode ? '#' : '@'}${widget.initialKeyword}'
                              : '${widget.isTagMode ? '#' : '@'}${searchText.trim()}';

                      return Text(
                        displayText,
                        style: TextStyle(
                          color:
                              (uiController.secondaryColor != null &&
                                      uiController.darkMode.value)
                                  ? Colors
                                      .white // White text for both @ and # in dark mode with color
                                  : Colors.black, // Black text otherwise

                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            Obx(
              () =>
                  controller.isEditing.value
                      ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            TextField(
                              controller: editController,
                              autofocus: true,
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
                                  child: const Text('Cancel'),
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
                                    style: AppFonts.medium(
                                      14,
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
                                .contains(trimmedSearchText);

                            return Obx(() {
                              return controller.filteredItems.isEmpty &&
                                      trimmedSearchText.isEmpty
                                  ? Center(
                                    child: Text(
                                      'No ${widget.isTagMode ? 'hashtags' : 'mentions'} available',
                                      style: TextStyle(
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
                                            const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      // Handle "add new item" case
                                      if (trimmedSearchText.isNotEmpty &&
                                          !hasExactMatch &&
                                          index == 0) {
                                        return Container(
                                          margin: const EdgeInsets.symmetric(
                                            // horizontal: 1,
                                            // vertical: 1,
                                          ),
                                          child: InkWell(
                                            onTap: () {
                                              controller.addNewItem(
                                                trimmedSearchText,
                                                widget.onItemSelected,
                                              );
                                            },
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 12,
                                                  ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Text(
                                                    '$prefixChar$trimmedSearchText',
                                                    style: TextStyle(
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
                                                  Text(
                                                    'add',
                                                    style: TextStyle(
                                                      color:
                                                          widget.isTagMode
                                                              ? Colors.green
                                                              : Colors.blue,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w400,
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

                                      return Container(
                                        height: 43,
                                        margin: const EdgeInsets.symmetric(
                                          // horizontal: 4,
                                          vertical: 2,
                                        ),
                                        child: InkWell(
                                          onTap: () {
                                            widget.onItemSelected(
                                              '$prefixChar$item',
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 10,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '$prefixChar$item',
                                                    style: TextStyle(
                                                      color:
                                                          widget.isTagMode
                                                              ? AppColors.green
                                                              : AppColors.blue,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: Image.asset(
                                                    AppImages.edit,
                                                    width: 20,
                                                    height: 20,
                                                    color:
                                                        uiController
                                                                .darkMode
                                                                .value
                                                            ? Colors.white
                                                            : Colors.black,
                                                  ),
                                                  onPressed: () {
                                                    controller.startEditing(
                                                      '$prefixChar$item',
                                                    );
                                                  },
                                                ),
                                                // IconButton(
                                                //   icon: const Icon(
                                                //     Icons.delete,
                                                //     size: 20,
                                                //     color: Colors.red,
                                                //   ),
                                                //   onPressed: () {
                                                //     controller.deleteItem(
                                                //       '$prefixChar$item',
                                                //     );
                                                //   },
                                                // ),
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
          ],
        ),
      ),
    );
  }
}
