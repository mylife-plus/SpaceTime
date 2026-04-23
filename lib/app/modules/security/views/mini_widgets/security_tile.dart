import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get/get_core/src/get_main.dart';

import '../../../ui/controllers/ui_controller.dart';

class SecurityTile extends StatelessWidget {
  final String title;
  final bool isActive;
  final ValueChanged<bool>? onChanged;

  const SecurityTile({
    super.key,
    required this.title,
    required this.isActive,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<UiController>();

    return Column(
      children: [
        Obx(
          () => Container(
            color: controller.darkMode.value ? controller.darkSurfaceColor : Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: isActive,
                    onChanged: onChanged,
                    activeColor: Colors.white,
                    activeTrackColor: Colors.blue,
                    inactiveThumbColor: Colors.grey.shade300,
                    inactiveTrackColor: Colors.grey.shade400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
