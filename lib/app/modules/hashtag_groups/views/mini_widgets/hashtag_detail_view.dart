import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_colors.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/hashtag_groups/controllers/hashtag_groups_controller.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

import '../../../../config/app_text.dart';
import '../../../../widgets/appbar.dart';

class HashtagDetailView extends GetView<HashtagGroupsController> {
  const HashtagDetailView({super.key});

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
            padding: const EdgeInsets.only(left: 13.0, top: 13, bottom: 13),
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
          child: Text('Sport', style: AppFonts.medium(20, color: Colors.white)),
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
                  controller.isEditing.value
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
                                controller: controller.editController,
                                autofocus: true,
                                onChanged:
                                    (val) => controller.editingItem.value = val,
                                decoration: InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  border: InputBorder.none,
                                  hintText: 'Edit hashtag',
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                GestureDetector(
                                  onTap: controller.cancelEditing,
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
                                    child: Image.asset(AppImages.rejectImg),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                GestureDetector(
                                  onTap:
                                      () => controller.saveEditedItem(
                                        controller.editingItem.value,
                                      ),
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
                          return controller.sportHashtags.isEmpty
                              ? Center(
                                child: Text(
                                  'No hashtags available',
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
                                itemCount: controller.sportHashtags.length,
                                separatorBuilder:
                                    (context, index) =>
                                        const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = controller.sportHashtags[index];
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
                                                color: AppColors.green,
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
                                                () => controller.startEditing(
                                                  item,
                                                ),
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
