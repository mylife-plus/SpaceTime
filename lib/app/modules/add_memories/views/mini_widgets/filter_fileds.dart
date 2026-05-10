import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/memory_location_picker_widget_with_radius.dart';
import 'package:spacetime/app/widgets/app_date_time_pickers.dart';
import 'package:spacetime/app/l10n/l10n_loader.dart';

import '../../../ui/controllers/ui_controller.dart';
import '../../controllers/add_memories_controller.dart';
import '../../../map/controllers/map_controller_new.dart';

class MemoriesFilterTextFieldRow extends StatefulWidget {
  final String imagePath;
  /// Localized placeholder / empty label for the field.
  final String hint;
  /// Canonical map key for filter state (e.g. `from date`, never translated).
  final String filterStorageKey;
  final double? borderRadius;

  MemoriesFilterTextFieldRow({
    super.key,
    required this.imagePath,
    required this.hint,
    required this.filterStorageKey,
    this.borderRadius,
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

  String get _storageKey =>
      widget.filterStorageKey.trim().toLowerCase();

  bool get isDateField =>
      _storageKey == 'from date' || _storageKey == 'to date';
  bool get isLocationField => _storageKey == 'location';
  bool get isRadiusField => _storageKey.contains('radius');

  String _formatRadiusForFilterDisplay(String radiusValue, String lang) {
    final d = double.tryParse(radiusValue.replaceAll(',', '.'));
    if (d == null) return radiusValue;
    return formatLocaleOneDecimal(d, lang);
  }

  void _handleTextChanged(String value, dynamic controller) {
    if (value.contains('@')) {
      debugPrint('Mention trigger from [${widget.filterStorageKey}]: $value');
    } else if (value.contains('#')) {
      debugPrint('Tag trigger from [${widget.filterStorageKey}]: $value');
    }
    controller.onTextChanged(widget.filterStorageKey, value);
  }

  // void _pickDate(BuildContext context, MemoryController controller) async {
  //       var uiController = Get.find<UiController>();

  //   if (picked != null) controller.setDate(picked);
  // }
  DateTime? _parsedStoredDate(dynamic controller) {
    final raw = controller.filterValues[_storageKey];
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  DateTime _initialDateForPicker(dynamic controller) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final first = DateTime(1900);
    final parsed = _parsedStoredDate(controller);
    if (parsed == null) return today;
    var d = DateTime(parsed.year, parsed.month, parsed.day);
    if (d.isBefore(first)) return first;
    if (d.isAfter(today)) return today;
    return d;
  }

  Future<void> _pickDate(BuildContext context, dynamic controller) async {
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _initialDateForPicker(controller),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      controller.setFilterDate(widget.filterStorageKey, formatted);
    }
  }

  Future<void> _pickLocation(BuildContext context, dynamic controller) async {
    debugPrint('🎯 [FilterFields] Opening MemoryLocationPickerWithRadius');

    debugPrint('🎯 [FilterFields] Navigating to MemoryLocationPickerWidgetWithRadius');
    final result = await Get.to(
      () => const MemoryLocationPickerWidgetWithRadius(),
      fullscreenDialog: true,
    );

    debugPrint('🎯 [FilterFields] Location picker returned: $result');

    if (result != null) {
      // Extract location and radius from new location picker result
      final locationData = result['location'];
      final radius = result['radius'] ?? 10.0;

      debugPrint('🎯 [FilterFields] Extracted locationData: $locationData');
      debugPrint('🎯 [FilterFields] Extracted radius: $radius');

      var locationName = '${locationData['location_flag']} ${locationData['city']}';
      // Convert to format expected by controller
      final enhancedLocationData = {
        'name':locationName ??  'Selected Location',
        'address': locationData['address'] ?? '',
        'latitude': locationData['latitude'],
        'longitude': locationData['longitude'],
        'country': locationData['country'] ?? '',
        'location_flag': locationData['location_flag'] ?? '', // Add location flag
        'region': locationData['state'] ?? '',
        'city': locationData['city'] ?? '',
        'timestamp': locationData['timestamp'] ?? DateTime.now().toIso8601String(),
        'type': locationData['type'] ?? 'selected',
        'source': locationData['source'] ?? 'location_picker',
      };

      debugPrint('🎯 [FilterFields] Calling setEnhancedLocationData with: $enhancedLocationData');
      controller.setEnhancedLocationData(enhancedLocationData);

      debugPrint('🎯 [FilterFields] Calling setRadius with: ${radius.toDouble()}');
controller.setRadius(radius.toDouble().toStringAsFixed(1));

      debugPrint('🎯 [FilterFields] After setting - selectedLocation: ${controller.selectedLocation.value}');
      debugPrint('🎯 [FilterFields] After setting - selectedLocationDisplayName: ${controller.selectedLocationDisplayName.value}');
      debugPrint('🎯 [FilterFields] After setting - selectedRadius: ${controller.selectedRadius.value}');
    } else {
      debugPrint('🎯 [FilterFields] Location picker returned null');
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
        final storageKey = _storageKey;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color:
                controller2.darkMode.value
                    ? controller2.darkSurfaceColor
                    : Colors.white,
            borderRadius: widget.borderRadius != null
                ? BorderRadius.circular(widget.borderRadius!)
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                widget.imagePath,
                width: 20,
                height: 20,
                color: controller2.darkMode.value
                    ? Colors.white
                    : Colors.grey[600],
              ),
              const SizedBox(width: 8),
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
                      final lang = controller2.selectedLanguage.value;
                      // Determine the display value based on field type
                      // Update controller text when value changes
                      String currentValue;
                      if (isLocationField) {
                        // Use display name if available, otherwise use coordinates
                        String locationValue = controller.selectedLocationDisplayName.value.isNotEmpty
                            ? controller.selectedLocationDisplayName.value
                            : controller.selectedLocation.value;
                        String radiusValue = controller.selectedRadius.value;
                        final kmUnit = trForLang('text_distance_unit_km', lang);

                        if (locationValue.isNotEmpty && radiusValue.isNotEmpty) {
                          currentValue =
                              '$locationValue + ${_formatRadiusForFilterDisplay(radiusValue, lang)}$kmUnit';
                        } else if (locationValue.isNotEmpty) {
                          currentValue = locationValue;
                        } else {
                          currentValue = widget.hint;
                        }
                      } else if (isRadiusField) {
                        currentValue = controller.selectedRadius.value;
                      } else {
                        currentValue =
                            controller.filterValues[storageKey] ?? '';
                      }

                      if (isLocationField) {
                        final isHint =
                            controller.selectedLocationDisplayName.value.isEmpty &&
                            controller.selectedLocation.value.isEmpty;

                        // Update text controller when value changes OR when clearing (isHint)
                        if (_textController.text != currentValue) {
                          if (!isHint) {
                            // Set the location value
                            _textController.text = currentValue;
                          } else {
                            // Clear the text when location is cleared
                            _textController.clear();
                          }
                        }
                      } else {
                        if (_textController.text != currentValue) {
                          _textController.text = currentValue;
                        }
                      }
                      // Only update controller text if it's different to avoid cursor issues

                      return Obx(() {
                        final lang = controller2.selectedLanguage.value;
                        final kmUnit = trForLang('text_distance_unit_km', lang);
                        // For location field with radius, use RichText for colored radius
                        if (isLocationField && (controller.selectedLocationDisplayName.value.isNotEmpty || controller.selectedLocation.value.isNotEmpty) && controller.selectedRadius.value.isNotEmpty) {
                          // Use display name if available, otherwise use coordinates
                          String locationValue = controller.selectedLocationDisplayName.value.isNotEmpty
                              ? controller.selectedLocationDisplayName.value
                              : controller.selectedLocation.value;
                          String radiusValue = controller.selectedRadius.value;
                          final radiusFormatted =
                              _formatRadiusForFilterDisplay(radiusValue, lang);

                          return SizedBox(
                            height: 22,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: RichText(
                                text: TextSpan(
                                  text: '$locationValue + ',
                                  style: GoogleFonts.kumbhSans(
                                    color:
                                        controller2.darkMode.value
                                            ? Colors.white
                                            : Colors.black,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    height: 1.2,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: '$radiusFormatted$kmUnit',
                                      style: GoogleFonts.kumbhSans(
                                        color: controller2.currentMainColor,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w400,
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return SizedBox(
                          height: 22,
                          child: TextField(
                            style: GoogleFonts.kumbhSans(
                              color:
                                  controller2.darkMode.value
                                      ? Colors.white
                                      : Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                            ),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              hintText: widget.hint,
                              hintStyle: GoogleFonts.kumbhSans(
                                color:
                                    controller2.darkMode.value
                                        ? Colors.white54
                                        : Colors.grey[700],
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            controller: _textController,
                            onChanged:
                                (val) => _handleTextChanged(val, controller),
                            keyboardType: TextInputType.text,
                          ),
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
