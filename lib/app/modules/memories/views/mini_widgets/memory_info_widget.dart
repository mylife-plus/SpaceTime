import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_location_picker_controller.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/memory_location_picker_widget.dart';
import 'package:spacetime/app/modules/memories/utils/memory_location_line_format.dart';
import 'package:spacetime/app/shared/widgets/searchable_category_widget.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import 'package:spacetime/app/widgets/app_date_time_pickers.dart';

class MemoryInfoWidget extends StatelessWidget {
  final VoidCallback? onCategorySelected;
  final VoidCallback? onAnyWidgetTapped;

  const MemoryInfoWidget({
    super.key,
    this.onCategorySelected,
    this.onAnyWidgetTapped,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MemoryController>();
    final controller2 = Get.find<UiController>();

    return Obx(
      () => Container(
        padding: const EdgeInsets.only(bottom: 1.5),

        // color: Colors.black.withOpacity(0.05),
        color:
            controller2.darkMode.value
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.05),
        child: Column(
          children: [
            // Row with Date & Time
            Row(
              children: [
                Expanded(
                  child: Obx(
                    () {
                      controller2.selectedLanguage.value;
                      String dateText = 'text_memory_pick_date'.tr;
                      if (controller.selectedDate.value != null) {
                        final selectedDate = controller.selectedDate.value!;

                        // if (selected == today) {
                        //   dateText = "Today";
                        // } else if (selected == yesterday) {
                        //   dateText = "Yesterday";
                        // } else {
                          dateText = "${selectedDate.day.toString().padLeft(2, '0')}.${selectedDate.month.toString().padLeft(2, '0')}.${selectedDate.year}";
                        // }
                      }

                      return _InfoContainer(
                        imagePath: AppImages.calendar,
                        text: dateText,
                        onTap: () async {
                          if (onAnyWidgetTapped != null) {
                            onAnyWidgetTapped!();
                          }
                          
                          // await Future.delayed(Duration(seconds: 2));

                          _pickDate(context, controller);
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Obx(
                    () {
                      controller2.selectedLanguage.value;
                      return _InfoContainer(
                      imagePath: AppImages.clock,
                      text:
                          controller.selectedTime.value != null
                              ? controller.selectedTime.value!.format(context)
                              : 'text_memory_pick_time'.tr,
                      onTap: () {
                        if (onAnyWidgetTapped != null) {
                          onAnyWidgetTapped!();
                        }
                        _pickTime(context, controller);
                      },
                    );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),

            // Location (Required)
            Obx(
              () {
                controller2.selectedLanguage.value;
                final hasLocation = controller.selectedLocation.value.isNotEmpty;
                final text = hasLocation
                    ? MemoryLocationLineFormat.displayLine(
                        flag: controller.locationFlag.value,
                        locationCity: controller.locationCity.value,
                        locationName: controller.locationName.value,
                        locationCountry: controller.locationCountry.value,
                        lat: controller.locationLatitude.value,
                        lng: controller.locationLongitude.value,
                      )
                    : controller.isFetchingLocation.value
                        ? 'text_memory_searching_location'.tr
                        : controller.locationFieldPlaceholderText;

                return _LocationInfoContainer(
                  imagePath: AppImages.location,
                  text: text,
                  isRequired: !hasLocation,
                  onTap: () async {
                    if (onAnyWidgetTapped != null) {
                      onAnyWidgetTapped!();
                    }

                    Get.put(
                      MemoryLocationPickerController(),
                      permanent: true,
                    );

                    final data = await Get.to(
                      () => const MemoryLocationPickerWidget(),
                    );

                    // Only update location if user pressed done (data is not null)
                    if (data != null) {
                      controller.setEnhancedLocationData(data);
                    }
                  },
                );
              },
            ),

            const SizedBox(height: 5),

            // Place Category - Searchable
            GestureDetector(
              onTap: () {
                if (onAnyWidgetTapped != null) {
                  onAnyWidgetTapped!();
                }
              },
              behavior: HitTestBehavior.opaque, // Prevent tap from propagating
              child: SearchableCategoryWidget(
                selectedCategory: controller.selectedCategory.value,
                onCategorySelected: (category) {
                  final categoryWithEmoji = category.emoji.isNotEmpty
                      ? '${category.emoji} ${category.name}'
                      : category.name;
                  controller.setCategory(categoryWithEmoji);

                  // Unfocus description field after category selection
                  if (onCategorySelected != null) {
                    onCategorySelected!();
                  }
                },
                onSelectedCategoryDeleted: () {
                  // Clear the selected category when it's deleted
                  controller.setCategory('');
                  debugPrint('[MemoryInfoWidget] Cleared selected category after deletion');
                },
                backgroundColor: controller2.darkMode.value
                    ? Colors.black.withValues(alpha: 0.5)
                    : Colors.white,
                allowMultipleSelectionInPicker: false,
                saveToRecent: true, // Single selection mode for Memory Info Widget
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _pickDate(BuildContext context, MemoryController controller) async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: controller.selectedDate.value ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) controller.setDate(picked);
  }

  void _pickTime(BuildContext context, MemoryController controller) async {
    final picked = await showAppTimePicker(
      context: context,
      initialTime: controller.selectedTime.value ?? TimeOfDay.now(),
    );
    if (picked != null) controller.setTime(picked);
  }
}

class _InfoContainer extends StatelessWidget {
  final String imagePath;
  final String text;
  final VoidCallback? onTap;

  const _InfoContainer({
    required this.imagePath,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque, // Prevent tap from propagating to widgets below
      child: Obx(
        () => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            // color: Colors.white,
            color:
                controller.darkMode.value
                    ? Colors.black.withValues(alpha: 0.5)
                    : Colors.white,
            // borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Image.asset(
                imagePath,
                width: 20,
                height: 20,
                // color: Colors.grey[600],
                color:
                    controller.darkMode.value ? Colors.white : Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        text,
                        style: AppFonts.medium(
                          17,
                          color:
                              controller.darkMode.value
                                  ? Colors.white
                                  : Colors.grey[700]!,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationInfoContainer extends StatelessWidget {
  final String imagePath;
  final String text;
  final VoidCallback onTap;
  final bool isRequired;

  const _LocationInfoContainer({
    required this.imagePath,
    required this.text,
    required this.onTap,
    required this.isRequired,
  });

  @override
  Widget build(BuildContext context) {
    final uiController = Get.find<UiController>();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: uiController.darkMode.value
            ? Colors.black.withValues(alpha: 0.5)
            : Colors.white,
      ),
      child: Row(
        children: [
          Image.asset(
            imagePath,
            width: 20,
            height: 20,
            color: uiController.darkMode.value ? Colors.white : Colors.grey[600],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: AppFonts.medium(
                        17,
                        color: uiController.darkMode.value
                            ? Colors.white
                            : Colors.grey[700]!,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isRequired)
                    Text(
                      'text_3'.tr,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.red.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
