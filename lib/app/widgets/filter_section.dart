import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:spacetime/app/modules/ui/controllers/ui_controller.dart';

class FilterPanel extends StatelessWidget {
  final List<Widget> children;
  final VoidCallback onReset;
  final VoidCallback onApply;

  const FilterPanel({
    super.key,
    required this.children,
    required this.onReset,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    return Material(
      elevation: 6,
      color:
          controller.darkMode.value
              ? controller.mainColor.value == 'blue'
                  ? Color(0xFF001937)
                  : controller.iconColor2
              : controller.mainColor.value == 'blue'
              ? Color(0xFF92C3FF)
              : controller.primaryColor,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...children,
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        controller.darkMode.value
                            ? Colors.white.withOpacity(0.2)
                            : Colors.white,
                    side: BorderSide(
                      color:
                          controller.darkMode.value
                              ? Colors.red.withOpacity(0.5)
                              : Colors.red,
                    ),
                  ),
                  onPressed: onReset,
                  child: Text(
                    'reset',
                    style: TextStyle(
                      color:
                          controller.darkMode.value ? Colors.red : Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        controller.darkMode.value
                            ? Colors.white.withOpacity(0.2)
                            : Colors.white,
                    side: const BorderSide(color: Colors.blue),
                  ),
                  onPressed: onApply,
                  child: const Text(
                    'filter',
                    style: TextStyle(color: Colors.blue),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
