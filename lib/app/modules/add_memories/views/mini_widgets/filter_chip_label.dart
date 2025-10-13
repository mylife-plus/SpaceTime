import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';

import '../../../ui/controllers/ui_controller.dart';

class MemoriesFilterChipLabel extends StatelessWidget {
  final String label;

  const MemoriesFilterChipLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();
    final isMention = label.startsWith('@');
    final isTag = label.startsWith('#');

    final borderColor =
        isMention
            ? Colors.green
            : isTag
            ? Colors.blue
            : Colors.grey;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color:
              controller.darkMode.value
                  ? Colors.white.withOpacity(0.2)
                  : Colors.white,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: controller.darkMode.value ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }
}
