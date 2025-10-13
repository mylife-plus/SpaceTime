import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';
import '../../controllers/map_controller.dart';
import 'package:spacetime/app/modules/memories/views/mini_widgets/location_picker_widget.dart';

class FilterTextFieldRow extends StatelessWidget {
  final String imagePath;
  final String hint;

  const FilterTextFieldRow({
    super.key,
    required this.imagePath,
    required this.hint,
  });

  bool get isDateField => hint.toLowerCase().contains('date');
  bool get isLocationField => hint.toLowerCase().contains('location');

  void _handleTextChanged(String value, MapController controller) {
    if (value.contains('@') || value.contains('#')) {
      controller.onTextChanged(hint, value);
    }
  }

  Future<void> _pickDate(BuildContext context, MapController controller) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      final formatted = DateFormat('yyyy-MM-dd').format(picked);
      controller.setFilterDate(hint, formatted);
    }
  }

  Future<void> _pickLocation(
    BuildContext context,
    MapController controller,
  ) async {
    final result = await Get.to(() => const LocationPickerWidget());
    if (result != null) {
      controller.setEnhancedLocationData(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<MapController>();
    final controller2 = Get.find<UiController>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
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
              imagePath,
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
                    // For location field, show selectedLocation from controller
                    final value =
                        isLocationField
                            ? controller.selectedLocation.value.isNotEmpty
                                ? controller.selectedLocation.value
                                : hint
                            : controller.filterValues[hint] ?? '';

                    return TextField(
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: hint,
                      ),
                      controller: TextEditingController(text: value),
                      onChanged: (val) => _handleTextChanged(val, controller),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
