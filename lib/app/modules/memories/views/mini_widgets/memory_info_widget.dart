import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/config/app_fonts.dart';
import 'package:spacetime/app/config/app_images.dart';
import 'package:spacetime/app/modules/memories/controllers/memory_controller.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/memory_location_picker_widget.dart';
import 'package:spacetime/app/shared/widgets/searchable_category_widget.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

class MemoryInfoWidget extends StatelessWidget {
  const MemoryInfoWidget({super.key});

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
                    () => _InfoContainer(
                      imagePath: AppImages.calendar,
                      text:
                          controller.selectedDate.value != null
                              ? "${controller.selectedDate.value!.day.toString().padLeft(2, '0')}.${controller.selectedDate.value!.month.toString().padLeft(2, '0')}.${controller.selectedDate.value!.year}"
                              : "Pick Date",
                      onTap: () => _pickDate(context, controller),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Obx(
                    () => _InfoContainer(
                      imagePath: AppImages.clock,
                      text:
                          controller.selectedTime.value != null
                              ? controller.selectedTime.value!.format(context)
                              : "Pick Time",
                      onTap: () => _pickTime(context, controller),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),

            // Location (Required)
            Obx(
              () => _InfoContainer(
                imagePath: AppImages.location,
                text:
                    controller.selectedLocation.value.isNotEmpty
                        ? '${controller.locationFlag.value} ${controller.locationCity.value}, ${controller.locationCountry.value}'
                        : 'Pick Location *',
                onTap: () async {
                  var data = await Get.to(() => const MemoryLocationPickerWidget());
                  controller.onAgainInit();

                  // Use the new enhanced location method
                  controller.setEnhancedLocationData(data);
                  // Call onAgainInit when returning from location picker (user preference)
                },
                isRequired: true, // Location is required for saving memories
              ),
            ),

            const SizedBox(height: 5),

            // Place Category - Searchable
            SearchableCategoryWidget(
              selectedCategory: controller.selectedCategory.value,
              onCategorySelected: (category) {
                final categoryWithEmoji = category.emoji.isNotEmpty
                    ? '${category.emoji} ${category.name}'
                    : category.name;
                controller.setCategory(categoryWithEmoji);
              },
              backgroundColor: controller2.darkMode.value
                  ? Colors.black.withValues(alpha: 0.5)
                  : Colors.white,
              allowMultipleSelectionInPicker: false, // Single selection mode for Memory Info Widget
            ),
          ],
        ),
      ),
    );
  }

  void _pickDate(BuildContext context, MemoryController controller) async {
    var uiController = Get.find<UiController>();

    final picked = await showDatePicker(
      context: context,
      initialDate: controller.selectedDate.value ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            colorScheme:
                uiController.darkMode.value
                    ? ColorScheme.dark(
                      primary:
                          uiController
                              .currentMainColor, // Header background and selected elements
                      onPrimary: Colors.white, // Header text color
                      surface: const Color(
                        0xFF1E1E1E,
                      ), // Calendar background color (dark)
                      onSurface:
                          Colors
                              .white, // Calendar text color (white for dark mode)
                      secondary:
                          uiController.currentMainColor, // Secondary elements
                      onSecondary: Colors.white,
                      outline:
                          Colors
                              .grey[600]!, // Border colors (darker for dark mode)
                      surfaceContainerHighest: const Color(
                        0xFF2E2E2E,
                      ), // Today's date background (dark)
                      onSurfaceVariant:
                          Colors
                              .white, // Today's date text (light for dark mode)
                      surfaceTint:
                          Colors.transparent, // Remove any surface tint
                    )
                    : ColorScheme.light(
                      primary:
                          uiController
                              .currentMainColor, // Header background and selected elements
                      onPrimary: Colors.white, // Header text color
                      surface: Colors.white, // Calendar background color
                      onSurface: Colors.black, // Calendar text color
                      secondary:
                          uiController.currentMainColor, // Secondary elements
                      onSecondary: Colors.white,
                      outline: Colors.grey[300]!, // Border colors
                      surfaceContainerHighest:
                          Colors.white, // Today's date background
                      onSurfaceVariant: Colors.black, // Today's date text
                      surfaceTint:
                          Colors.transparent, // Remove any surface tint
                    ),
            dialogTheme: DialogThemeData(
              backgroundColor:
                  uiController.darkMode.value
                      ? const Color(0xFF1E1E1E) // Dark mode dialog background
                      : Colors.white, // Light mode dialog background
              surfaceTintColor: Colors.transparent, // Remove surface tint
              shadowColor: Colors.transparent,
            ),

            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor:
                    uiController.currentMainColor, // Button text color
              ),
            ),
            datePickerTheme: DatePickerThemeData(
              backgroundColor:
                  uiController.darkMode.value
                      ? const Color(
                        0xFF1E1E1E,
                      ) // Dark mode date picker background
                      : Colors.white, // Light mode date picker background
              surfaceTintColor: Colors.transparent, // Remove surface tint
              shadowColor: Colors.transparent, // Remove shadow tint
              headerBackgroundColor:
                  uiController.currentMainColor, // Header background
              headerForegroundColor: Colors.white, // Header text color
              dayForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white; // Selected date text color
                }
                if (states.contains(WidgetState.disabled)) {
                  return uiController.darkMode.value
                      ? Colors
                          .grey[600] // Light grey for dark mode disabled dates
                      : Colors.grey[400]; // Grey for light mode disabled dates
                }
                return uiController.darkMode.value
                    ? Colors.white
                    : Colors.black; // Regular date text color
              }),
              dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return uiController
                      .currentMainColor; // Selected date background
                }
                return Colors.transparent; // Regular date background
              }),
              todayForegroundColor: WidgetStateProperty.all(
                uiController.currentMainColor,
              ), // Today's date text
              todayBackgroundColor: WidgetStateProperty.all(
                Colors.transparent,
              ), // Today's date background
              yearForegroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white; // Selected year text color
                }
                return uiController.darkMode.value
                    ? Colors.white
                    : Colors.black; // Regular year text color
              }),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              // // color: uiController.darkMode.value
              //     ? const Color(0xFF1E1E1E) // Dark mode container background
              //     : Colors.white, // Light mode container background
              borderRadius: BorderRadius.circular(12),
            ),
            child: child!,
          ),
        );
      },
    );
    if (picked != null) controller.setDate(picked);
  }

  void _pickTime(BuildContext context, MemoryController controller) async {
    var uiController = Get.find<UiController>();
    final picked = await showTimePicker(
      context: context,
      initialTime: controller.selectedTime.value ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:
                uiController.darkMode.value
                    ? ColorScheme.dark(
                      primary:
                          uiController
                              .currentMainColor, // Header background and selected elements
                      onPrimary: Colors.white, // Header text color
                      surface: const Color(
                        0xFF1E1E1E,
                      ), // Time picker background color (dark)
                      onSurface:
                          Colors
                              .white, // Time picker text color (white for dark mode)
                      secondary:
                          uiController
                              .currentMainColor, // Clock hands and selected time
                      onSecondary: Colors.white,
                      outline:
                          Colors
                              .grey[600]!, // Clock circle and lines (darker for dark mode)
                      surfaceContainerHighest: const Color(
                        0xFF2E2E2E,
                      ), // Clock face background (dark)
                      onSurfaceVariant:
                          Colors
                              .grey[400]!, // Clock numbers (lighter for dark mode)
                      tertiary:
                          uiController.currentMainColor, // AM/PM selection
                      onTertiary: Colors.white,
                    )
                    : ColorScheme.light(
                      primary:
                          uiController
                              .currentMainColor, // Header background and selected elements
                      onPrimary: Colors.white, // Header text color
                      surface: Colors.white, // Time picker background color
                      onSurface: Colors.black, // Time picker text color
                      secondary:
                          uiController
                              .currentMainColor, // Clock hands and selected time
                      onSecondary: Colors.white,
                      outline: Colors.grey[400]!, // Clock circle and lines
                      surfaceContainerHighest:
                          Colors.grey[100]!, // Clock face background
                      onSurfaceVariant: Colors.grey[500]!, // Clock numbers
                      tertiary:
                          uiController.currentMainColor, // AM/PM selection
                      onTertiary: Colors.white,
                    ),
            dialogTheme: DialogThemeData(
              backgroundColor:
                  uiController.darkMode.value
                      ? const Color(0xFF1E1E1E) // Dark mode dialog background
                      : Colors.white, // Light mode dialog background
            ),
            scaffoldBackgroundColor:
                uiController.darkMode.value
                    ? const Color(0xFF1E1E1E) // Dark mode scaffold background
                    : Colors.white, // Light mode scaffold background
            cardTheme: CardThemeData(
              color:
                  uiController.darkMode.value
                      ? const Color(0xFF1E1E1E) // Dark mode card background
                      : Colors.white, // Light mode card background
              surfaceTintColor: Colors.transparent, // Remove surface tint
              shadowColor: Colors.transparent, // Remove shadow
            ),
            appBarTheme: AppBarTheme(
              backgroundColor:
                  uiController.darkMode.value
                      ? const Color(0xFF1E1E1E) // Dark mode app bar background
                      : Colors.white, // Light mode app bar background
              surfaceTintColor: Colors.transparent, // Remove surface tint
            ),
            bottomSheetTheme: BottomSheetThemeData(
              backgroundColor:
                  uiController.darkMode.value
                      ? const Color(
                        0xFF1E1E1E,
                      ) // Dark mode bottom sheet background
                      : Colors.white, // Light mode bottom sheet background
              surfaceTintColor: Colors.transparent, // Remove surface tint
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor:
                    uiController.currentMainColor, // Button text color
              ),
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor:
                  uiController.darkMode.value
                      ? const Color(
                        0xFF1E1E1E,
                      ) // Dark mode time picker background
                      : Colors.white, // Light mode time picker background
              hourMinuteTextColor:
                  uiController.darkMode.value
                      ? Colors
                          .white // Dark mode hour/minute text color
                      : Colors.black, // Light mode hour/minute text color
              dayPeriodTextColor:
                  uiController.darkMode.value
                      ? Colors
                          .white // Dark mode AM/PM text color
                      : Colors.black, // Light mode AM/PM text color
              dialHandColor: uiController.currentMainColor, // Clock hand color
              dialBackgroundColor:
                  uiController.darkMode.value
                      ? const Color(
                        0xFF2E2E2E,
                      ) // Dark mode clock face background
                      : Colors.grey[100], // Light mode clock face background
              dialTextColor:
                  uiController.darkMode.value
                      ? Colors
                          .white // Dark mode clock numbers color
                      : Colors.black, // Light mode clock numbers color
              entryModeIconColor:
                  uiController.currentMainColor, // Mode switch icon
              helpTextStyle: TextStyle(
                color:
                    uiController.darkMode.value
                        ? Colors
                            .white54 // Dark mode help text
                        : Colors.black54, // Light mode help text
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) controller.setTime(picked);
  }
}

class _InfoContainer extends StatelessWidget {
  final String imagePath;
  final String text;
  final VoidCallback? onTap;
  final bool isRequired;

  const _InfoContainer({
    required this.imagePath,
    required this.text,
    this.onTap,
    this.isRequired = false,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return InkWell(
      onTap: onTap,
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
                    if (isRequired)
                      Text(
                        ' *',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.bold,
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
