import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../ui/controllers/ui_controller.dart';
import '../../controllers/add_memories_controller.dart';
import '../../../map/controllers/map_controller_new.dart';
import 'package:spacetime/app/modules/location_picker/views/new_location_picker_widget.dart';

class MemoriesFilterTextFieldRow extends StatefulWidget {
  final String imagePath;
  final String hint;

  const MemoriesFilterTextFieldRow({
    super.key,
    required this.imagePath,
    required this.hint,
  });

  @override
  State<MemoriesFilterTextFieldRow> createState() =>
      _MemoriesFilterTextFieldRowState();
}

class _MemoriesFilterTextFieldRowState
    extends State<MemoriesFilterTextFieldRow> {
  late TextEditingController _textController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get isDateField => widget.hint.toLowerCase().contains('date');
  bool get isLocationField =>
      widget.hint.toLowerCase().contains('location') &&
      !widget.hint.toLowerCase().contains('radius');
  bool get isRadiusField => widget.hint.toLowerCase().contains('radius');

  void _handleTextChanged(String value, dynamic controller) {
    if (value.contains('@') || value.contains('#')) {
      controller.onTextChanged(widget.hint, value);
    } else {
      controller.onTextChanged(widget.hint, value);
    }
  }

  // void _pickDate(BuildContext context, MemoryController controller) async {
  //       var uiController = Get.find<UiController>();

  //   if (picked != null) controller.setDate(picked);
  // }
  Future<void> _pickDate(BuildContext context, dynamic controller) async {
    var uiController = Get.find<UiController>();

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
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
    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      controller.setFilterDate(widget.hint, formatted);
    }
  }

  Future<void> _pickLocation(BuildContext context, dynamic controller) async {
    final result = await Get.to(() => const NewLocationPickerWidget());
    if (result != null) {
      // Extract location and radius from new location picker result
      final locationData = result['location'];
      final radius = result['radius'] ?? 10.0;

      // Convert to format expected by controller
      final enhancedLocationData = {
        'name': locationData['address'] ?? 'Selected Location',
        'address': locationData['address'] ?? '',
        'latitude': locationData['latitude'],
        'longitude': locationData['longitude'],
        'country': locationData['country'] ?? '',
        'region': locationData['state'] ?? '',
        'city': locationData['city'] ?? '',
        'timestamp': locationData['timestamp'] ?? DateTime.now().toIso8601String(),
        'type': locationData['type'] ?? 'selected',
        'source': locationData['source'] ?? 'location_picker',
      };

      controller.setEnhancedLocationData(enhancedLocationData);
      controller.setRadius(radius.toInt().toString());
      // No need to focus radius field since it's now concatenated with location
    }
  }

  @override
  Widget build(BuildContext context) {
    // Try to find MapControllerNew first (for map filter), then fallback to AddMemoriesController
    dynamic controller;
    try {
      controller = Get.find<MapControllerNew>();
      // Check if it's opened from map
      if (!controller.isOpenedFromMap) {
        throw Exception('Not opened from map');
      }
    } catch (e) {
      controller = Get.find<AddMemoriesController>();
    }

    final controller2 = Get.find<UiController>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Obx(() {
        final normalizedHint = widget.hint.trim().toLowerCase();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color:
                controller2.darkMode.value
                    ? Colors.white.withValues(alpha: 0.2)
                    : Colors.white,
          ),
          child: Row(
            children: [
              Image.asset(
                widget.imagePath,
                width: 18,
                height: 18,
                color: controller2.darkMode.value ? Colors.white : Colors.grey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap:
                      isDateField
                          ? () => _pickDate(context, controller)
                          : isLocationField
                          ? () => _pickLocation(context, controller)
                          : null,
                  child: AbsorbPointer(
                    absorbing: isDateField || isLocationField,
                    child: Obx(() {
                      // Determine the display value based on field type
                      // Update controller text when value changes
                      String currentValue;
                      if (isLocationField) {
                        // Concatenate location with radius using ' + '
                        String locationValue = controller.selectedLocation.value;
                        String radiusValue = controller.selectedRadius.value;

                        if (locationValue.isNotEmpty && radiusValue.isNotEmpty) {
                          currentValue = '$locationValue + ${radiusValue}km';
                        } else if (locationValue.isNotEmpty) {
                          currentValue = locationValue;
                        } else {
                          currentValue = widget.hint;
                        }
                      } else if (isRadiusField) {
                        currentValue = controller.selectedRadius.value;
                      } else {
                        currentValue =
                            controller.filterValues[normalizedHint] ?? '';
                      }

                      if (isLocationField) {
                        final isHint =
                            controller.selectedLocation.value.isEmpty;

                        if (!isHint && _textController.text != currentValue) {
                          _textController.text = currentValue;
                        }
                      } else {
                        if (_textController.text != currentValue) {
                          _textController.text = currentValue;
                        }
                      }
                      // Only update controller text if it's different to avoid cursor issues

                      return Obx(() {

                        return TextField(
                          style: GoogleFonts.kumbhSans(
                            color:
                                controller2.darkMode.value
                                    ? Colors.white
                                    : Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: widget.hint,
                            hintStyle: GoogleFonts.kumbhSans(
                              color:
                                  controller2.darkMode.value
                                      ? Colors.white54
                                      : Colors.grey[600],
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),


                          ),
                          controller: _textController,
                          onChanged:
                              (val) => _handleTextChanged(val, controller),
                          keyboardType: TextInputType.text,
                        );
                      });
                    }),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
