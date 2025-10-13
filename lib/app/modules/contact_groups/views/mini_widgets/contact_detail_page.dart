import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_colors.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/contact_groups/controllers/contact_groups_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import '../../../../config/app_text.dart';
import '../../../../widgets/appbar.dart';

class ContactDetailPage extends StatefulWidget {
  const ContactDetailPage({super.key});

  @override
  State<ContactDetailPage> createState() => _ContactDetailPage();
}

class _ContactDetailPage extends State<ContactDetailPage> {
  final TextEditingController editController = TextEditingController();
  final RxBool isEditing = false.obs;
  final RxString editingItem = ''.obs;
  final RxString originalItem = ''.obs; // Add this to store the original item
  final RxList<String> homeMentions =
      <String>[
        'mother',
        'father',
        'brother',
        'sister',
        'grandparents',
        'cousins',
      ].obs;

  @override
  void initState() {
    super.initState();

    ever(isEditing, (editing) {
      if (editing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          editController.text = editingItem.value;
          editController.selection = TextSelection.fromPosition(
            TextPosition(offset: editController.text.length),
          );
        });
      }
    });
  }

  void _startEditing(String item) {
    originalItem.value = item; // Store original item for reference
    editingItem.value = item;
    isEditing.value = true;
  }

  void _cancelEditing() {
    isEditing.value = false;
    editingItem.value = '';
    originalItem.value = '';
  }

  void _saveEditedItem(String newValue) {
    if (newValue.trim().isNotEmpty) {
      final oldItem = originalItem.value;
      final index = homeMentions.indexOf(oldItem);
      if (index != -1) {
        homeMentions[index] = newValue.trim();
      }
    }
    _cancelEditing();
  }

  @override
  void dispose() {
    editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Scaffold(
      backgroundColor:
          uiController.darkMode.value
              ? Colors.black
              : uiController.getLightModeBackgroundColor(
                uiController.mainColor.value,
              ),
      appBar: AppBar(
        leading: GestureDetector(
          onTap: Get.back,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Image.asset(
              AppImages.arrowBack,
              width: 15,
              height: 15,
              fit: BoxFit.contain,
            ),
          ),
        ),
        backgroundColor:
            uiController.darkMode.value
                ? uiController.mainColor.value == 'blue'
                    ? Color(0xFF001937)
                    : uiController.primaryColorDark
                : uiController.currentMainColor,
        title: Center(
          child: Text(
            'Family',
            style: AppFonts.medium(20, color: Colors.white),
          ),
        ),
        actions: [Icon(Icons.sports, color: Colors.transparent, size: 50)],
      ),

      body: Container(
        decoration: BoxDecoration(
          color: uiController.darkMode.value ? Colors.black : Colors.white,
        ),
        child: Column(
          children: [
            Obx(
              () =>
                  isEditing.value
                      ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color:
                                    uiController.darkMode.value
                                        ? Colors.black
                                        : Colors.white,
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextField(
                                controller: editController,
                                autofocus: true,
                                onChanged: (val) => editingItem.value = val,
                                decoration: InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  border: InputBorder.none,
                                  hintText: 'Edit group',
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                GestureDetector(
                                  onTap: _cancelEditing,
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    padding: EdgeInsets.all(17),
                                    decoration: BoxDecoration(
                                      // color:
                                      //     uiController.darkMode.value
                                      //         ? uiController.mainColor.value ==
                                      //                 'blue'
                                      //             ? Colors.black
                                      //             : uiController.secondaryColor
                                      //         : uiController.mainColor.value ==
                                      //             'blue'
                                      //         ? Colors.white
                                      //         : uiController.primaryColor,
                                      color:
                                          uiController.darkMode.value
                                              ? Colors.grey[900]
                                              : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          // color: Colors.black.withOpacity(0.1),
                                          color:
                                              uiController.darkMode.value
                                                  ? Colors.white.withOpacity(
                                                    0.1,
                                                  )
                                                  : Colors.black.withOpacity(
                                                    0.1,
                                                  ),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Image.asset(AppImages.rejectImg),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                GestureDetector(
                                  onTap:
                                      () => _saveEditedItem(editingItem.value),
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    padding: EdgeInsets.all(17),
                                    decoration: BoxDecoration(
                                      color:
                                          uiController.darkMode.value
                                              ? Colors.grey[900]
                                              : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          // color: Colors.black.withOpacity(0.1),
                                          color:
                                              uiController.darkMode.value
                                                  ? Colors.white.withOpacity(
                                                    0.1,
                                                  )
                                                  : Colors.black.withOpacity(
                                                    0.1,
                                                  ),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Image.asset(AppImages.acceptImg),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                      : Expanded(
                        child: Obx(() {
                          return homeMentions.isEmpty
                              ? Center(
                                child: Text(
                                  'No groups available',
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
                                itemCount: homeMentions.length,
                                separatorBuilder:
                                    (context, index) =>
                                        const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = homeMentions[index];

                                  return Container(
                                    height: 43,
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 10),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item,
                                              style: TextStyle(
                                                color: AppColors.blue,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: Image.asset(
                                              AppImages.edit,
                                              width: 20,
                                              height: 20,
                                              color:
                                                  uiController.darkMode.value
                                                      ? Colors.white
                                                      : Colors.black,
                                            ),
                                            onPressed:
                                                () => _startEditing(
                                                  item,
                                                ), // Pass item without #
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                        }),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
